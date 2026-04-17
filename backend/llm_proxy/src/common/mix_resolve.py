from __future__ import annotations

import hashlib
import json
import math
import os
import shutil
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol
from urllib.parse import urlparse
from urllib.request import urlopen

_DEFAULT_APPLY_MODEL_FILENAME = (
    "mix_apply_classifier_official_sessions_20260330_seed1.onnx"
)
_DEFAULT_MAGNITUDE_MODEL_FILENAME = (
    "mix_magnitude_regressor_official_sessions_20260330_seed1.onnx"
)
_DEFAULT_MANIFEST_URL = ""
_DEFAULT_BUNDLE_VERSION = "server-default"
_CONTRACT_VERSION = "mix_refine_v1"
_FEATURE_COUNT = 77
_ACTION_FEATURE_COUNT = 15
_MAX_ACTIONS = 64
_DEFAULT_MANIFEST_TIMEOUT_SECONDS = 4
_DEFAULT_DOWNLOAD_TIMEOUT_SECONDS = 12
_DEFAULT_CACHE_DIRECTORY = "/tmp/mixroom_mix_models"


def contract_version() -> str:
    return _CONTRACT_VERSION


class MixResolveValidationError(ValueError):
    pass


@dataclass(frozen=True)
class _ParamLookup:
    current: float
    minimum: float | None
    maximum: float | None


@dataclass(frozen=True)
class _OverlapMetrics:
    overlap_density: float = 0.0
    masking_pair_ratio: float = 0.0
    centroid_collision_ratio: float = 0.0
    avg_overlap_centroid_gap_norm: float = 0.0
    overlap_rms_pressure: float = 0.0
    role_overlap_ratio: float = 0.0
    low_collision_ratio: float = 0.0
    lowmid_collision_ratio: float = 0.0
    mid_collision_ratio: float = 0.0
    high_collision_ratio: float = 0.0


@dataclass(frozen=True)
class _ResolvedModelBundle:
    source: str
    bundle_version: str
    apply_path: Path
    magnitude_path: Path
    apply_version: str
    magnitude_version: str
    fetch_ms: int = 0


@dataclass(frozen=True)
class _RemoteModelAssetSpec:
    version: str
    url: str
    sha256_hex: str
    file_name: str


@dataclass(frozen=True)
class _RemoteBundleManifest:
    bundle_version: str
    apply_model: _RemoteModelAssetSpec
    magnitude_model: _RemoteModelAssetSpec


class _ModelRunner(Protocol):
    def predict_apply_score(self, features: list[float]) -> float | None: ...

    def predict_scalar(self, features: list[float]) -> float | None: ...

    def observability_context(self) -> dict[str, Any]: ...


