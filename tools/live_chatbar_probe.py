#!/usr/bin/env python3
import argparse
import json
import os
import re
import socket
import sys
import time
from pathlib import Path
from typing import Any, Optional


REPO_ROOT = Path(__file__).resolve().parents[1]
BACKEND_SRC = REPO_ROOT / "backend" / "llm_proxy" / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from common.llm_contract import build_llm_request_from_mixroom_payload
from common.llm_provider import get_provider


PROJECT_SNAPSHOT = """bpm=124.00
Track 1: isEmpty = false fileName(s)=lead_vocal.wav rms=0.182 crest=1.84 gain=1.02 pan=0.50 roles=[vocals:92%, synth:4%, other:2%] role_consistency=0.95 spectral{centroid_hz=2380 zcr=0.074 hf_rms=0.141 sibil=0.39 bassy=0.06} dynamics{st_rms_p95=0.311 transient_density=0.072} overlaps=2(0.84),4(0.41),5(0.33) fx=[Mixroom EQ, Mixroom Compressor, Mixroom De-Esser] automation_targets=[volume | fx0:Mixroom EQ{Low Gain[low_gain], Mid Gain[mid_gain], High Gain[high_gain]} | fx1:Mixroom Compressor{Threshold[threshold], Mix[mix]} | fx2:Mixroom De-Esser{Threshold[threshold], Mix[mix]}]
Track 2: isEmpty = false fileName(s)=drum_bus.wav rms=0.228 crest=1.48 gain=1.00 pan=0.50 roles=[drums:95%, bass:2%, other:2%] role_consistency=0.98 spectral{centroid_hz=1860 zcr=0.118 hf_rms=0.167 sibil=0.03 bassy=0.44} dynamics{st_rms_p95=0.392 transient_density=0.218} overlaps=1(0.84),3(0.56),4(0.22),5(0.19) fx=[Mixroom Compressor, Mixroom EQ] automation_targets=[volume | fx0:Mixroom Compressor{Threshold[threshold], Mix[mix]} | fx1:Mixroom EQ{Low Gain[low_gain], Mid Gain[mid_gain], High Gain[high_gain]}]
Track 3: isEmpty = false fileName(s)=sub_bass.wav rms=0.241 crest=1.31 gain=0.97 pan=0.50 roles=[bass:96%, synth:2%, other:1%] role_consistency=0.99 spectral{centroid_hz=210 zcr=0.021 hf_rms=0.028 sibil=0.00 bassy=0.96} dynamics{st_rms_p95=0.361 transient_density=0.044} overlaps=2(0.56),4(0.18) fx=[Mixroom EQ] automation_targets=[volume | fx0:Mixroom EQ{Low Gain[low_gain], Mid Gain[mid_gain], High Gain[high_gain]}]
Track 4: isEmpty = false fileName(s)=rhythm_guitar.wav rms=0.156 crest=1.73 gain=0.94 pan=0.24 roles=[guitar:88%, synth:6%, vocals:2%] role_consistency=0.91 spectral{centroid_hz=1690 zcr=0.081 hf_rms=0.113 sibil=0.01 bassy=0.14} dynamics{st_rms_p95=0.274 transient_density=0.116} overlaps=1(0.41),2(0.22),3(0.18),5(0.46) fx=[Mixroom EQ, Mixroom Reverb] automation_targets=[volume | fx0:Mixroom EQ{Low Gain[low_gain], Mid Gain[mid_gain], High Gain[high_gain]} | fx1:Mixroom Reverb{Mix[mix], Room Size[room_size]}]
Track 5: isEmpty = false fileName(s)=pad_synth.wav rms=0.121 crest=2.18 gain=0.88 pan=0.62 roles=[synth:94%, guitar:3%, other:2%] role_consistency=0.93 spectral{centroid_hz=1420 zcr=0.045 hf_rms=0.089 sibil=0.00 bassy=0.18} dynamics{st_rms_p95=0.228 transient_density=0.028} overlaps=1(0.33),2(0.19),4(0.46) fx=[Mixroom Reverb, Mixroom Delay] automation_targets=[volume | fx0:Mixroom Reverb{Mix[mix], Room Size[room_size]} | fx1:Mixroom Delay{Mix[mix], Time[time]}]"""

