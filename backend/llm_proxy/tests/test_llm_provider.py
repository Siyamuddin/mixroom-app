from __future__ import annotations

import io
import json
import sys
import urllib.error
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from common import llm_provider  # noqa: E402
from common.llm_provider import (  # noqa: E402
    AnthropicMessagesProvider,
    GeminiGenerateContentProvider,
    OpenAiResponsesProvider,
    get_provider,
)
from common.llm_contract import build_openai_responses_request  # noqa: E402


def _sample_request() -> dict:
    return {
        "model": "test-model",
        "instructions": "System prompt",
        "messages": [
            {"role": "assistant", "content": "Previous reply"},
            {"role": "user", "content": "Make it clearer"},
        ],
        "temperature": 0.6,
        "max_output_tokens": 222,
        "tools": [
            {
                "type": "function",
                "name": "mix_model_request",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "mode": {"type": "string"},
                    },
                    "required": ["mode"],
                },
            }
        ],
        "tool_choice": "required",
    }


class LlmProviderTests(unittest.TestCase):
    def test_get_provider_supports_aliases(self) -> None:
        self.assertEqual(get_provider("openai").name, "openai")
        self.assertEqual(get_provider("anthropic").name, "claude")
        self.assertEqual(get_provider("claude").name, "claude")
        self.assertEqual(get_provider("google").name, "gemini")
        self.assertEqual(get_provider("gemini").name, "gemini")

    def test_openai_request_builder_passes_conversation_id(self) -> None:
        request = {
            **_sample_request(),
            "conversation": "conv_test123",
        }

        body = build_openai_responses_request(request)

        self.assertEqual(body["conversation"], "conv_test123")

    def test_openai_provider_appends_function_call_outputs_for_conversation(self) -> None:
        provider = OpenAiResponsesProvider()
        calls: list[dict] = []

        def fake_post_json_request(**kwargs):
            calls.append(kwargs)
            if kwargs["url"].endswith("/v1/responses"):
                return (
                    200,
                    json.dumps(
                        {
                            "id": "resp_123",
                            "output": [
                                {
                                    "type": "function_call",
                                    "call_id": "call_123",
                                    "name": "daw_assistant_actions",
                                    "arguments": "{}",
                                }
                            ],
                        }
                    ),
                )
            return 200, json.dumps({"ok": True})

        with mock.patch.object(
            llm_provider,
            "_post_json_request",
            side_effect=fake_post_json_request,
        ):
            result = provider.forward_request(
                api_key="sk-test",
                request_body={**_sample_request(), "conversation": "conv_123"},
                timeout_seconds=30,
            )

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(len(calls), 2)
        self.assertTrue(calls[1]["url"].endswith("/v1/conversations/conv_123/items"))
        self.assertEqual(
            calls[1]["body"]["items"][0]["type"],
            "function_call_output",
        )
        self.assertEqual(
            result["observability"]["openai_conversation_tool_outputs_appended"],
            1,
        )

    def test_claude_builds_messages_api_request(self) -> None:
        provider = AnthropicMessagesProvider()

        body = provider._build_upstream_request(_sample_request())

        self.assertEqual(body["model"], "test-model")
        self.assertEqual(body["system"], "System prompt")
        self.assertEqual(body["max_tokens"], 222)
        self.assertEqual(body["temperature"], 0.6)
        self.assertEqual(
            body["messages"],
            [
                {"role": "assistant", "content": "Previous reply"},
                {"role": "user", "content": "Make it clearer"},
            ],
        )
        self.assertEqual(body["tool_choice"], {"type": "any"})
        self.assertEqual(body["tools"][0]["name"], "mix_model_request")
        self.assertEqual(body["tools"][0]["input_schema"]["type"], "object")

    def test_claude_normalizes_tool_use_to_openai_compatible_output(self) -> None:
        provider = AnthropicMessagesProvider()

        normalized = provider._normalize_success_payload(
            {
                "id": "msg_123",
                "model": "claude-test",
                "content": [
                    {"type": "text", "text": "Applied a subtle cleanup."},
                    {
                        "type": "tool_use",
                        "name": "mix_model_request",
                        "input": {"mode": "execute"},
                    },
                ],
            }
        )

        self.assertEqual(normalized["id"], "msg_123")
        self.assertEqual(normalized["model"], "claude-test")
        self.assertEqual(normalized["output"][0]["type"], "message")
        self.assertEqual(
            normalized["output"][0]["content"][0]["text"],
            "Applied a subtle cleanup.",
        )
        self.assertEqual(normalized["output"][1]["type"], "function_call")
        self.assertEqual(normalized["output"][1]["name"], "mix_model_request")
        self.assertEqual(normalized["output"][1]["arguments"], {"mode": "execute"})

    def test_gemini_builds_generate_content_request(self) -> None:
        provider = GeminiGenerateContentProvider()

        body = provider._build_upstream_request(_sample_request())

        self.assertEqual(
            body["systemInstruction"],
            {"parts": [{"text": "System prompt"}]},
        )
        self.assertEqual(
            body["contents"],
            [
                {"role": "model", "parts": [{"text": "Previous reply"}]},
                {"role": "user", "parts": [{"text": "Make it clearer"}]},
            ],
        )
        self.assertEqual(body["generationConfig"]["temperature"], 0.6)
        self.assertEqual(body["generationConfig"]["maxOutputTokens"], 222)
        self.assertEqual(
            body["toolConfig"],
            {"functionCallingConfig": {"mode": "ANY"}},
        )
        self.assertEqual(
            body["tools"][0]["functionDeclarations"][0]["name"],
            "mix_model_request",
        )

    def test_gemini_normalizes_function_call_to_openai_compatible_output(self) -> None:
        provider = GeminiGenerateContentProvider()

        normalized = provider._normalize_success_payload(
            {
                "candidates": [
                    {
                        "content": {
                            "parts": [
                                {"text": "Applied a subtle cleanup."},
                                {
                                    "functionCall": {
                                        "name": "mix_model_request",
                                        "args": {"mode": "execute"},
                                    }
                                },
                            ]
                        }
                    }
                ]
            }
        )

        self.assertEqual(normalized["output"][0]["type"], "message")
        self.assertEqual(
            normalized["output"][0]["content"][0]["text"],
            "Applied a subtle cleanup.",
        )
        self.assertEqual(normalized["output"][1]["type"], "function_call")
        self.assertEqual(normalized["output"][1]["name"], "mix_model_request")
        self.assertEqual(normalized["output"][1]["arguments"], {"mode": "execute"})

    def test_post_json_request_retries_retryable_transport_errors(self) -> None:
        response = mock.MagicMock()
        response.__enter__.return_value.status = 200
        response.__enter__.return_value.read.return_value = b'{"ok":true}'

        with mock.patch.dict(
            llm_provider.os.environ,
            {"LLM_UPSTREAM_NETWORK_RETRY_ATTEMPTS": "2"},
            clear=False,
        ):
            with mock.patch.object(
                llm_provider.urllib.request,
                "urlopen",
                side_effect=[
                    urllib.error.URLError(ConnectionResetError("connection reset")),
                    response,
                ],
            ) as urlopen_mock:
                with mock.patch.object(
                    llm_provider.time,
                    "monotonic",
                    side_effect=[100.0, 100.0, 100.5, 102.0],
                ), mock.patch.object(llm_provider.time, "sleep") as sleep_mock:
                    status_code, body = llm_provider._post_json_request(
                        url="https://api.example.test/v1/responses",
                        headers={"Authorization": "Bearer sk-test"},
                        body={"input": "hello"},
                        timeout_seconds=5,
                        fallback_error_message="Upstream error",
                    )

        self.assertEqual(status_code, 200)
        self.assertEqual(json.loads(body), {"ok": True})
        self.assertEqual(urlopen_mock.call_count, 2)
        self.assertEqual(
            [call.kwargs["timeout"] for call in urlopen_mock.call_args_list],
            [5.0, 3.0],
        )
        sleep_mock.assert_called_once()

    def test_post_json_request_serializes_non_ascii_text_as_utf8(self) -> None:
        response = mock.MagicMock()
        response.__enter__.return_value.status = 200
        response.__enter__.return_value.read.return_value = b'{"ok":true}'

        with mock.patch.object(
            llm_provider.urllib.request,
            "urlopen",
            return_value=response,
        ) as urlopen_mock:
            status_code, _ = llm_provider._post_json_request(
                url="https://api.example.test/v1/responses",
                headers={"Authorization": "Bearer sk-test"},
                body={"input": "한국어 샘플"},
                timeout_seconds=5,
                fallback_error_message="Upstream error",
            )

        request = urlopen_mock.call_args.args[0]
        self.assertEqual(status_code, 200)
        self.assertIn("한국어 샘플".encode("utf-8"), request.data)
        self.assertNotIn(b"\\ud55c", request.data)

    def test_post_json_request_does_not_retry_after_deadline_exhausted(self) -> None:
        response = mock.MagicMock()
        response.__enter__.return_value.status = 200
        response.__enter__.return_value.read.return_value = b'{"ok":true}'

        with mock.patch.dict(
            llm_provider.os.environ,
            {"LLM_UPSTREAM_NETWORK_RETRY_ATTEMPTS": "2"},
            clear=False,
        ), mock.patch.object(
            llm_provider.urllib.request,
            "urlopen",
            side_effect=[
                urllib.error.URLError(TimeoutError("timed out")),
                response,
            ],
        ) as urlopen_mock, mock.patch.object(
            llm_provider.time,
            "monotonic",
            side_effect=[100.0, 100.0, 104.9],
        ), mock.patch.object(llm_provider.time, "sleep") as sleep_mock:
            with self.assertRaises(TimeoutError):
                llm_provider._post_json_request(
                    url="https://api.example.test/v1/responses",
                    headers={"Authorization": "Bearer sk-test"},
                    body={"input": "hello"},
                    timeout_seconds=5,
                    fallback_error_message="Upstream error",
                )

        self.assertEqual(urlopen_mock.call_count, 1)
        sleep_mock.assert_not_called()

    def test_upstream_timeout_detection_handles_wrapped_socket_timeout(self) -> None:
        self.assertTrue(
            llm_provider.is_upstream_timeout_error(
                urllib.error.URLError(TimeoutError("timed out"))
            )
        )
        self.assertFalse(
            llm_provider.is_upstream_timeout_error(
                urllib.error.URLError(ConnectionResetError("reset"))
            )
        )

    def test_post_json_request_does_not_retry_http_errors(self) -> None:
        http_error = urllib.error.HTTPError(
            url="https://api.example.test/v1/responses",
            code=503,
            msg="Service Unavailable",
            hdrs=None,
            fp=io.BytesIO(b'{"error":"provider_unavailable"}'),
        )

        with mock.patch.dict(
            llm_provider.os.environ,
            {"LLM_UPSTREAM_NETWORK_RETRY_ATTEMPTS": "3"},
            clear=False,
        ):
            with mock.patch.object(
                llm_provider.urllib.request,
                "urlopen",
                side_effect=http_error,
            ) as urlopen_mock:
                status_code, body = llm_provider._post_json_request(
                    url="https://api.example.test/v1/responses",
                    headers={"Authorization": "Bearer sk-test"},
                    body={"input": "hello"},
                    timeout_seconds=5,
                    fallback_error_message="Upstream error",
                )

        self.assertEqual(status_code, 503)
        self.assertEqual(json.loads(body), {"error": "provider_unavailable"})
        self.assertEqual(urlopen_mock.call_count, 1)


if __name__ == "__main__":
    unittest.main()