class OnnxMixModelRunner:
    def __init__(self) -> None:
        self._sessions_loaded = False
        self._load_error: Exception | None = None
        self._load_lock = threading.Lock()
        self._apply_session = None
        self._magnitude_session = None
        self._np = None
        self._ort = None
        self._apply_path = ""
        self._magnitude_path = ""
        self._apply_version = ""
        self._magnitude_version = ""
        self._model_fetch_ms = 0
        self._model_source = "unknown"
        self._bundle_version = (
            os.environ.get("MIX_MODEL_BUNDLE_VERSION", "").strip()
            or _DEFAULT_BUNDLE_VERSION
        )

    def predict_apply_score(self, features: list[float]) -> float | None:
        self._ensure_sessions()
        named_outputs = self._run_named_outputs(self._apply_session, features)
        return self._extract_apply_score(named_outputs)

    def predict_scalar(self, features: list[float]) -> float | None:
        self._ensure_sessions()
        named_outputs = self._run_named_outputs(self._magnitude_session, features)
        for value in named_outputs.values():
            scalar = self._first_scalar(value)
            if scalar is not None:
                return scalar
        return None

    def observability_context(self) -> dict[str, Any]:
        apply_version = (
            self._apply_version
            or _basename_without_extension(self._apply_path)
            or _basename_without_extension(_DEFAULT_APPLY_MODEL_FILENAME)
        )
        magnitude_version = (
            self._magnitude_version
            or _basename_without_extension(self._magnitude_path)
            or _basename_without_extension(_DEFAULT_MAGNITUDE_MODEL_FILENAME)
        )
        context = {
            "mix_magnitude_model_source": self._model_source,
            "mix_magnitude_model_bundle_version": self._bundle_version,
            "mix_apply_model_version": apply_version,
            "mix_magnitude_regressor_version": magnitude_version,
            "mix_feature_contract_version": _CONTRACT_VERSION,
        }
        if self._model_fetch_ms > 0:
            context["mix_model_fetch_ms"] = self._model_fetch_ms
        return context

    def _ensure_sessions(self) -> None:
        if self._sessions_loaded:
            return
        with self._load_lock:
            if self._sessions_loaded:
                return
            try:
                import numpy as np
                import onnxruntime as ort

                resolved = self._resolve_bundle()

                options = ort.SessionOptions()
                options.intra_op_num_threads = 1
                options.inter_op_num_threads = 1

                self._apply_session = ort.InferenceSession(
                    str(resolved.apply_path),
                    sess_options=options,
                    providers=["CPUExecutionProvider"],
                )
                self._magnitude_session = ort.InferenceSession(
                    str(resolved.magnitude_path),
                    sess_options=options,
                    providers=["CPUExecutionProvider"],
                )
                self._np = np
                self._ort = ort
                self._apply_path = str(resolved.apply_path)
                self._magnitude_path = str(resolved.magnitude_path)
                self._apply_version = resolved.apply_version
                self._magnitude_version = resolved.magnitude_version
                self._model_source = resolved.source
                self._bundle_version = resolved.bundle_version
                self._model_fetch_ms = resolved.fetch_ms
                self._sessions_loaded = True
                self._load_error = None
            except Exception as error:
                self._load_error = error
                raise

    def _resolve_bundle(self) -> _ResolvedModelBundle:
        configured_apply = os.environ.get("MIX_APPLY_MODEL_PATH", "").strip()
        configured_magnitude = os.environ.get("MIX_MAGNITUDE_MODEL_PATH", "").strip()
        if configured_apply or configured_magnitude:
            if not configured_apply or not configured_magnitude:
                raise FileNotFoundError(
                    "Both MIX_APPLY_MODEL_PATH and MIX_MAGNITUDE_MODEL_PATH must be set together."
                )
            apply_path = Path(configured_apply).expanduser()
            magnitude_path = Path(configured_magnitude).expanduser()
            if not apply_path.exists():
                raise FileNotFoundError(f"Missing apply model file: {apply_path}")
            if not magnitude_path.exists():
                raise FileNotFoundError(
                    f"Missing magnitude model file: {magnitude_path}"
                )
            return _ResolvedModelBundle(
                source="configured_path",
                bundle_version=self._bundle_version,
                apply_path=apply_path,
                magnitude_path=magnitude_path,
                apply_version=_basename_without_extension(str(apply_path)),
                magnitude_version=_basename_without_extension(str(magnitude_path)),
            )

        packaged = self._packaged_lambda_bundle()
        if packaged is not None:
            return packaged

        manifest_url = _manifest_url()
        if manifest_url:
            try:
                return self._resolve_bundle_from_manifest(manifest_url)
            except Exception:
                bundled = self._bundled_repo_bundle()
                if bundled is not None:
                    return bundled
                raise

        bundled = self._bundled_repo_bundle()
        if bundled is not None:
            return bundled
        raise FileNotFoundError("No mix model source is configured.")

    def _resolve_bundle_from_manifest(self, manifest_url: str) -> _ResolvedModelBundle:
        started_at = time.perf_counter()
        manifest = _load_remote_manifest(manifest_url)
        bundle_dir = _cache_root_dir() / _safe_path_component(manifest.bundle_version)
        bundle_dir.mkdir(parents=True, exist_ok=True)
        apply_path = self._download_remote_asset(
            manifest_url=manifest_url,
            asset=manifest.apply_model,
            bundle_dir=bundle_dir,
        )
        magnitude_path = self._download_remote_asset(
            manifest_url=manifest_url,
            asset=manifest.magnitude_model,
            bundle_dir=bundle_dir,
        )
        return _ResolvedModelBundle(
            source="manifest",
            bundle_version=manifest.bundle_version,
            apply_path=apply_path,
            magnitude_path=magnitude_path,
            apply_version=manifest.apply_model.version,
            magnitude_version=manifest.magnitude_model.version,
            fetch_ms=int((time.perf_counter() - started_at) * 1000.0),
        )

    def _download_remote_asset(
        self,
        *,
        manifest_url: str,
        asset: _RemoteModelAssetSpec,
        bundle_dir: Path,
    ) -> Path:
        target = bundle_dir / _safe_path_component(asset.file_name)
        if target.exists() and _sha256_for_file(target) == asset.sha256_hex:
            return target
        parsed_manifest = urlparse(manifest_url)
        parsed_asset = urlparse(asset.url)
        if not _is_trusted_asset_url(parsed_manifest, parsed_asset):
            raise ValueError("Model asset URL is outside the trusted manifest origin.")
        temp_target = target.with_suffix(f"{target.suffix}.download")
        if temp_target.exists():
            temp_target.unlink()
        _download_url_to_file(asset.url, temp_target, timeout_seconds=_download_timeout_seconds())
        digest = _sha256_for_file(temp_target)
        if digest != asset.sha256_hex:
            temp_target.unlink(missing_ok=True)
            raise ValueError(f"Checksum mismatch for model asset {asset.file_name}.")
        if target.exists():
            target.unlink()
        temp_target.rename(target)
        return target

    def _packaged_lambda_bundle(self) -> _ResolvedModelBundle | None:
        apply_path = _package_root() / "models" / _DEFAULT_APPLY_MODEL_FILENAME
        magnitude_path = _package_root() / "models" / _DEFAULT_MAGNITUDE_MODEL_FILENAME
        if not apply_path.exists() or not magnitude_path.exists():
            return None
        return _ResolvedModelBundle(
            source="packaged",
            bundle_version=self._bundle_version,
            apply_path=apply_path,
            magnitude_path=magnitude_path,
            apply_version=_basename_without_extension(str(apply_path)),
            magnitude_version=_basename_without_extension(str(magnitude_path)),
        )

    def _bundled_repo_bundle(self) -> _ResolvedModelBundle | None:
        apply_path = _repo_root() / "assets" / "models" / _DEFAULT_APPLY_MODEL_FILENAME
        magnitude_path = (
            _repo_root() / "assets" / "models" / _DEFAULT_MAGNITUDE_MODEL_FILENAME
        )
        if not apply_path.exists() or not magnitude_path.exists():
            return None
        return _ResolvedModelBundle(
            source="repo_asset",
            bundle_version=self._bundle_version,
            apply_path=apply_path,
            magnitude_path=magnitude_path,
            apply_version=_basename_without_extension(str(apply_path)),
            magnitude_version=_basename_without_extension(str(magnitude_path)),
        )

    def _run_named_outputs(self, session: Any, features: list[float]) -> dict[str, Any]:
        np = self._np
        if np is None:
            raise RuntimeError("numpy is not initialized")
        input_name = session.get_inputs()[0].name
        output_names = [item.name for item in session.get_outputs()]
        raw_outputs = session.run(
            None,
            {
                input_name: np.asarray([features], dtype=np.float32),
            },
        )
        return dict(zip(output_names, raw_outputs))

    def _extract_apply_score(self, named_outputs: dict[str, Any]) -> float | None:
        for name, value in named_outputs.items():
            if "prob" in name.lower():
                score = self._positive_class_score(value)
                if score is not None:
                    return max(0.0, min(1.0, score))
        for value in named_outputs.values():
            score = self._positive_class_score(value)
            if score is not None:
                return max(0.0, min(1.0, score))
        return None

    def _positive_class_score(self, raw: Any) -> float | None:
        value = self._normalize_runtime_value(raw)
        if isinstance(value, dict):
            for key, candidate in value.items():
                if str(key).strip() in {"1", "1.0"} and isinstance(candidate, (int, float)):
                    return float(candidate)
            return None
        if isinstance(value, list):
            if not value:
                return None
            if len(value) >= 2 and all(isinstance(item, (int, float)) for item in value[:2]):
                return float(value[1])
            return self._positive_class_score(value[0])
        if isinstance(value, (int, float)):
            return float(value)
        return None

    def _first_scalar(self, raw: Any) -> float | None:
        value = self._normalize_runtime_value(raw)
        if isinstance(value, (int, float)):
            return float(value)
        if isinstance(value, dict):
            return self._positive_class_score(value)
        if isinstance(value, list) and value:
            return self._first_scalar(value[0])
        return None

    def _normalize_runtime_value(self, raw: Any) -> Any:
        if hasattr(raw, "tolist"):
            return raw.tolist()
        return raw