SELECTION_SNAPSHOT = """selected_row_index=0
selected_clip_indices=0,3
primary_selected_clip_index=0
selected_row_automation_targets=volume | fx0:Mixroom EQ{Low Gain[low_gain], Mid Gain[mid_gain], High Gain[high_gain]} | fx1:Mixroom Compressor{Threshold[threshold], Mix[mix]} | fx2:Mixroom De-Esser{Threshold[threshold], Mix[mix]}
selected_clip[0]{row=0,clip_kind=audio,start_ms=0.0,end_ms=27840.0,file=lead_vocal.wav,label=Lead Vocal}
selected_clip[3]{row=4,clip_kind=audio,start_ms=0.0,end_ms=27840.0,file=pad_synth.wav,label=Pad Synth}"""

DEFAULT_CASES = [
    {
        "name": "tutorial_mute",
        "prompt": "Show me where the mute button is.",
    },
    {
        "name": "interpret_vocal_pocket",
        "prompt": "The vocals don't sit right. Make them feel more in the pocket without sounding overprocessed.",
    },
    {
        "name": "interpret_professional",
        "prompt": "Make this sound more professional but keep it natural.",
    },
    {
        "name": "interpret_wider_cleaner",
        "prompt": "Make the chorus feel wider and cleaner.",
    },
    {
        "name": "interpret_muddy_harsh",
        "prompt": "The mix feels muddy and a little harsh. Fix it.",
    },
    {
        "name": "interpret_drums_vs_vocals",
        "prompt": "Make the drums hit harder without drowning the vocals.",
    },
    {
        "name": "informational_deesser",
        "prompt": "Explain what a de-esser does in plain language.",
    },
    {
        "name": "clarify_trim",
        "prompt": "Trim the clip.",
    },
]

DEFAULT_PROMPTS_FILE = REPO_ROOT / "tools" / "live_chatbar_prompts.json"


def _extract_result(payload: dict[str, Any]) -> dict[str, Any]:
    outputs = payload.get("output") or []
    assistant_text = None
    tool_calls = []

    for item in outputs:
        if not isinstance(item, dict):
            continue
        item_type = item.get("type")
        if item_type == "function_call":
            args = item.get("arguments")
            if isinstance(args, str):
                try:
                    args = json.loads(args)
                except json.JSONDecodeError:
                    pass
            tool_calls.append(
                {
                    "name": item.get("name"),
                    "arguments": args,
                }
            )
            continue
        if item_type != "message":
            continue
        for content in item.get("content") or []:
            if not isinstance(content, dict):
                continue
            if content.get("type") != "output_text":
                continue
            text = content.get("text")
            if isinstance(text, str) and text.strip() and assistant_text is None:
                assistant_text = text.strip()

    primary_tool = tool_calls[0] if tool_calls else None
    return {
        "assistant_text": assistant_text,
        "tool_calls": tool_calls,
        "primary_tool": primary_tool,
    }


def _validate_tool_call(tool_name: Optional[str], args: Any) -> list[str]:
    warnings: list[str] = []
    if not tool_name:
        warnings.append("No tool call returned.")
        return warnings
    if not isinstance(args, dict):
        warnings.append(f"{tool_name} arguments are not a JSON object.")
        return warnings

    if tool_name == "mix_model_request":
        if not isinstance(args.get("mode"), str):
            warnings.append("mix_model_request missing mode.")
        actions = args.get("actions")
        if not isinstance(actions, list) or not actions:
            warnings.append("mix_model_request missing actions array.")
        else:
            for idx, action in enumerate(actions):
                if not isinstance(action, dict):
                    warnings.append(f"mix action {idx} is not an object.")
                    continue
                goal = action.get("goal")
                if not isinstance(goal, dict):
                    warnings.append(f"mix action {idx} missing goal.")
                    continue
                target = goal.get("target")
                if not isinstance(target, dict):
                    warnings.append(f"mix action {idx} missing target.")
                    continue
                if target.get("row_index") == -1:
                    warnings.append(f"mix action {idx} emitted row_index = -1.")
    elif tool_name == "daw_assistant_actions":
        actions = args.get("actions")
        if not isinstance(actions, list) or not actions:
            warnings.append("daw_assistant_actions missing actions array.")
        else:
            for idx, action in enumerate(actions):
                if not isinstance(action, dict):
                    warnings.append(f"daw action {idx} is not an object.")
                    continue
                if not isinstance(action.get("type"), str) or not action.get("type"):
                    warnings.append(f"daw action {idx} missing type.")
    elif tool_name == "informational_response":
        if not isinstance(args.get("message"), str) or not args.get("message", "").strip():
            warnings.append("informational_response missing message.")
    return warnings


