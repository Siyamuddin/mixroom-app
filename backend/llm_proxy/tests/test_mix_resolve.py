from __future__ import annotations

import hashlib
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from common import config as proxy_config  # noqa: E402
from common import mix_resolve  # noqa: E402
from common.mix_resolve import OnnxMixModelRunner, MixResolveService  # noqa: E402
from handlers import api_mix_resolve  # noqa: E402


def _authed_event(
    body: str = "{}",
    *,
    claims: dict | None = None,
) -> dict:
    return {
        "requestContext": {
            "http": {
                "method": "POST",
            },
            "routeKey": "POST /v1/mix/resolve",
            "authorizer": {
                "jwt": {
                    "claims": claims
                    or {
                        "iss": proxy_config.APP_AUTH_ISSUER,
                        "aud": proxy_config.APP_AUTH_AUDIENCE,
                        "sub": "user-123",
                        "sid": "session-123",
                        "token_use": "access",
                    },
                }
            },
        },
        "rawPath": "/v1/mix/resolve",
        "headers": {
            "Authorization": "Bearer test-token",
        },
        "body": body,
        "isBase64Encoded": False,
    }


class _StubRunner:
    def __init__(
        self,
        *,
        apply_score: float = 0.9,
        raw_magnitude: float = 0.5,
    ) -> None:
        self.apply_score = apply_score
        self.raw_magnitude = raw_magnitude
        self.features_seen: list[list[float]] = []

    def predict_apply_score(self, features: list[float]) -> float | None:
        self.features_seen.append(list(features))
        return self.apply_score

    def predict_scalar(self, features: list[float]) -> float | None:
        return self.raw_magnitude

    def observability_context(self) -> dict[str, object]:
        return {
            "mix_magnitude_model_source": "remote",
            "mix_magnitude_model_bundle_version": "test-bundle",
            "mix_apply_model_version": "apply-test",
            "mix_magnitude_regressor_version": "reg-test",
        }


class _FakeResolver:
    def resolve(self, **_: object) -> dict[str, object]:
        return {
            "actions": [
                {
                    "type": "set_row_gain",
                    "data": {"row": 0, "mode": "set", "value": 1.5},
                }
            ],
            "fallback_used": False,
            "fallback_reason": "",
            "debug_entries": [],
            "observability": {
                "mix_magnitude_model_source": "remote",
                "mix_model_onnx_ms": 7,
            },
        }