class MixResolveService:
    def __init__(self, runner: _ModelRunner | None = None) -> None:
        self._runner = runner or OnnxMixModelRunner()

    def resolve(
        self,
        *,
        project: dict[str, Any],
        goal: dict[str, Any],
        actions: list[dict[str, Any]],
        strict: bool,
    ) -> dict[str, Any]:
        normalized_project = _normalize_project(project)
        normalized_goal = _normalize_goal(goal)
        normalized_actions = _normalize_actions(actions)
        if len(normalized_actions) > _max_actions():
            raise MixResolveValidationError(
                f"Too many candidate actions. Maximum is {_max_actions()}."
            )
        if not normalized_actions:
            return {
                "actions": [],
                "fallback_used": False,
                "fallback_reason": "",
                "debug_entries": [],
                "observability": self._runner.observability_context(),
            }

        if _goal_execution_profile(normalized_goal) == "experimental_extreme":
            return self._fallback_result(
                normalized_actions,
                fallback_reason="execution_profile_bypass",
            )
        if _has_reference_target(normalized_goal):
            return self._fallback_result(
                normalized_actions,
                fallback_reason="reference_match_bypass",
            )

        try:
            context_features = self._build_context_features(
                project=normalized_project,
                goal=normalized_goal,
                actions=normalized_actions,
                strict=strict,
            )
            if len(context_features) + _ACTION_FEATURE_COUNT != _FEATURE_COUNT:
                return self._fallback_result(
                    normalized_actions,
                    fallback_reason="feature_contract_mismatch",
                )

            onnx_started_at = time.perf_counter()
            refined_actions: list[dict[str, Any]] = []
            debug_entries: list[dict[str, Any]] = []

            for index, action in enumerate(normalized_actions):
                features = [
                    *context_features,
                    *self._build_action_features(normalized_project, action),
                ]
                if len(features) != _FEATURE_COUNT:
                    return self._fallback_result(
                        normalized_actions,
                        fallback_reason="feature_contract_mismatch",
                    )

                apply_score = self._runner.predict_apply_score(features)
                raw_magnitude = self._runner.predict_scalar(features)
                if apply_score is None or raw_magnitude is None:
                    return self._fallback_result(
                        normalized_actions,
                        fallback_reason="inference_failed",
                    )

                predicted_scale = max(0.0, min(3.0, float(raw_magnitude)))
                decision = "keep"
                min_scale_floor = _minimum_scale_floor(normalized_goal, strict=strict)
                preserve_audible_request = min_scale_floor >= 0.75

                if apply_score < 0.15:
                    if not strict and not preserve_audible_request:
                        debug_entries.append(
                            {
                                "action_index": index,
                                "action_type": action["type"],
                                "before": action,
                                "apply_score": apply_score,
                                "raw_magnitude": raw_magnitude,
                                "decision": "drop",
                                "dropped": True,
                            }
                        )
                        continue
                    predicted_scale = min(predicted_scale, 0.25)
                    decision = (
                        "preserve_audible_floor"
                        if preserve_audible_request
                        else "strong_attenuate"
                    )

                if apply_score < 0.5:
                    if not strict:
                        predicted_scale = min(predicted_scale, 0.35)
                        decision = "attenuate_non_strict"
                    else:
                        predicted_scale = min(predicted_scale, 0.65)
                        if decision == "keep":
                            decision = "attenuate_strict"

                predicted_scale = max(predicted_scale, min_scale_floor)
                predicted_scale = max(0.0, min(3.0, predicted_scale))
                refined_action = _scale_action(
                    normalized_project,
                    action,
                    predicted_scale,
                )
                refined_actions.append(refined_action)
                debug_entries.append(
                    {
                        "action_index": index,
                        "action_type": action["type"],
                        "before": action,
                        "after": refined_action,
                        "apply_score": apply_score,
                        "raw_magnitude": raw_magnitude,
                        "final_scale": predicted_scale,
                        "decision": decision,
                        "dropped": False,
                    }
                )

            observability = {
                **self._runner.observability_context(),
                "mix_model_onnx_ms": int((time.perf_counter() - onnx_started_at) * 1000),
            }
            return {
                "actions": refined_actions,
                "fallback_used": False,
                "fallback_reason": "",
                "debug_entries": debug_entries,
                "observability": observability,
            }
        except Exception:
            return self._fallback_result(
                normalized_actions,
                fallback_reason="inference_failed",
            )

    def _fallback_result(
        self,
        actions: list[dict[str, Any]],
        *,
        fallback_reason: str,
    ) -> dict[str, Any]:
        return {
            "actions": actions,
            "fallback_used": True,
            "fallback_reason": fallback_reason,
            "debug_entries": [],
            "observability": self._runner.observability_context(),
        }

    def _build_context_features(
        self,
        *,
        project: dict[str, Any],
        goal: dict[str, Any],
        actions: list[dict[str, Any]],
        strict: bool,
    ) -> list[float]:
        rows_with_audio = [row for row in _project_rows(project) if _row_has_audio(row)]
        rms = sorted(_row_approx_rms(row) for row in rows_with_audio)
        crest_norm = sorted(
            max(0.0, min(1.0, _row_approx_crest(row) / 20.0)) for row in rows_with_audio
        )
        centroid_norm = sorted(
            max(0.0, min(1.0, _audio_stat(row, "centroid_hz") / 8000.0))
            for row in rows_with_audio
        )
        zcr = sorted(max(0.0, min(1.0, _audio_stat(row, "zcr"))) for row in rows_with_audio)
        sibilance = sorted(
            max(0.0, min(1.0, _audio_stat(row, "sibilance") / 5.0))
            for row in rows_with_audio
        )
        bassiness = sorted(
            max(0.0, min(1.0, _audio_stat(row, "bassiness") / 5.0))
            for row in rows_with_audio
        )
        hf_rms = sorted(
            max(0.0, min(1.0, _audio_stat(row, "hf_rms"))) for row in rows_with_audio
        )
        st_rms_mean = sorted(
            max(0.0, min(1.0, _audio_stat(row, "st_rms_mean"))) for row in rows_with_audio
        )
        st_rms_p95 = sorted(
            max(0.0, min(1.0, _audio_stat(row, "st_rms_p95"))) for row in rows_with_audio
        )
        st_rms_std = sorted(
            max(0.0, min(1.0, _audio_stat(row, "st_rms_std"))) for row in rows_with_audio
        )
        transient_density = sorted(
            max(0.0, min(1.0, _audio_stat(row, "transient_density")))
            for row in rows_with_audio
        )
        true_peak_norm = sorted(_norm_dbfs(_audio_stat(row, "true_peak_dbfs")) for row in rows_with_audio)
        integrated_lufs_norm = sorted(
            _norm_lufs_db(_audio_stat(row, "integrated_lufs_est")) for row in rows_with_audio
        )
        short_lufs_mean_norm = sorted(
            _norm_lufs_db(_audio_stat(row, "short_lufs_mean")) for row in rows_with_audio
        )
        short_lufs_p95_norm = sorted(
            _norm_lufs_db(_audio_stat(row, "short_lufs_p95")) for row in rows_with_audio
        )
        lra_norm = sorted(
            max(0.0, min(1.0, _audio_stat(row, "lra_est") / 40.0)) for row in rows_with_audio
        )
        clip_ratio = sorted(
            max(0.0, min(1.0, _audio_stat(row, "clip_ratio"))) for row in rows_with_audio
        )
        spectral_flatness = sorted(
            max(0.0, min(1.0, _audio_stat(row, "spectral_flatness")))
            for row in rows_with_audio
        )
        spectral_rolloff_norm = sorted(
            max(0.0, min(1.0, _audio_stat(row, "spectral_rolloff_hz") / 8000.0))
            for row in rows_with_audio
        )
        spectral_slope_norm = sorted(
            _norm_slope(_audio_stat(row, "spectral_slope")) for row in rows_with_audio
        )
        spectral_flux = sorted(
            max(0.0, min(1.0, _audio_stat(row, "spectral_flux"))) for row in rows_with_audio
        )
        phase_corr_norm = sorted(
            _norm_phase_corr(_audio_stat(row, "phase_corr")) for row in rows_with_audio
        )
        side_ratio_norm = sorted(
            max(0.0, min(1.0, _audio_stat(row, "side_ratio") / 2.0))
            for row in rows_with_audio
        )
        stereo_imbalance = sorted(
            max(0.0, min(1.0, _audio_stat(row, "stereo_imbalance")))
            for row in rows_with_audio
        )
        silence_ratio = sorted(
            max(0.0, min(1.0, _audio_stat(row, "silence_ratio"))) for row in rows_with_audio
        )
        onset_rate_norm = sorted(
            max(0.0, min(1.0, _audio_stat(row, "onset_rate_hz") / 20.0))
            for row in rows_with_audio
        )
        noise_floor_norm = sorted(
            _norm_dbfs(_audio_stat(row, "noise_floor_dbfs")) for row in rows_with_audio
        )
        spectral_bandwidth_norm = sorted(
            max(0.0, min(1.0, _audio_stat(row, "spectral_bandwidth_hz") / 8000.0))
            for row in rows_with_audio
        )

        median_rms = _median(rms)
        rms_iqr = (_q(rms, 0.75) - _q(rms, 0.25)) if rms else 0.0
        median_crest_norm = _q(crest_norm, 0.5) if crest_norm else 0.0
        median_centroid_norm = _q(centroid_norm, 0.5) if centroid_norm else 0.0
        median_zcr = _q(zcr, 0.5) if zcr else 0.0
        median_sibilance_norm = _q(sibilance, 0.5) if sibilance else 0.0
        median_bassiness_norm = _q(bassiness, 0.5) if bassiness else 0.0
        median_hf_rms = _q(hf_rms, 0.5) if hf_rms else 0.0
        median_st_rms_mean = _q(st_rms_mean, 0.5) if st_rms_mean else 0.0
        median_st_rms_p95 = _q(st_rms_p95, 0.5) if st_rms_p95 else 0.0
        median_st_rms_std = _q(st_rms_std, 0.5) if st_rms_std else 0.0
        median_transient_density = (
            _q(transient_density, 0.5) if transient_density else 0.0
        )
        median_true_peak_norm = _q(true_peak_norm, 0.5) if true_peak_norm else 0.0
        median_integrated_lufs_norm = (
            _q(integrated_lufs_norm, 0.5) if integrated_lufs_norm else 0.0
        )
        median_short_lufs_mean_norm = (
            _q(short_lufs_mean_norm, 0.5) if short_lufs_mean_norm else 0.0
        )
        median_short_lufs_p95_norm = (
            _q(short_lufs_p95_norm, 0.5) if short_lufs_p95_norm else 0.0
        )
        median_lra_norm = _q(lra_norm, 0.5) if lra_norm else 0.0
        median_clip_ratio = _q(clip_ratio, 0.5) if clip_ratio else 0.0
        median_spectral_flatness = (
            _q(spectral_flatness, 0.5) if spectral_flatness else 0.0
        )
        median_spectral_rolloff_norm = (
            _q(spectral_rolloff_norm, 0.5) if spectral_rolloff_norm else 0.0
        )
        median_spectral_slope_norm = (
            _q(spectral_slope_norm, 0.5) if spectral_slope_norm else 0.0
        )
        median_spectral_flux = _q(spectral_flux, 0.5) if spectral_flux else 0.0
        median_phase_corr_norm = _q(phase_corr_norm, 0.5) if phase_corr_norm else 0.0
        median_side_ratio_norm = _q(side_ratio_norm, 0.5) if side_ratio_norm else 0.0
        median_stereo_imbalance = (
            _q(stereo_imbalance, 0.5) if stereo_imbalance else 0.0
        )
        median_silence_ratio = _q(silence_ratio, 0.5) if silence_ratio else 0.0
        median_onset_rate_norm = _q(onset_rate_norm, 0.5) if onset_rate_norm else 0.0
        median_noise_floor_norm = (
            _q(noise_floor_norm, 0.5) if noise_floor_norm else 0.0
        )
        median_spectral_bandwidth_norm = (
            _q(spectral_bandwidth_norm, 0.5)
            if spectral_bandwidth_norm
            else 0.0
        )

        row_gain_ops = sum(1 for action in actions if action["type"] == "set_row_gain")
        row_pan_ops = sum(1 for action in actions if action["type"] == "set_row_pan")
        fx_ops = sum(1 for action in actions if "effect" in action["type"])
        master_ops = sum(1 for action in actions if "master" in action["type"])

        scope = _goal_target_scope(goal)
        kind = _goal_kind(goal)
        overlap_metrics = _overlap_metrics(project, rows_with_audio)
        st_dynamic_headroom = max(0.0, min(1.0, median_st_rms_p95 - median_st_rms_mean))

        return [
            _goal_intensity(goal),
            1.0 if strict else 0.0,
            max(0.0, min(1.0, _project_bpm(project) / 240.0)),
            max(
                0.0,
                min(
                    1.0,
                    len(rows_with_audio) / max(1.0, float(_project_max_rows(project))),
                ),
            ),
            median_rms,
            row_gain_ops / 12.0,
            row_pan_ops / 12.0,
            fx_ops / 20.0,
            master_ops / 12.0,
            1.0 if scope == "auto" else 0.0,
            1.0 if scope == "row" else 0.0,
            1.0 if scope == "master" else 0.0,
            1.0 if kind == "balance" else 0.0,
            1.0 if kind == "gain" else 0.0,
            1.0 if kind == "pan" else 0.0,
            1.0 if kind == "eq" else 0.0,
            1.0 if kind == "compressor" else 0.0,
            1.0 if kind == "limiter" else 0.0,
            1.0 if kind == "clipper" else 0.0,
            1.0 if kind == "reverb" else 0.0,
            1.0 if kind == "delay" else 0.0,
            1.0 if kind == "deesser" else 0.0,
            1.0 if kind == "distortion" else 0.0,
            median_crest_norm,
            max(0.0, min(1.0, rms_iqr)),
            median_centroid_norm,
            median_zcr,
            median_sibilance_norm,
            median_bassiness_norm,
            median_hf_rms,
            median_st_rms_mean,
            median_st_rms_p95,
            median_st_rms_std,
            median_transient_density,
            overlap_metrics.overlap_density,
            overlap_metrics.masking_pair_ratio,
            overlap_metrics.centroid_collision_ratio,
            overlap_metrics.avg_overlap_centroid_gap_norm,
            overlap_metrics.overlap_rms_pressure,
            overlap_metrics.role_overlap_ratio,
            st_dynamic_headroom,
            median_true_peak_norm,
            median_integrated_lufs_norm,
            median_short_lufs_mean_norm,
            median_short_lufs_p95_norm,
            median_lra_norm,
            median_clip_ratio,
            median_spectral_flatness,
            median_spectral_rolloff_norm,
            median_spectral_slope_norm,
            median_spectral_flux,
            median_phase_corr_norm,
            median_side_ratio_norm,
            median_stereo_imbalance,
            median_silence_ratio,
            median_onset_rate_norm,
            median_noise_floor_norm,
            median_spectral_bandwidth_norm,
            overlap_metrics.low_collision_ratio,
            overlap_metrics.lowmid_collision_ratio,
            overlap_metrics.mid_collision_ratio,
            overlap_metrics.high_collision_ratio,
        ]

    def _build_action_features(
        self,
        project: dict[str, Any],
        action: dict[str, Any],
    ) -> list[float]:
        action_type = action["type"]
        ai_magnitude = _action_magnitude(project, action)
        is_master = 1.0 if "master" in action_type else 0.0
        known = {
            "set_row_gain",
            "set_row_pan",
            "set_master_gain",
            "set_master_pan",
            "adjust_effect_param_by_name",
            "adjust_master_effect_param_by_name",
            "ensure_effect",
            "ensure_master_effect",
            "delete_effect",
            "delete_master_effect",
            "hard_reset_row_fx",
            "hard_reset_master_fx",
        }

        def flag(candidate: str) -> float:
            return 1.0 if action_type == candidate else 0.0

        return [
            max(0.0, min(3.0, ai_magnitude)),
            is_master,
            flag("set_row_gain"),
            flag("set_row_pan"),
            flag("set_master_gain"),
            flag("set_master_pan"),
            flag("adjust_effect_param_by_name"),
            flag("adjust_master_effect_param_by_name"),
            flag("ensure_effect"),
            flag("ensure_master_effect"),
            flag("delete_effect"),
            flag("delete_master_effect"),
            flag("hard_reset_row_fx"),
            flag("hard_reset_master_fx"),
            0.0 if action_type in known else 1.0,
        ]