def _combined_chat_transcript(ui: dict[str, Any]) -> str:
    chunks = []
    chat_message = str(ui.get("chat_message") or "").strip()
    if chat_message:
        chunks.append(chat_message)
    for item in ui.get("chat_followups") or []:
        text = str(item or "").strip()
        if text:
            chunks.append(text)
    return "\n\n".join(chunks).strip()


def _evaluate_chat_quality(transcript: str, tool_name: Optional[str]) -> list[str]:
    issues: list[str] = []
    if not transcript:
        issues.append("No user-facing chat output.")
        return issues

    lower = transcript.lower()
    if any(token in lower for token in [
        "mix_model_request",
        "daw_assistant_actions",
        "informational_response",
        "\"assistant_message\"",
        "\"target_id\"",
        "\"row_index\"",
    ]):
        issues.append("Chat output leaked internal/tool-facing text.")

    if re.search(r"^\s*[\{\[]", transcript):
        issues.append("Chat output looks JSON-like.")

    if transcript.endswith((':', ';', ',', ' -', ' –')):
        issues.append("Chat output ends like it was cut off.")

    if re.search(r"\b(step\s*\d+/\d+)\b", lower) and tool_name != "daw_assistant_actions":
        issues.append("Chat output contains step markers in an unexpected place.")

    if len(transcript) < 12:
        issues.append("Chat output is unusually short.")

    if lower in {"sure.", "okay.", "ok.", "done.", "here you go."}:
        issues.append("Chat output is too minimal to be user-friendly.")

    if transcript.count("\n\n\n") > 0:
        issues.append("Chat output has odd spacing.")

    lines = [line.strip() for line in transcript.splitlines() if line.strip()]
    if len(lines) >= 2 and len(set(lines)) != len(lines):
        issues.append("Chat output repeats lines.")

    dangling_patterns = [
        r"\bwithout\s*$",
        r"\bwith\s*$",
        r"\bby\s*$",
        r"\band\s*$",
        r"\bor\s*$",
        r"\bto\s*$",
    ]
    for pattern in dangling_patterns:
        if re.search(pattern, lower):
            issues.append("Chat output feels truncated at the end.")
            break

    return issues


def _infer_current_chatbar_behavior(tool_name: Optional[str], args: Any) -> dict[str, Any]:
    assistant_message = ""
    chat_only_followups: list[str] = []

    if isinstance(args, dict):
        assistant_message = str(
            args.get("assistant_message")
            or args.get("message")
            or ""
        ).strip()

    if tool_name == "daw_assistant_actions" and isinstance(args, dict):
        for action in args.get("actions") or []:
            if not isinstance(action, dict):
                continue
            action_type = str(action.get("type") or "").strip().lower()
            data = action.get("data") or {}
            if not isinstance(data, dict):
                continue
            if action_type == "tutorial":
                raw_steps = data.get("steps") or []
                steps = raw_steps if isinstance(raw_steps, list) and raw_steps else [data]
                lines = []
                for index, step in enumerate(steps, start=1):
                    if not isinstance(step, dict):
                        continue
                    text = str(step.get("text") or "").strip()
                    if text:
                        lines.append(text if len(steps) == 1 else f"{index}. {text}")
                if lines:
                    chat_only_followups.append("\n".join(lines))
            if action_type == "clarify":
                question = str(data.get("question") or "").strip()
                options = [
                    str(option).strip()
                    for option in (data.get("options") or [])
                    if str(option).strip()
                ]
                if question:
                    chat_only_followups.append(
                        question if not options else f"{question}\n\nOptions: {' / '.join(options)}"
                    )

    return {
        "chat_message": assistant_message,
        "chat_followups": chat_only_followups,
        "snackbars": [],
    }


def _summarize_case(case_name: str, prompt: str, result: dict[str, Any], latency_s: float) -> dict[str, Any]:
    primary_tool = result.get("primary_tool") or {}
    tool_name = primary_tool.get("name")
    tool_args = primary_tool.get("arguments")
    warnings = _validate_tool_call(tool_name, tool_args)
    ui = _infer_current_chatbar_behavior(tool_name, tool_args)
    transcript = _combined_chat_transcript(ui)
    quality_issues = _evaluate_chat_quality(transcript, tool_name)

    return {
        "name": case_name,
        "prompt": prompt,
        "latency_ms": int(latency_s * 1000),
        "tool_name": tool_name,
        "assistant_text": result.get("assistant_text"),
        "tool_arguments": tool_args,
        "warnings": warnings,
        "chat_quality_issues": quality_issues,
        "current_chatbar": ui,
        "chat_transcript": transcript,
    }


