"""Python API for the unchanged V3 planner, isolated in a bounded Node process.

Node >=22.18 is the only runtime dependency. Provider credentials are passed in
the child environment, never command arguments, JSON requests, or error text.
"""

from __future__ import annotations

import asyncio
import json
import os
from pathlib import Path
import shutil
import signal
from typing import Any, Protocol
import weakref


class PlannerSettings(Protocol):
    openai_api_key: str
    typesafe_api_key: str
    openai_model: str
    typesafe_model: str


_WORKER = Path(__file__).with_name("worker.mjs")
_TIMEOUT_SECONDS = 75.0
_INPUT_LIMIT = 4_600_000
_OUTPUT_LIMIT = 2_000_000
_STDERR_LIMIT = 64_000
_MAX_WORKERS = 2
_limiters: weakref.WeakKeyDictionary[Any, asyncio.Semaphore] = weakref.WeakKeyDictionary()


def _failure(code: str, message: str, status: int = 502) -> dict[str, Any]:
    return {"httpStatus": status, "response": {"error": {"code": code, "message": message}}}


def _setting(settings: PlannerSettings, key: str) -> str:
    value = getattr(settings, key, "")
    return value.strip() if isinstance(value, str) else ""


def _environment(settings: PlannerSettings) -> dict[str, str]:
    # Do not inherit NODE_OPTIONS, loader hooks, proxy credentials, or unrelated
    # server secrets. Node uses its standard TLS certificate store.
    return {
        "PATH": os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin"),
        "LANG": "C.UTF-8",
        "NODE_NO_WARNINGS": "1",
        "OPENAI_API_KEY": _setting(settings, "openai_api_key"),
        "TYPESAFE_API_KEY": _setting(settings, "typesafe_api_key"),
        "OPENAI_MODEL": _setting(settings, "openai_model"),
        "TYPESAFE_MODEL": _setting(settings, "typesafe_model"),
    }


def _signal_group(process: asyncio.subprocess.Process, sig: signal.Signals) -> None:
    if process.returncode is not None:
        return
    try:
        os.killpg(process.pid, sig)
    except ProcessLookupError:
        pass
    except PermissionError:
        # macOS can report EPERM for an already departing process group before
        # asyncio has received its exit notification. The direct owned child is
        # still a safe fallback; never target a different process group.
        try:
            process.send_signal(sig)
        except (ProcessLookupError, PermissionError):
            pass


async def _stop(process: asyncio.subprocess.Process) -> None:
    if process.returncode is not None:
        return
    _signal_group(process, signal.SIGTERM)
    try:
        await asyncio.wait_for(process.wait(), timeout=0.5)
    except TimeoutError:
        _signal_group(process, signal.SIGKILL)
        await process.wait()


async def _read_bounded(
    stream: asyncio.StreamReader, limit: int, process: asyncio.subprocess.Process,
    *, keep: bool,
) -> bytes | None:
    chunks: list[bytes] = []
    total = 0
    exceeded = False
    while chunk := await stream.read(32_768):
        total += len(chunk)
        if total > limit and not exceeded:
            exceeded = True
            # Continue draining a killed worker's pipes without retaining data.
            # This prevents pipe backpressure from delaying process reaping.
            _signal_group(process, signal.SIGKILL)
        elif keep and not exceeded:
            chunks.append(chunk)
    return None if exceeded else b"".join(chunks)


async def _exchange(process: asyncio.subprocess.Process, encoded: bytes) -> tuple[bytes | None, bytes | None, int]:
    assert process.stdin is not None and process.stdout is not None and process.stderr is not None
    stdout = asyncio.create_task(_read_bounded(process.stdout, _OUTPUT_LIMIT, process, keep=True))
    stderr = asyncio.create_task(_read_bounded(process.stderr, _STDERR_LIMIT, process, keep=False))
    try:
        try:
            process.stdin.write(encoded)
            await process.stdin.drain()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            process.stdin.close()
        out, err = await asyncio.gather(stdout, stderr)
        return out, err, await process.wait()
    finally:
        for task in (stdout, stderr):
            if not task.done():
                task.cancel()
        await asyncio.gather(stdout, stderr, return_exceptions=True)