class MixResolveServiceTests(unittest.TestCase):
    def test_runner_prefers_packaged_lambda_bundle_before_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            package_root = Path(temp_dir)
            models_dir = package_root / "models"
            models_dir.mkdir(parents=True, exist_ok=True)

            apply_path = (
                models_dir / "mix_apply_classifier_official_sessions_20260330_seed1.onnx"
            )
            magnitude_path = (
                models_dir
                / "mix_magnitude_regressor_official_sessions_20260330_seed1.onnx"
            )
            apply_path.write_bytes(b"packaged-apply")
            magnitude_path.write_bytes(b"packaged-magnitude")

            runner = OnnxMixModelRunner()
            with mock.patch.object(mix_resolve, "_package_root", return_value=package_root):
                with mock.patch.dict(
                    os.environ,
                    {
                        "MIX_MODEL_MANIFEST_URL": "https://example.com/manifest.json",
                    },
                    clear=False,
                ):
                    resolved = runner._resolve_bundle()

            self.assertEqual(resolved.source, "packaged")
            self.assertEqual(resolved.apply_path, apply_path)
            self.assertEqual(resolved.magnitude_path, magnitude_path)

    def test_runner_resolves_manifest_backed_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source_dir = root / "source"
            cache_dir = root / "cache"
            source_dir.mkdir(parents=True, exist_ok=True)

            apply_path = source_dir / "mix_apply_classifier_test.onnx"
            magnitude_path = source_dir / "mix_magnitude_regressor_test.onnx"
            apply_bytes = b"apply-model"
            magnitude_bytes = b"magnitude-model"
            apply_path.write_bytes(apply_bytes)
            magnitude_path.write_bytes(magnitude_bytes)

            manifest_path = root / "manifest.json"
            manifest_path.write_text(
                json.dumps(
                    {
                        "bundle_version": "bundle-123",
                        "enabled": True,
                        "rollout_percent": 100,
                        "min_app_version": "1.0.0",
                        "max_app_version": "",
                        "apply_model": {
                            "version": "apply-v1",
                            "url": apply_path.as_uri(),
                            "sha256": hashlib.sha256(apply_bytes).hexdigest(),
                            "file_name": apply_path.name,
                        },
                        "magnitude_model": {
                            "version": "mag-v1",
                            "url": magnitude_path.as_uri(),
                            "sha256": hashlib.sha256(magnitude_bytes).hexdigest(),
                            "file_name": magnitude_path.name,
                        },
                    }
                ),
                encoding="utf-8",
            )

            runner = OnnxMixModelRunner()
            with mock.patch.dict(
                os.environ,
                {
                    "MIX_MODEL_MANIFEST_URL": manifest_path.as_uri(),
                    "MIX_MODEL_CACHE_DIRECTORY": str(cache_dir),
                },
                clear=False,
            ):
                with mock.patch.object(
                    runner,
                    "_packaged_lambda_bundle",
                    return_value=None,
                ):
                    resolved = runner._resolve_bundle()

            self.assertEqual(resolved.bundle_version, "bundle-123")
            self.assertEqual(resolved.apply_version, "apply-v1")
            self.assertEqual(resolved.magnitude_version, "mag-v1")
            self.assertTrue(resolved.apply_path.exists())
            self.assertTrue(resolved.magnitude_path.exists())
            self.assertEqual(resolved.apply_path.parent, cache_dir / "bundle-123")

    def test_service_refines_gain_action_using_model_scale(self) -> None:
        service = MixResolveService(runner=_StubRunner())
        result = service.resolve(
            project={
                "bpm": 124.0,
                "master_gain_0to3": 1.0,
                "master_pan_0to1": 0.5,
                "max_rows": 1,
                "rows": [
                    {
                        "row": 0,
                        "features": {
                            "approx_rms": 0.2,
                            "approx_crest": 1.8,
                        },
                        "role_probs": {
                            "vocals": 0.9,
                        },
                        "audio_stats": {
                            "centroid_hz": 1200.0,
                            "true_peak_dbfs": -5.0,
                            "integrated_lufs_est": -16.0,
                        },
                        "mix": {
                            "gain_0to3": 1.0,
                            "pan_0to1": 0.5,
                        },
                        "effects": [],
                        "hasAudio": True,
                    }
                ],
                "master_effects": [],
                "overlap_matrix": [[0]],
                "overlap_ratio_matrix": [[0.0]],
            },
            goal={
                "type": "mix_request",
                "intensity": 0.55,
                "execution_profile": "producer_safe",
                "audibility": "noticeable",
                "target": {
                    "scope": "row",
                    "row_index": 0,
                    "confidence": 1.0,
                },
                "intents": [
                    {
                        "kind": "gain",
                        "direction": "up",
                        "confidence": 1.0,
                    }
                ],
            },
            actions=[
                {
                    "type": "set_row_gain",
                    "data": {
                        "row": 0,
                        "mode": "set",
                        "value": 2.0,
                    },
                }
            ],
            strict=False,
        )

        self.assertFalse(result["fallback_used"])
        refined = result["actions"][0]
        self.assertEqual(refined["type"], "set_row_gain")
        self.assertAlmostEqual(refined["data"]["value"], 1.5)
        self.assertEqual(result["observability"]["mix_apply_model_version"], "apply-test")

    def test_service_bypasses_reference_guided_goals(self) -> None:
        service = MixResolveService(runner=_StubRunner())
        result = service.resolve(
            project={
                "bpm": 120.0,
                "master_gain_0to3": 1.0,
                "rows": [],
                "max_rows": 0,
                "overlap_matrix": [],
                "overlap_ratio_matrix": [],
            },
            goal={
                "type": "mix_request",
                "intensity": 0.5,
                "execution_profile": "producer_safe",
                "audibility": "noticeable",
                "target": {"scope": "auto", "confidence": 1.0},
                "reference_target": {"row_index": 1, "confidence": 0.9},
                "intents": [{"kind": "balance", "confidence": 1.0}],
            },
            actions=[
                {
                    "type": "set_master_gain",
                    "data": {"mode": "delta", "delta": 0.2},
                }
            ],
            strict=True,
        )

        self.assertTrue(result["fallback_used"])
        self.assertEqual(result["fallback_reason"], "reference_match_bypass")
        self.assertEqual(result["actions"][0]["type"], "set_master_gain")


class MixResolveHandlerTests(unittest.TestCase):
    def test_handler_requires_authenticated_user(self) -> None:
        result = api_mix_resolve.handler({"headers": {}, "body": "{}"}, None)
        self.assertEqual(result["statusCode"], 401)

    def test_handler_rejects_invalid_body(self) -> None:
        result = api_mix_resolve.handler(_authed_event("{not-json"), None)
        self.assertEqual(result["statusCode"], 400)

    def test_handler_returns_resolved_actions(self) -> None:
        with mock.patch.object(api_mix_resolve, "_resolver", _FakeResolver()):
            result = api_mix_resolve.handler(
                _authed_event(
                    json.dumps(
                        {
                            "project_state": {
                                "rows": [],
                            },
                            "goal": {
                                "target": {"scope": "auto"},
                                "intents": [{"kind": "balance"}],
                            },
                            "actions": [
                                {
                                    "type": "set_row_gain",
                                    "data": {"row": 0, "mode": "set", "value": 2.0},
                                }
                            ],
                            "strict": True,
                        }
                    )
                ),
                None,
            )

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        self.assertFalse(payload["fallback_used"])
        self.assertEqual(payload["actions"][0]["data"]["value"], 1.5)
        self.assertEqual(payload["observability"]["mix_model_onnx_ms"], 7)