def _usage_metrics(payload: dict[str, Any]) -> dict[str, int]:
    usage = payload.get("usage")
    if not isinstance(usage, dict):
        return {
            "prompt_tokens": 0,
            "completion_tokens": 0,
            "total_tokens": 0,
            "cached_prompt_tokens": 0,
        }

    prompt_tokens = int(usage.get("input_tokens") or usage.get("prompt_tokens") or 0)
    completion_tokens = int(usage.get("output_tokens") or usage.get("completion_tokens") or 0)
    total_tokens = int(usage.get("total_tokens") or (prompt_tokens + completion_tokens))
    cached_prompt_tokens = 0
    for details_key in ("input_tokens_details", "prompt_tokens_details"):
        details = usage.get(details_key)
        if not isinstance(details, dict):
            continue
        try:
            cached_prompt_tokens = int(details.get("cached_tokens") or 0)
        except (TypeError, ValueError):
            cached_prompt_tokens = 0
        break

    return {
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "total_tokens": total_tokens,
        "cached_prompt_tokens": cached_prompt_tokens,
    }


def _normalize_case(raw: dict[str, Any]) -> dict[str, str]:
    return {
        "name": str(raw["name"]),
        "category": str(raw.get("category") or "uncategorized"),
        "prompt": str(raw["prompt"]),
    }


def _load_cases(prompts_file: Path) -> list[dict[str, str]]:
    raw = json.loads(prompts_file.read_text(encoding="utf-8"))
    if not isinstance(raw, list):
        raise ValueError("Prompt suite file must contain a JSON array.")
    cases = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        if "name" not in item or "prompt" not in item:
            continue
        cases.append(_normalize_case(item))
    if not cases:
        raise ValueError("Prompt suite file contained no valid cases.")
    return cases


def run_case(
    provider_name: str,
    api_key: str,
    model: str,
    case: dict[str, str],
    timeout_seconds: int,
    retries: int,
    instructions_override: Optional[str] = None,
    prompt_cache_key_override: Optional[str] = None,
) -> dict[str, Any]:
    request_body = build_llm_request_from_mixroom_payload(
        {
            "conversation": [],
            "user_text": case["prompt"],
            "project_snapshot": PROJECT_SNAPSHOT,
            "selection_snapshot": SELECTION_SNAPSHOT,
            "request_overrides": {
                "model": model,
                "max_output_tokens": 900,
            },
        },
        default_model=model,
        ai_feature="ai_chat",
    )
    if instructions_override is not None:
        request_body["instructions"] = instructions_override
    if prompt_cache_key_override:
        request_body["prompt_cache_key"] = prompt_cache_key_override

    last_error = None
    response = None
    started = time.perf_counter()
    for attempt in range(retries + 1):
        try:
            response = get_provider(provider_name).forward_request(
                api_key=api_key,
                request_body=request_body,
                timeout_seconds=timeout_seconds,
            )
            last_error = None
            break
        except socket.timeout as error:
            last_error = error
        except TimeoutError as error:
            last_error = error
        if attempt < retries:
            time.sleep(1.5 * (attempt + 1))
    latency_s = time.perf_counter() - started

    if response is None:
        return {
            "name": case["name"],
            "category": case["category"],
            "prompt": case["prompt"],
            "latency_ms": int(latency_s * 1000),
            "tool_name": None,
            "assistant_text": None,
            "tool_arguments": None,
            "warnings": [f"Upstream request failed after retries: {last_error}"],
            "chat_quality_issues": ["No user-facing chat output."],
            "current_chatbar": {
                "chat_message": "",
                "chat_followups": [],
                "snackbars": [],
            },
            "chat_transcript": "",
            "status_code": 0,
            "error_body": {"error": str(last_error)},
        }

    status_code = int(response.get("statusCode") or 0)
    response_body = response.get("body") or "{}"
    try:
        payload = json.loads(response_body)
    except json.JSONDecodeError:
        payload = {"raw_body": response_body}

    parsed = _extract_result(payload) if status_code == 200 else {
        "assistant_text": None,
        "tool_calls": [],
        "primary_tool": None,
    }
    summary = _summarize_case(case["name"], case["prompt"], parsed, latency_s)
    summary["category"] = case["category"]
    summary["status_code"] = status_code
    summary.update(_usage_metrics(payload))
    if status_code != 200:
        summary["error_body"] = payload
    return summary