async def _run(mode: str, payload: dict[str, Any], settings: PlannerSettings) -> dict[str, Any]:
    if not isinstance(payload, dict):
        return _failure("planner_request_invalid", "A JSON object is required.", 400)
    try:
        encoded = json.dumps({"mode": mode, "payload": payload}, ensure_ascii=False, allow_nan=False, separators=(",", ":")).encode("utf-8")
    except (TypeError, ValueError, UnicodeError):
        return _failure("planner_request_invalid", "The planner request must contain valid JSON.", 400)
    if len(encoded) > _INPUT_LIMIT:
        return _failure("planner_request_too_large", "The project snapshot exceeded its size limit.", 413)
    if mode == "plan" and not _setting(settings, "openai_api_key"):
        return _failure("planner_not_configured", "The server-side OpenAI planner is not configured.", 503)
    node = shutil.which("node")
    if node is None:
        return _failure("planner_runtime_unavailable", "The local planner runtime is unavailable.", 503)
    loop = asyncio.get_running_loop()
    limiter = _limiters.setdefault(loop, asyncio.Semaphore(_MAX_WORKERS))
    if limiter.locked():
        return _failure("planner_busy", "The planner is busy. Try again after the current request finishes.", 503)
    await limiter.acquire()
    process: asyncio.subprocess.Process | None = None
    exchange: asyncio.Task[tuple[bytes | None, bytes | None, int]] | None = None
    try:
        process = await asyncio.create_subprocess_exec(
            node, "--experimental-strip-types", "--max-old-space-size=192", str(_WORKER),
            stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE, env=_environment(settings),
            start_new_session=True,
        )
        exchange = asyncio.create_task(_exchange(process, encoded))
        # Shield keeps pipe readers alive during timeout/cancellation cleanup.
        out, err, exit_code = await asyncio.wait_for(asyncio.shield(exchange), timeout=_TIMEOUT_SECONDS)
        if out is None or err is None:
            return _failure("planner_output_limit", "The planner response exceeded its size limit.")
        if exit_code != 0:
            return _failure("planner_worker_failed", "The planner could not complete this request.")
        try:
            result = json.loads(out)
        except (ValueError, UnicodeError):
            return _failure("planner_response_invalid", "The planner returned an invalid response.")
        if (not isinstance(result, dict) or type(result.get("httpStatus")) is not int
                or not 200 <= result["httpStatus"] <= 599 or not isinstance(result.get("response"), dict)):
            return _failure("planner_response_invalid", "The planner returned an invalid response.")
        return {"httpStatus": result["httpStatus"], "response": result["response"]}
    except TimeoutError:
        return _failure("planner_timeout", "Planning timed out before any edit was applied.", 504)
    except asyncio.CancelledError:
        raise
    except Exception:
        # Do not surface subprocess exception text: it may contain environment,
        # path, or request details. The application can log this error code only.
        return _failure("planner_worker_failed", "The planner could not complete this request.")
    finally:
        try:
            if process is not None:
                await _stop(process)
            if exchange is not None:
                if not exchange.done():
                    exchange.cancel()
                await asyncio.gather(exchange, return_exceptions=True)
        finally:
            limiter.release()


async def plan_voice_request(input: dict[str, Any], settings: PlannerSettings) -> dict[str, Any]:
    """Plan one native {sessionId, commandId, request, sessionState} request."""
    return await _run("plan", input, settings)


async def resolve_mix_request(payload: dict[str, Any], settings: PlannerSettings) -> dict[str, Any]:
    """Preserve the existing locally calculated mix proposals and metadata."""
    return await _run("mix", payload, settings)