def _max_actions() -> int:
    raw = os.environ.get("MIX_RESOLVE_MAX_ACTIONS", "").strip()
    try:
        return max(1, int(raw))
    except ValueError:
        return _MAX_ACTIONS


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


def _package_root() -> Path:
    return Path(__file__).resolve().parents[1]


def _cache_root_dir() -> Path:
    configured = (
        os.environ.get("MIX_MODEL_CACHE_DIRECTORY", "").strip()
        or os.environ.get("MIXROOM_MAGNITUDE_MODEL_CACHE_DIRECTORY", "").strip()
    )
    raw = configured or _DEFAULT_CACHE_DIRECTORY
    return Path(raw).expanduser()


def _manifest_url() -> str:
    configured = (
        os.environ.get("MIX_MODEL_MANIFEST_URL", "").strip()
        or os.environ.get("MIXROOM_MAGNITUDE_MODEL_MANIFEST_URL", "").strip()
    )
    return configured or _DEFAULT_MANIFEST_URL


def _manifest_timeout_seconds() -> int:
    configured = (
        os.environ.get("MIX_MODEL_MANIFEST_TIMEOUT_SECONDS", "").strip()
        or os.environ.get("MIXROOM_MAGNITUDE_MODEL_MANIFEST_TIMEOUT_SECONDS", "").strip()
    )
    try:
        return max(1, int(configured))
    except ValueError:
        return _DEFAULT_MANIFEST_TIMEOUT_SECONDS