def _build_aggregate(results: list[dict[str, Any]]) -> dict[str, Any]:
    by_category: dict[str, dict[str, Any]] = {}
    tool_counts: dict[str, int] = {}
    weird_cases = []
    invalid_cases = []
    latencies = []
    cached_hits = 0
    cached_prompt_tokens = []

    for result in results:
        category = str(result.get("category") or "uncategorized")
        bucket = by_category.setdefault(
            category,
            {
                "count": 0,
                "tool_counts": {},
                "invalid_count": 0,
                "chat_issue_count": 0,
            },
        )
        bucket["count"] += 1

        tool_name = str(result.get("tool_name") or "none")
        tool_counts[tool_name] = tool_counts.get(tool_name, 0) + 1
        bucket["tool_counts"][tool_name] = bucket["tool_counts"].get(tool_name, 0) + 1

        latency_ms = int(result.get("latency_ms") or 0)
        if latency_ms > 0:
            latencies.append(latency_ms)
        cached_prompt_token_count = int(result.get("cached_prompt_tokens") or 0)
        if cached_prompt_token_count > 0:
            cached_hits += 1
            cached_prompt_tokens.append(cached_prompt_token_count)

        warnings = result.get("warnings") or []
        chat_issues = result.get("chat_quality_issues") or []
        if warnings:
            bucket["invalid_count"] += 1
            invalid_cases.append(
                {
                    "name": result["name"],
                    "category": category,
                    "warnings": warnings,
                }
            )
        if chat_issues:
            bucket["chat_issue_count"] += 1
            weird_cases.append(
                {
                    "name": result["name"],
                    "category": category,
                    "issues": chat_issues,
                    "chat_transcript": result.get("chat_transcript"),
                }
            )

    latencies.sort()
    p95 = latencies[min(len(latencies) - 1, int(len(latencies) * 0.95))] if latencies else 0
    average = int(sum(latencies) / len(latencies)) if latencies else 0

    return {
        "total_cases": len(results),
        "tool_counts": tool_counts,
        "invalid_case_count": len(invalid_cases),
        "chat_issue_case_count": len(weird_cases),
        "average_latency_ms": average,
        "p95_latency_ms": p95,
        "cached_hit_count": cached_hits,
        "average_cached_prompt_tokens": (
            int(sum(cached_prompt_tokens) / len(cached_prompt_tokens))
            if cached_prompt_tokens
            else 0
        ),
        "by_category": by_category,
        "invalid_cases": invalid_cases[:30],
        "chat_issue_cases": weird_cases[:30],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe live Mixroom chatbar LLM contract.")
    parser.add_argument("--provider", default="openai")
    parser.add_argument("--model", default="gpt-4.1-mini")
    parser.add_argument("--json-out")
    parser.add_argument("--prompts-file", default=str(DEFAULT_PROMPTS_FILE))
    parser.add_argument("--timeout-seconds", type=int, default=60)
    parser.add_argument("--retries", type=int, default=2)
    parser.add_argument("--limit", type=int, default=0)
    args = parser.parse_args()

    api_key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not api_key:
        print("OPENAI_API_KEY is required.", file=sys.stderr)
        return 2

    cases = _load_cases(Path(args.prompts_file))
    if args.limit and args.limit > 0:
        cases = cases[: args.limit]
    results = []
    for index, case in enumerate(cases, start=1):
        print(
            f"Running {index}/{len(cases)} {case['name']}...",
            file=sys.stderr,
        )
        results.append(
            run_case(
                args.provider,
                api_key,
                args.model,
                case,
                timeout_seconds=args.timeout_seconds,
                retries=args.retries,
            )
        )

    output = {
        "provider": args.provider,
        "model": args.model,
        "project_snapshot_tracks": 5,
        "selection_snapshot_present": True,
        "aggregate": _build_aggregate(results),
        "results": results,
    }

    rendered = json.dumps(output, indent=2, ensure_ascii=False)
    if args.json_out:
        Path(args.json_out).write_text(rendered + "\n", encoding="utf-8")
    print(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
