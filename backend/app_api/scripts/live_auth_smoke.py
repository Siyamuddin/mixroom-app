from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any, Iterable


@dataclass(frozen=True)
class HttpResult:
    status_code: int
    body_text: str
    body_json: dict[str, Any] | None


def _env(name: str) -> str:
    return os.environ.get(name, "").strip()


def _join_url(base_url: str, path: str) -> str:
    return f"{base_url.rstrip('/')}/{path.lstrip('/')}"


def _request_json(
    *,
    method: str,
    url: str,
    bearer_token: str = "",
    body: dict[str, Any] | None = None,
) -> HttpResult:
    payload = None
    headers = {
        "Accept": "application/json",
    }
    if body is not None:
        payload = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    if bearer_token.strip():
        headers["Authorization"] = f"Bearer {bearer_token.strip()}"

    request = urllib.request.Request(
        url,
        data=payload,
        headers=headers,
        method=method.upper(),
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            raw = response.read().decode("utf-8")
            return HttpResult(
                status_code=response.getcode(),
                body_text=raw,
                body_json=_decode_json_object(raw),
            )
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8")
        return HttpResult(
            status_code=exc.code,
            body_text=raw,
            body_json=_decode_json_object(raw),
        )


def _decode_json_object(raw: str) -> dict[str, Any] | None:
    if not raw.strip():
        return None
    try:
        decoded = json.loads(raw)
    except json.JSONDecodeError:
        return None
    if isinstance(decoded, dict):
        return {str(key): value for key, value in decoded.items()}
    return None


def _expect_status(result: HttpResult, expected: Iterable[int], label: str) -> None:
    allowed = tuple(expected)
    if result.status_code in allowed:
        print(f"[ok] {label}: HTTP {result.status_code}")
        return
    raise SystemExit(
        f"[fail] {label}: expected {allowed}, got {result.status_code}\n{result.body_text}"
    )


def _require_json(result: HttpResult, label: str) -> dict[str, Any]:
    if result.body_json is not None:
        return result.body_json
    raise SystemExit(f"[fail] {label}: response was not a JSON object\n{result.body_text}")


def _extract_tokens(payload: dict[str, Any], label: str) -> dict[str, str]:
    tokens = payload.get("tokens")
    if not isinstance(tokens, dict):
        raise SystemExit(f"[fail] {label}: missing tokens payload\n{payload}")
    required = {}
    for key in ("accessToken", "idToken", "refreshToken"):
        value = str(tokens.get(key) or "").strip()
        if not value:
            raise SystemExit(f"[fail] {label}: missing {key}\n{payload}")
        required[key] = value
    return required


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Live smoke test for deployed Mixroom auth and LLM proxy auth.",
    )
    parser.add_argument(
        "--app-api-base-url",
        default=_env("APP_API_BASE_URL"),
        help="Deployed App API base URL. Defaults to APP_API_BASE_URL.",
    )
    parser.add_argument(
        "--llm-proxy-api-base-url",
        default=_env("LLM_PROXY_API_BASE_URL"),
        help="Deployed LLM proxy base URL. Defaults to LLM_PROXY_API_BASE_URL.",
    )
    parser.add_argument(
        "--email",
        default=_env("MIXROOM_TEST_EMAIL"),
        help="Existing native-auth test account email. Defaults to MIXROOM_TEST_EMAIL.",
    )
    parser.add_argument(
        "--password",
        default=_env("MIXROOM_TEST_PASSWORD"),
        help="Existing native-auth test account password. Defaults to MIXROOM_TEST_PASSWORD.",
    )
    args = parser.parse_args()

    app_api_base_url = args.app_api_base_url.strip()
    llm_proxy_base_url = args.llm_proxy_api_base_url.strip()
    email = args.email.strip()
    password = args.password.strip()

    if not app_api_base_url:
        raise SystemExit("[fail] missing --app-api-base-url or APP_API_BASE_URL")
    if not email or not password:
        raise SystemExit("[fail] missing --email/--password or MIXROOM_TEST_EMAIL/MIXROOM_TEST_PASSWORD")

    sign_in = _request_json(
        method="POST",
        url=_join_url(app_api_base_url, "/v1/auth/sign-in"),
        body={
            "identifier": email,
            "password": password,
        },
    )
    _expect_status(sign_in, (200,), "sign in")
    sign_in_payload = _require_json(sign_in, "sign in")
    initial_tokens = _extract_tokens(sign_in_payload, "sign in")

    get_me = _request_json(
        method="GET",
        url=_join_url(app_api_base_url, "/v1/users/me"),
        bearer_token=initial_tokens["idToken"],
    )
    _expect_status(get_me, (200,), "users/me with initial token")

    if llm_proxy_base_url:
        llm_limits = _request_json(
            method="GET",
            url=_join_url(llm_proxy_base_url, "/v1/llm/limits"),
            bearer_token=initial_tokens["idToken"],
        )
        _expect_status(llm_limits, (200,), "llm limits with initial token")

    refresh = _request_json(
        method="POST",
        url=_join_url(app_api_base_url, "/v1/auth/refresh"),
        body={
            "refresh_token": initial_tokens["refreshToken"],
            "fallback_id_token": initial_tokens["idToken"],
        },
    )
    _expect_status(refresh, (200,), "refresh")
    refresh_payload = _require_json(refresh, "refresh")
    refreshed_tokens = _extract_tokens(refresh_payload, "refresh")

    if refreshed_tokens["refreshToken"] != initial_tokens["refreshToken"]:
        raise SystemExit("[fail] refresh unexpectedly changed the device refresh token")
    print("[ok] refresh kept the device refresh token stable")

    initial_me_after_refresh = _request_json(
        method="GET",
        url=_join_url(app_api_base_url, "/v1/users/me"),
        bearer_token=initial_tokens["idToken"],
    )
    _expect_status(
        initial_me_after_refresh,
        (200,),
        "users/me still accepts the pre-refresh access token until it expires",
    )

    refreshed_me = _request_json(
        method="GET",
        url=_join_url(app_api_base_url, "/v1/users/me"),
        bearer_token=refreshed_tokens["idToken"],
    )
    _expect_status(refreshed_me, (200,), "users/me with refreshed token")

    if llm_proxy_base_url:
        initial_limits_after_refresh = _request_json(
            method="GET",
            url=_join_url(llm_proxy_base_url, "/v1/llm/limits"),
            bearer_token=initial_tokens["idToken"],
        )
        _expect_status(
            initial_limits_after_refresh,
            (200,),
            "llm limits still accepts the pre-refresh access token until it expires",
        )

        refreshed_limits = _request_json(
            method="GET",
            url=_join_url(llm_proxy_base_url, "/v1/llm/limits"),
            bearer_token=refreshed_tokens["idToken"],
        )
        _expect_status(refreshed_limits, (200,), "llm limits with refreshed token")

    sign_out = _request_json(
        method="POST",
        url=_join_url(app_api_base_url, "/v1/auth/sign-out"),
        bearer_token=refreshed_tokens["idToken"],
        body={},
    )
    _expect_status(sign_out, (200,), "sign out")

    signed_out_me = _request_json(
        method="GET",
        url=_join_url(app_api_base_url, "/v1/users/me"),
        bearer_token=refreshed_tokens["idToken"],
    )
    _expect_status(signed_out_me, (401, 403), "users/me rejects token after sign out")

    if llm_proxy_base_url:
        signed_out_limits = _request_json(
            method="GET",
            url=_join_url(llm_proxy_base_url, "/v1/llm/limits"),
            bearer_token=refreshed_tokens["idToken"],
        )
        _expect_status(
            signed_out_limits,
            (401, 403),
            "llm limits rejects token after sign out",
        )

    print("[ok] live auth smoke passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