def _download_timeout_seconds() -> int:
    configured = (
        os.environ.get("MIX_MODEL_DOWNLOAD_TIMEOUT_SECONDS", "").strip()
        or os.environ.get("MIXROOM_MAGNITUDE_MODEL_DOWNLOAD_TIMEOUT_SECONDS", "").strip()
    )
    try:
        return max(1, int(configured))
    except ValueError:
        return _DEFAULT_DOWNLOAD_TIMEOUT_SECONDS


def _safe_path_component(raw: str) -> str:
    trimmed = str(raw or "").strip()
    if not trimmed:
        return hashlib.sha256(b"empty").hexdigest()[:16]
    safe = "".join(
        character
        if character.isalnum() or character in {"-", "_", "."}
        else "_"
        for character in trimmed
    ).strip("._")
    if safe:
        return safe
    return hashlib.sha256(trimmed.encode("utf-8")).hexdigest()[:16]


def _load_remote_manifest(manifest_url: str) -> _RemoteBundleManifest:
    parsed_manifest = urlparse(manifest_url)
    if parsed_manifest.scheme not in {"https", "http", "file"}:
        raise ValueError("Unsupported mix model manifest URL scheme.")

    with urlopen(manifest_url, timeout=_manifest_timeout_seconds()) as response:
        payload = json.load(response)

    if not isinstance(payload, dict):
        raise ValueError("Mix model manifest root must be an object.")

    def parse_asset(raw: Any, *, default_filename: str) -> _RemoteModelAssetSpec:
        if not isinstance(raw, dict):
            raise ValueError("Mix model manifest asset entry must be an object.")
        version = str(raw.get("version") or "").strip()
        url = str(raw.get("url") or "").strip()
        sha256_hex = str(raw.get("sha256") or "").strip().lower()
        file_name = str(raw.get("file_name") or default_filename).strip()
        if not version or not url or not sha256_hex or not file_name:
            raise ValueError("Mix model manifest asset fields are incomplete.")
        if len(sha256_hex) != 64 or any(
            character not in "0123456789abcdef" for character in sha256_hex
        ):
            raise ValueError("Mix model manifest asset checksum is invalid.")
        parsed_asset = urlparse(url)
        if parsed_asset.scheme not in {"https", "http", "file"}:
            raise ValueError("Unsupported mix model asset URL scheme.")
        return _RemoteModelAssetSpec(
            version=version,
            url=url,
            sha256_hex=sha256_hex,
            file_name=file_name,
        )

    bundle_version = str(payload.get("bundle_version") or "").strip()
    if not bundle_version:
        raise ValueError("Mix model manifest bundle_version is required.")

    return _RemoteBundleManifest(
        bundle_version=bundle_version,
        apply_model=parse_asset(
            payload.get("apply_model"),
            default_filename=_DEFAULT_APPLY_MODEL_FILENAME,
        ),
        magnitude_model=parse_asset(
            payload.get("magnitude_model"),
            default_filename=_DEFAULT_MAGNITUDE_MODEL_FILENAME,
        ),
    )


def _download_url_to_file(
    url: str,
    destination: Path,
    *,
    timeout_seconds: int,
) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with urlopen(url, timeout=timeout_seconds) as response, destination.open("wb") as handle:
        shutil.copyfileobj(response, handle)


def _sha256_for_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def _is_trusted_asset_url(parsed_manifest: Any, parsed_asset: Any) -> bool:
    if parsed_asset.scheme not in {"https", "http", "file"}:
        return False
    if parsed_manifest.scheme == "file":
        return parsed_asset.scheme == "file"
    return (
        parsed_manifest.scheme == parsed_asset.scheme
        and parsed_manifest.netloc == parsed_asset.netloc
    )


def _basename_without_extension(value: str) -> str:
    raw = str(value or "").strip()
    if not raw:
        return ""
    return Path(raw).stem


def _normalize_project(project: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(project, dict):
        raise MixResolveValidationError("project_state must be an object.")
    rows = project.get("rows")
    if not isinstance(rows, list):
        raise MixResolveValidationError("project_state.rows must be a list.")
    return project


def _normalize_goal(goal: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(goal, dict):
        raise MixResolveValidationError("goal must be an object.")
    return goal


def _normalize_actions(actions: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if not isinstance(actions, list):
        raise MixResolveValidationError("actions must be a list.")
    normalized: list[dict[str, Any]] = []
    for raw in actions:
        if not isinstance(raw, dict):
            raise MixResolveValidationError("Each action must be an object.")
        action_type = str(raw.get("type") or "").strip()
        if not action_type:
            raise MixResolveValidationError("Each action requires a type.")
        data = raw.get("data")
        if data is None:
            data = {}
        if not isinstance(data, dict):
            raise MixResolveValidationError("Each action data field must be an object.")
        normalized.append(
            {
                "type": action_type,
                "data": dict(data),
            }
        )
    return normalized


def _project_rows(project: dict[str, Any]) -> list[dict[str, Any]]:
    rows = project.get("rows")
    if isinstance(rows, list):
        return [row for row in rows if isinstance(row, dict)]
    return []


def _project_bpm(project: dict[str, Any]) -> float:
    return _as_float(project.get("bpm"))


def _project_max_rows(project: dict[str, Any]) -> int:
    raw = project.get("max_rows")
    if isinstance(raw, int):
        return raw
    if isinstance(raw, float):
        return int(raw)
    return max(1, len(_project_rows(project)))


def _row_has_audio(row: dict[str, Any]) -> bool:
    return row.get("hasAudio") is True


def _row_approx_rms(row: dict[str, Any]) -> float:
    features = row.get("features")
    if isinstance(features, dict):
        return _as_float(features.get("approx_rms"))
    return 0.0


def _row_approx_crest(row: dict[str, Any]) -> float:
    features = row.get("features")
    if isinstance(features, dict):
        return _as_float(features.get("approx_crest"))
    return 0.0


def _row_index(row: dict[str, Any]) -> int:
    raw = row.get("row")
    if isinstance(raw, int):
        return raw
    if isinstance(raw, float):
        return int(raw)
    return -1


def _audio_stat(row: dict[str, Any], key: str) -> float:
    stats = row.get("audio_stats")
    if isinstance(stats, dict):
        return _as_float(stats.get(key))
    return 0.0


def _top_role(row: dict[str, Any]) -> str:
    role_probs = row.get("role_probs")
    if not isinstance(role_probs, dict) or not role_probs:
        return "other"
    best_key = "other"
    best_value = float("-inf")
    for key, value in role_probs.items():
        if not isinstance(value, (int, float)):
            continue
        if float(value) > best_value:
            best_key = str(key).strip().lower() or "other"
            best_value = float(value)
    return best_key or "other"


def _goal_intensity(goal: dict[str, Any]) -> float:
    return max(0.0, min(1.0, _as_float(goal.get("intensity"), 0.5)))


def _goal_execution_profile(goal: dict[str, Any]) -> str:
    value = str(goal.get("execution_profile") or "").strip().lower()
    if value in {"producer_safe", "creative_bold", "experimental_extreme"}:
        return value
    return "producer_safe"


def _goal_audibility(goal: dict[str, Any]) -> str:
    value = str(goal.get("audibility") or "").strip().lower()
    if value in {"subtle", "noticeable", "obvious", "extreme"}:
        return value
    return "noticeable"


def _goal_target_scope(goal: dict[str, Any]) -> str:
    target = goal.get("target")
    if isinstance(target, dict):
        scope = str(target.get("scope") or "").strip().lower()
        if scope in {"auto", "row", "master"}:
            return scope
    return "auto"


def _goal_kind(goal: dict[str, Any]) -> str:
    intents = goal.get("intents")
    if isinstance(intents, list):
        for raw in intents:
            if isinstance(raw, dict):
                kind = str(raw.get("kind") or "").strip().lower()
                if kind:
                    return kind
    return "balance"


def _goal_destructive(goal: dict[str, Any]) -> bool:
    return goal.get("destructive_ok") is True or _goal_execution_profile(goal) == "experimental_extreme"


def _has_reference_target(goal: dict[str, Any]) -> bool:
    target = goal.get("reference_target")
    if not isinstance(target, dict):
        return False
    row_index = target.get("row_index")
    prefer_selected = target.get("prefer_selected") is True
    return isinstance(row_index, (int, float)) or prefer_selected


def _minimum_scale_floor(goal: dict[str, Any], *, strict: bool) -> float:
    destructive = _goal_destructive(goal)
    profile = _goal_execution_profile(goal)
    audibility = _goal_audibility(goal)
    if profile == "producer_safe":
        if audibility in {"subtle", "noticeable"}:
            return 0.0
        if audibility == "obvious":
            return 0.75 if strict else 0.85
        return 0.85 if strict else 1.0
    if profile == "creative_bold":
        if audibility == "subtle":
            return 0.55
        if audibility == "noticeable":
            return 0.8
        if audibility == "obvious":
            return 1.0
        return 1.25 if destructive else 1.1
    return 1.35 if destructive else 1.1


def _action_magnitude(project: dict[str, Any], action: dict[str, Any]) -> float:
    data = action["data"]
    mode = str(data.get("mode") or "delta").strip().lower()
    if mode == "set":
        action_type = action["type"]
        if action_type == "set_row_gain":
            row = _row_for_index(project, data.get("row"))
            target = data.get("value")
            if row is not None and isinstance(target, (int, float)):
                return abs(float(target) - _row_mix_value(row, "gain_0to3"))
        elif action_type == "set_row_pan":
            row = _row_for_index(project, data.get("row"))
            target = data.get("value")
            if row is not None and isinstance(target, (int, float)):
                return abs(float(target) - _row_mix_value(row, "pan_0to1", 0.5))
        elif action_type == "set_master_gain":
            target = data.get("value")
            if isinstance(target, (int, float)):
                return abs(float(target) - _as_float(project.get("master_gain_0to3"), 1.0))
        elif action_type == "set_master_pan":
            target = data.get("value")
            if isinstance(target, (int, float)):
                return abs(float(target) - _as_float(project.get("master_pan_0to1"), 0.5))
        elif action_type == "adjust_effect_param_by_name":
            lookup = _lookup_row_effect_param(project, data)
            target = data.get("value")
            if lookup is not None and isinstance(target, (int, float)):
                return abs(float(target) - lookup.current)
        elif action_type == "adjust_master_effect_param_by_name":
            lookup = _lookup_master_effect_param(project, data)
            target = data.get("value")
            if lookup is not None and isinstance(target, (int, float)):
                return abs(float(target) - lookup.current)
        return 1.0

    if isinstance(data.get("delta"), (int, float)):
        return abs(float(data["delta"]))
    if isinstance(data.get("delta_norm"), (int, float)):
        return abs(float(data["delta_norm"]))
    return 1.0


def _scale_action(
    project: dict[str, Any],
    action: dict[str, Any],
    scale: float,
) -> dict[str, Any]:
    if abs(scale - 1.0) < 0.03:
        return action

    data = dict(action["data"])
    mode = str(data.get("mode") or "delta").strip().lower()

    def scale_key(key: str) -> None:
        value = data.get(key)
        if isinstance(value, (int, float)):
            data[key] = float(value) * scale

    action_type = action["type"]
    if action_type == "set_row_gain":
        if mode == "set" and isinstance(data.get("value"), (int, float)):
            row = _row_for_index(project, data.get("row"))
            if row is not None and _row_has_audio(row):
                current = _row_mix_value(row, "gain_0to3")
                target = float(data["value"])
                data["value"] = max(0.0, min(3.0, current + (target - current) * scale))
        else:
            scale_key("delta")
    elif action_type == "set_row_pan":
        if mode == "set" and isinstance(data.get("value"), (int, float)):
            row = _row_for_index(project, data.get("row"))
            if row is not None and _row_has_audio(row):
                current = _row_mix_value(row, "pan_0to1", 0.5)
                target = float(data["value"])
                data["value"] = max(0.0, min(1.0, current + (target - current) * scale))
        else:
            scale_key("delta")
    elif action_type == "set_master_gain":
        if mode == "set" and isinstance(data.get("value"), (int, float)):
            current = _as_float(project.get("master_gain_0to3"), 1.0)
            target = float(data["value"])
            data["value"] = max(0.0, min(3.0, current + (target - current) * scale))
        else:
            scale_key("delta")
    elif action_type == "set_master_pan":
        if mode == "set" and isinstance(data.get("value"), (int, float)):
            current = _as_float(project.get("master_pan_0to1"), 0.5)
            target = float(data["value"])
            data["value"] = max(0.0, min(1.0, current + (target - current) * scale))
        else:
            scale_key("delta")
    elif action_type == "adjust_effect_param_by_name":
        if mode == "set":
            _scale_effect_set_action(
                data=data,
                scale=scale,
                lookup=_lookup_row_effect_param(project, data),
            )
        else:
            scale_key("delta")
            scale_key("delta_norm")
    elif action_type == "adjust_master_effect_param_by_name":
        if mode == "set":
            _scale_effect_set_action(
                data=data,
                scale=scale,
                lookup=_lookup_master_effect_param(project, data),
            )
        else:
            scale_key("delta")
            scale_key("delta_norm")

    return {
        "type": action_type,
        "data": data,
    }


def _scale_effect_set_action(
    *,
    data: dict[str, Any],
    scale: float,
    lookup: _ParamLookup | None,
) -> None:
    if lookup is None:
        return
    if isinstance(data.get("value"), (int, float)):
        current = lookup.current
        target = float(data["value"])
        next_value = current + (target - current) * scale
        if lookup.minimum is not None and lookup.maximum is not None:
            next_value = max(lookup.minimum, min(lookup.maximum, next_value))
        elif data.get("clamp_0_1") is True:
            next_value = max(0.0, min(1.0, next_value))
        data["value"] = next_value
        data.pop("value_norm", None)
        return
    if (
        isinstance(data.get("value_norm"), (int, float))
        and lookup.minimum is not None
        and lookup.maximum is not None
    ):
        value_norm = max(0.0, min(1.0, float(data["value_norm"])))
        target = lookup.minimum + (lookup.maximum - lookup.minimum) * value_norm
        next_value = lookup.current + (target - lookup.current) * scale
        next_value = max(lookup.minimum, min(lookup.maximum, next_value))
        data["value"] = next_value
        data.pop("value_norm", None)


def _lookup_row_effect_param(project: dict[str, Any], data: dict[str, Any]) -> _ParamLookup | None:
    row = _row_for_index(project, data.get("row"))
    if row is None:
        return None
    effect_contains = str(data.get("effect_name_contains") or "").strip().lower()
    if not effect_contains:
        return None
    for effect in _row_effects(row):
        effect_name = str(effect.get("name") or "").strip().lower()
        if effect_contains in effect_name:
            return _lookup_param_in_effect(effect, data)
    return None


def _lookup_master_effect_param(project: dict[str, Any], data: dict[str, Any]) -> _ParamLookup | None:
    effect_contains = str(data.get("effect_name_contains") or "").strip().lower()
    if not effect_contains:
        return None
    effects = project.get("master_effects")
    if not isinstance(effects, list):
        return None
    for effect in effects:
        if not isinstance(effect, dict):
            continue
        effect_name = str(effect.get("name") or "").strip().lower()
        if effect_contains in effect_name:
            return _lookup_param_in_effect(effect, data)
    return None


def _lookup_param_in_effect(effect: dict[str, Any], data: dict[str, Any]) -> _ParamLookup | None:
    exact = str(data.get("param_name") or "").strip().lower()
    contains_any_raw = data.get("param_name_contains_any")
    contains_any = (
        [str(item).strip().lower() for item in contains_any_raw if str(item).strip()]
        if isinstance(contains_any_raw, list)
        else []
    )
    parameters = effect.get("parameters")
    if not isinstance(parameters, list):
        return None
    for parameter in parameters:
        if not isinstance(parameter, dict):
            continue
        name = str(parameter.get("name") or "").strip().lower()
        exact_match = bool(exact) and name == exact
        fuzzy_match = bool(contains_any) and any(token in name for token in contains_any)
        if not exact_match and not fuzzy_match:
            continue
        value = parameter.get("value")
        if not isinstance(value, (int, float)):
            return None
        minimum = parameter.get("min")
        maximum = parameter.get("max")
        return _ParamLookup(
            current=float(value),
            minimum=float(minimum) if isinstance(minimum, (int, float)) else None,
            maximum=float(maximum) if isinstance(maximum, (int, float)) else None,
        )
    return None


def _row_for_index(project: dict[str, Any], row_index: Any) -> dict[str, Any] | None:
    if not isinstance(row_index, (int, float)):
        return None
    target = int(row_index)
    rows = _project_rows(project)
    if 0 <= target < len(rows):
        return rows[target]
    for row in rows:
        if _row_index(row) == target:
            return row
    return None


def _row_effects(row: dict[str, Any]) -> list[dict[str, Any]]:
    effects = row.get("effects")
    if isinstance(effects, list):
        return [effect for effect in effects if isinstance(effect, dict)]
    return []


def _row_mix_value(row: dict[str, Any], key: str, fallback: float = 0.0) -> float:
    mix = row.get("mix")
    if isinstance(mix, dict):
        return _as_float(mix.get(key), fallback)
    return fallback


def _median(values: list[float]) -> float:
    if not values:
        return 0.0
    mid = len(values) // 2
    if len(values) % 2 == 1:
        return values[mid]
    return (values[mid - 1] + values[mid]) * 0.5


def _q(sorted_values: list[float], q: float) -> float:
    if not sorted_values:
        return 0.0
    if len(sorted_values) == 1:
        return sorted_values[0]
    qq = max(0.0, min(1.0, q))
    pos = qq * (len(sorted_values) - 1)
    lo = math.floor(pos)
    hi = math.ceil(pos)
    if lo == hi:
        return sorted_values[lo]
    t = pos - lo
    return sorted_values[lo] * (1.0 - t) + sorted_values[hi] * t


def _overlap_metrics(project: dict[str, Any], rows_with_audio: list[dict[str, Any]]) -> _OverlapMetrics:
    if len(rows_with_audio) < 2:
        return _OverlapMetrics()
    pair_count = len(rows_with_audio) * (len(rows_with_audio) - 1) / 2.0
    overlap_strength_sum = 0.0
    masking_strength_sum = 0.0
    centroid_collision_strength_sum = 0.0
    role_overlap_strength_sum = 0.0
    sum_gap_norm = 0.0
    sum_rms_pressure = 0.0
    low_collision_sum = 0.0
    lowmid_collision_sum = 0.0
    mid_collision_sum = 0.0
    high_collision_sum = 0.0

    for index, row_a in enumerate(rows_with_audio):
        for row_b in rows_with_audio[index + 1 :]:
            overlap_strength = _overlap_ratio(project, _row_index(row_a), _row_index(row_b))
            if overlap_strength <= 1e-6:
                continue
            overlap_strength_sum += overlap_strength

            centroid_a = _audio_stat(row_a, "centroid_hz")
            centroid_b = _audio_stat(row_b, "centroid_hz")
            gap_norm = max(0.0, min(1.0, abs(centroid_a - centroid_b) / 8000.0))
            sum_gap_norm += gap_norm * overlap_strength
            if gap_norm < 0.12:
                centroid_collision_strength_sum += overlap_strength

            rms_a = max(1e-6, _row_approx_rms(row_a))
            rms_b = max(1e-6, _row_approx_rms(row_b))
            ratio = max(rms_a, rms_b) / min(rms_a, rms_b)
            pressure = max(0.0, min(1.0, (ratio - 1.0) / 3.0))
            sum_rms_pressure += pressure * overlap_strength
            if ratio > 1.4 and gap_norm < 0.20:
                masking_strength_sum += overlap_strength

            role_a = _top_role(row_a)
            role_b = _top_role(row_b)
            if role_a != role_b and role_a != "other" and role_b != "other":
                role_overlap_strength_sum += overlap_strength

            low_collision_sum += _band_collision_score(row_a, row_b, "low") * overlap_strength
            lowmid_collision_sum += (
                _band_collision_score(row_a, row_b, "lowmid") * overlap_strength
            )
            mid_collision_sum += _band_collision_score(row_a, row_b, "mid") * overlap_strength
            high_collision_sum += _band_collision_score(row_a, row_b, "high") * overlap_strength

    if overlap_strength_sum <= 1e-6:
        return _OverlapMetrics(overlap_density=0.0)

    return _OverlapMetrics(
        overlap_density=max(0.0, min(1.0, overlap_strength_sum / pair_count)),
        masking_pair_ratio=max(0.0, min(1.0, masking_strength_sum / overlap_strength_sum)),
        centroid_collision_ratio=max(
            0.0, min(1.0, centroid_collision_strength_sum / overlap_strength_sum)
        ),
        avg_overlap_centroid_gap_norm=max(
            0.0, min(1.0, sum_gap_norm / overlap_strength_sum)
        ),
        overlap_rms_pressure=max(0.0, min(1.0, sum_rms_pressure / overlap_strength_sum)),
        role_overlap_ratio=max(0.0, min(1.0, role_overlap_strength_sum / overlap_strength_sum)),
        low_collision_ratio=max(0.0, min(1.0, low_collision_sum / overlap_strength_sum)),
        lowmid_collision_ratio=max(
            0.0, min(1.0, lowmid_collision_sum / overlap_strength_sum)
        ),
        mid_collision_ratio=max(0.0, min(1.0, mid_collision_sum / overlap_strength_sum)),
        high_collision_ratio=max(0.0, min(1.0, high_collision_sum / overlap_strength_sum)),
    )


def _overlap_ratio(project: dict[str, Any], a: int, b: int) -> float:
    overlap_ratio_matrix = project.get("overlap_ratio_matrix")
    ratio = 0.0
    if isinstance(overlap_ratio_matrix, list):
        ratio = max(ratio, _matrix_value(overlap_ratio_matrix, a, b))
        ratio = max(ratio, _matrix_value(overlap_ratio_matrix, b, a))
    if ratio > 0.0:
        return max(0.0, min(1.0, ratio))

    overlap_matrix = project.get("overlap_matrix")
    if isinstance(overlap_matrix, list):
        ab = _matrix_value(overlap_matrix, a, b) == 1
        ba = _matrix_value(overlap_matrix, b, a) == 1
        if ab or ba:
            return 1.0
    return 0.0


def _matrix_value(matrix: list[Any], i: int, j: int) -> float:
    if i < 0 or i >= len(matrix):
        return 0.0
    row = matrix[i]
    if not isinstance(row, list) or j < 0 or j >= len(row):
        return 0.0
    value = row[j]
    if isinstance(value, (int, float)):
        return float(value)
    return 0.0


def _norm_dbfs(value: float) -> float:
    return max(0.0, min(1.0, (value + 80.0) / 80.0))


def _norm_lufs_db(value: float) -> float:
    return max(0.0, min(1.0, (value + 80.0) / 80.0))


def _norm_slope(value: float) -> float:
    return max(0.0, min(1.0, (value + 2.0) / 4.0))


def _norm_phase_corr(value: float) -> float:
    return max(0.0, min(1.0, (value + 1.0) / 2.0))


def _band_share(row: dict[str, Any], key: str) -> float:
    low = max(0.0, _audio_stat(row, "low"))
    lowmid = max(0.0, _audio_stat(row, "lowmid"))
    mid = max(0.0, _audio_stat(row, "mid"))
    high = max(0.0, _audio_stat(row, "high"))
    total = max(1e-9, low + lowmid + mid + high)
    value = max(0.0, _audio_stat(row, key))
    return max(0.0, min(1.0, value / total))


def _band_collision_score(row_a: dict[str, Any], row_b: dict[str, Any], key: str) -> float:
    share_a = _band_share(row_a, key)
    share_b = _band_share(row_b, key)
    similarity = max(0.0, min(1.0, 1.0 - abs(share_a - share_b)))
    both_present = max(0.0, min(1.0, 2.0 * min(share_a, share_b)))
    return max(0.0, min(1.0, similarity * both_present))


def _as_float(value: Any, fallback: float = 0.0) -> float:
    if isinstance(value, bool):
        return 1.0 if value else 0.0
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value))
    except (TypeError, ValueError):
        return fallback
