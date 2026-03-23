#!/usr/bin/env python3
import argparse
import json
import math
import os
import shutil
import subprocess
import tempfile
import zipfile
from collections import Counter, defaultdict
from pathlib import Path

import pandas as pd

from prepare_dataset import (
    CANONICAL_KINDS,
    EXPECTED_FEATURE_COUNT,
    FEATURE_COLUMNS,
    _action_type_features,
    _count_action_groups,
    _project_stats,
)

UNITY_GAIN = 2.0
CENTER_PAN = 0.5
FALLBACK_TRACK_DURATION_MS = 8000.0

ROLE_KEYWORDS = {
    "vocals": ("vocal", "vox", "lead", "bgv", "backing", "choir", "hook"),
    "drums": ("drum", "kick", "snare", "hat", "tom", "perc", "808", "loop"),
    "bass": ("bass", "sub"),
    "guitar": ("guitar", "gtr", "gt"),
    "synth": ("synth", "pad", "arp", "pluck", "lead synth"),
    "piano": ("piano", "keys", "key", "rhodes", "organ"),
    "strings": ("string", "violin", "cello", "viola", "orchestra"),
}

ROLE_PROFILES = {
    "vocals": {
        "centroid_hz": 2500.0,
        "zcr": 0.11,
        "sibilance": 2.6,
        "bassiness": 0.45,
        "hf_rms": 0.42,
        "st_rms_mean": 0.34,
        "st_rms_p95": 0.58,
        "st_rms_std": 0.11,
        "transient_density": 0.28,
        "true_peak_dbfs": -3.2,
        "integrated_lufs_est": -18.0,
        "short_lufs_mean": -17.0,
        "short_lufs_p95": -12.5,
        "lra_est": 7.5,
        "clip_ratio": 0.01,
        "spectral_flatness": 0.22,
        "spectral_rolloff_hz": 5200.0,
        "spectral_slope": -0.15,
        "spectral_flux": 0.26,
        "phase_corr": 0.78,
        "side_ratio": 0.20,
        "stereo_imbalance": 0.08,
        "silence_ratio": 0.10,
        "onset_rate_hz": 3.4,
        "noise_floor_dbfs": -55.0,
        "spectral_bandwidth_hz": 2800.0,
        "low": 0.18,
        "lowmid": 0.22,
        "mid": 0.34,
        "high": 0.26,
        "approx_rms": 0.31,
        "approx_crest": 8.4,
    },
    "drums": {
        "centroid_hz": 1900.0,
        "zcr": 0.17,
        "sibilance": 0.8,
        "bassiness": 1.8,
        "hf_rms": 0.32,
        "st_rms_mean": 0.38,
        "st_rms_p95": 0.76,
        "st_rms_std": 0.18,
        "transient_density": 0.82,
        "true_peak_dbfs": -2.4,
        "integrated_lufs_est": -15.0,
        "short_lufs_mean": -13.2,
        "short_lufs_p95": -9.0,
        "lra_est": 5.2,
        "clip_ratio": 0.03,
        "spectral_flatness": 0.28,
        "spectral_rolloff_hz": 6000.0,
        "spectral_slope": -0.08,
        "spectral_flux": 0.54,
        "phase_corr": 0.66,
        "side_ratio": 0.14,
        "stereo_imbalance": 0.05,
        "silence_ratio": 0.18,
        "onset_rate_hz": 7.8,
        "noise_floor_dbfs": -50.0,
        "spectral_bandwidth_hz": 3600.0,
        "low": 0.32,
        "lowmid": 0.21,
        "mid": 0.26,
        "high": 0.21,
        "approx_rms": 0.37,
        "approx_crest": 10.2,
    },
    "bass": {
        "centroid_hz": 380.0,
        "zcr": 0.04,
        "sibilance": 0.12,
        "bassiness": 3.4,
        "hf_rms": 0.08,
        "st_rms_mean": 0.33,
        "st_rms_p95": 0.56,
        "st_rms_std": 0.09,
        "transient_density": 0.16,
        "true_peak_dbfs": -4.2,
        "integrated_lufs_est": -17.0,
        "short_lufs_mean": -16.2,
        "short_lufs_p95": -12.7,
        "lra_est": 5.8,
        "clip_ratio": 0.01,
        "spectral_flatness": 0.18,
        "spectral_rolloff_hz": 1800.0,
        "spectral_slope": -0.48,
        "spectral_flux": 0.14,
        "phase_corr": 0.91,
        "side_ratio": 0.05,
        "stereo_imbalance": 0.02,
        "silence_ratio": 0.06,
        "onset_rate_hz": 1.7,
        "noise_floor_dbfs": -60.0,
        "spectral_bandwidth_hz": 900.0,
        "low": 0.58,
        "lowmid": 0.24,
        "mid": 0.13,
        "high": 0.05,
        "approx_rms": 0.34,
        "approx_crest": 7.2,
    },
    "guitar": {
        "centroid_hz": 1800.0,
        "zcr": 0.09,
        "sibilance": 0.42,
        "bassiness": 0.85,
        "hf_rms": 0.24,
        "st_rms_mean": 0.28,
        "st_rms_p95": 0.52,
        "st_rms_std": 0.13,
        "transient_density": 0.34,
        "true_peak_dbfs": -4.0,
        "integrated_lufs_est": -19.0,
        "short_lufs_mean": -18.2,
        "short_lufs_p95": -13.8,
        "lra_est": 8.6,
        "clip_ratio": 0.01,
        "spectral_flatness": 0.24,
        "spectral_rolloff_hz": 4300.0,
        "spectral_slope": -0.22,
        "spectral_flux": 0.24,
        "phase_corr": 0.72,
        "side_ratio": 0.18,
        "stereo_imbalance": 0.07,
        "silence_ratio": 0.10,
        "onset_rate_hz": 2.8,
        "noise_floor_dbfs": -57.0,
        "spectral_bandwidth_hz": 2400.0,
        "low": 0.19,
        "lowmid": 0.28,
        "mid": 0.34,
        "high": 0.19,
        "approx_rms": 0.27,
        "approx_crest": 9.4,
    },
    "synth": {
        "centroid_hz": 1600.0,
        "zcr": 0.08,
        "sibilance": 0.35,
        "bassiness": 1.2,
        "hf_rms": 0.22,
        "st_rms_mean": 0.26,
        "st_rms_p95": 0.46,
        "st_rms_std": 0.10,
        "transient_density": 0.20,
        "true_peak_dbfs": -5.0,
        "integrated_lufs_est": -20.0,
        "short_lufs_mean": -18.6,
        "short_lufs_p95": -14.0,
        "lra_est": 6.0,
        "clip_ratio": 0.00,
        "spectral_flatness": 0.27,
        "spectral_rolloff_hz": 4700.0,
        "spectral_slope": -0.10,
        "spectral_flux": 0.18,
        "phase_corr": 0.60,
        "side_ratio": 0.28,
        "stereo_imbalance": 0.10,
        "silence_ratio": 0.08,
        "onset_rate_hz": 1.9,
        "noise_floor_dbfs": -62.0,
        "spectral_bandwidth_hz": 2600.0,
        "low": 0.16,
        "lowmid": 0.24,
        "mid": 0.34,
        "high": 0.26,
        "approx_rms": 0.24,
        "approx_crest": 6.8,
    },
    "piano": {
        "centroid_hz": 1250.0,
        "zcr": 0.06,
        "sibilance": 0.22,
        "bassiness": 1.0,
        "hf_rms": 0.18,
        "st_rms_mean": 0.25,
        "st_rms_p95": 0.49,
        "st_rms_std": 0.12,
        "transient_density": 0.24,
        "true_peak_dbfs": -5.3,
        "integrated_lufs_est": -21.0,
        "short_lufs_mean": -19.0,
        "short_lufs_p95": -14.4,
        "lra_est": 8.0,
        "clip_ratio": 0.00,
        "spectral_flatness": 0.20,
        "spectral_rolloff_hz": 3600.0,
        "spectral_slope": -0.18,
        "spectral_flux": 0.18,
        "phase_corr": 0.82,
        "side_ratio": 0.16,
        "stereo_imbalance": 0.06,
        "silence_ratio": 0.11,
        "onset_rate_hz": 2.1,
        "noise_floor_dbfs": -61.0,
        "spectral_bandwidth_hz": 2000.0,
        "low": 0.24,
        "lowmid": 0.30,
        "mid": 0.28,
        "high": 0.18,
        "approx_rms": 0.23,
        "approx_crest": 8.2,
    },
    "strings": {
        "centroid_hz": 1450.0,
        "zcr": 0.05,
        "sibilance": 0.20,
        "bassiness": 0.72,
        "hf_rms": 0.16,
        "st_rms_mean": 0.22,
        "st_rms_p95": 0.40,
        "st_rms_std": 0.08,
        "transient_density": 0.08,
        "true_peak_dbfs": -6.2,
        "integrated_lufs_est": -22.0,
        "short_lufs_mean": -20.6,
        "short_lufs_p95": -15.8,
        "lra_est": 7.1,
        "clip_ratio": 0.00,
        "spectral_flatness": 0.15,
        "spectral_rolloff_hz": 3100.0,
        "spectral_slope": -0.22,
        "spectral_flux": 0.11,
        "phase_corr": 0.84,
        "side_ratio": 0.20,
        "stereo_imbalance": 0.05,
        "silence_ratio": 0.05,
        "onset_rate_hz": 0.8,
        "noise_floor_dbfs": -64.0,
        "spectral_bandwidth_hz": 1800.0,
        "low": 0.18,
        "lowmid": 0.29,
        "mid": 0.33,
        "high": 0.20,
        "approx_rms": 0.20,
        "approx_crest": 6.4,
    },
    "other": {
        "centroid_hz": 1500.0,
        "zcr": 0.08,
        "sibilance": 0.40,
        "bassiness": 1.0,
        "hf_rms": 0.18,
        "st_rms_mean": 0.24,
        "st_rms_p95": 0.44,
        "st_rms_std": 0.10,
        "transient_density": 0.20,
        "true_peak_dbfs": -5.0,
        "integrated_lufs_est": -20.0,
        "short_lufs_mean": -18.5,
        "short_lufs_p95": -14.5,
        "lra_est": 7.0,
        "clip_ratio": 0.00,
        "spectral_flatness": 0.22,
        "spectral_rolloff_hz": 3400.0,
        "spectral_slope": -0.16,
        "spectral_flux": 0.18,
        "phase_corr": 0.78,
        "side_ratio": 0.14,
        "stereo_imbalance": 0.06,
        "silence_ratio": 0.08,
        "onset_rate_hz": 1.8,
        "noise_floor_dbfs": -60.0,
        "spectral_bandwidth_hz": 2100.0,
        "low": 0.22,
        "lowmid": 0.27,
        "mid": 0.29,
        "high": 0.22,
        "approx_rms": 0.22,
        "approx_crest": 7.4,
    },
}

NEGATIVE_ROW_EFFECT_KINDS = ("eq", "compressor", "reverb", "delay", "deesser", "distortion")
NEGATIVE_MASTER_EFFECT_KINDS = ("compressor", "limiter", "clipper")
SALIENT_PARAM_TOKENS = (
    "mix",
    "threshold",
    "frequency",
    "gain",
    "drive",
    "feedback",
    "attack",
    "release",
    "ratio",
    "ceiling",
    "room",
    "anger",
    "q",
)


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Build a trainable AI mixing dataset from finished Mixroom project "
            "folders or .mixroom bundles."
        )
    )
    parser.add_argument(
        "--projects-root",
        required=True,
        help="Directory, Mixroom project folder, project.json, or .mixroom bundle",
    )
    parser.add_argument(
        "--out-csv",
        required=True,
        help="Output dataset CSV path",
    )
    return parser.parse_args()


def _clamp(value, lo=0.0, hi=1.0):
    return max(lo, min(hi, float(value)))


def _safe_float(value, default=0.0):
    return float(value) if isinstance(value, (int, float)) else default


def _discover_sources(root_path):
    root = Path(root_path).expanduser().resolve()
    if not root.exists():
        raise SystemExit(f"Projects root not found: {root}")

    if root.is_file():
        if root.name == "project.json":
            return [("project_dir", root.parent)]
        if root.suffix.lower() == ".mixroom":
            return [("bundle", root)]
        raise SystemExit(f"Unsupported input file: {root}")

    if (root / "project.json").exists():
        return [("project_dir", root)]

    sources = []
    for project_json in root.rglob("project.json"):
        sources.append(("project_dir", project_json.parent))
    for bundle in root.rglob("*.mixroom"):
        sources.append(("bundle", bundle))

    unique = []
    seen = set()
    for source_type, path in sources:
        key = (source_type, str(path))
        if key in seen:
            continue
        seen.add(key)
        unique.append((source_type, path))
    return unique


def _infer_role(track):
    haystack = " ".join(
        str(track.get(key) or "")
        for key in ("label", "fileName", "instrumentName", "instrumentId")
    ).lower()
    for role, keywords in ROLE_KEYWORDS.items():
        if any(keyword in haystack for keyword in keywords):
            return role
    return "other"


def _role_probs(role):
    base = {
        "vocals": 0.03,
        "drums": 0.03,
        "bass": 0.03,
        "guitar": 0.03,
        "synth": 0.03,
        "piano": 0.03,
        "strings": 0.03,
        "other": 0.03,
    }
    base[role] = 0.85
    return base


def _effect_kind(effect_name):
    text = str(effect_name or "").lower()
    if "de-esser" in text or "deesser" in text:
        return "deesser"
    if "clipper" in text or "clip" in text:
        return "clipper"
    if "limit" in text:
        return "limiter"
    if "compress" in text:
        return "compressor"
    if "reverb" in text or "verb" in text:
        return "reverb"
    if "delay" in text or "echo" in text:
        return "delay"
    if "distort" in text or "satur" in text or "drive" in text:
        return "distortion"
    if "eq" in text or "filter" in text:
        return "eq"
    return "balance"


def _row_count(project_json):
    rows = project_json.get("rows")
    if isinstance(rows, list) and rows:
        return len(rows)

    max_row = -1
    for track in project_json.get("tracks", []) or []:
        row_index = track.get("rowIndex")
        if isinstance(row_index, int):
            max_row = max(max_row, row_index)
    for row_state in project_json.get("rowStates", []) or []:
        row = row_state.get("row")
        if isinstance(row, int):
            max_row = max(max_row, row)
    for row_fx in project_json.get("rowEffects", []) or []:
        row = row_fx.get("row")
        if isinstance(row, int):
            max_row = max(max_row, row)
    return max(max_row + 1, 1)


def _default_row_state(row):
    return {
        "row": row,
        "gain": UNITY_GAIN,
        "pan": CENTER_PAN,
        "volumeAutomation": [],
        "automationLanes": [],
        "automationClips": [],
    }


def _normalize_row_states(project_json, count):
    row_states = {row: _default_row_state(row) for row in range(count)}
    for raw_state in project_json.get("rowStates", []) or []:
        if not isinstance(raw_state, dict):
            continue
        row = raw_state.get("row")
        if not isinstance(row, int) or row < 0 or row >= count:
            continue
        row_states[row] = {
            "row": row,
            "gain": _safe_float(raw_state.get("gain"), UNITY_GAIN),
            "pan": _safe_float(raw_state.get("pan"), CENTER_PAN),
            "volumeAutomation": raw_state.get("volumeAutomation") or [],
            "automationLanes": raw_state.get("automationLanes") or [],
            "automationClips": raw_state.get("automationClips") or [],
        }
    return row_states


def _normalize_effect_snapshot(raw_snapshot, count):
    effects_by_row = {row: [] for row in range(count)}
    for raw_row in raw_snapshot or []:
        if not isinstance(raw_row, dict):
            continue
        row = raw_row.get("row")
        if not isinstance(row, int) or row < 0 or row >= count:
            continue
        normalized = []
        for raw_effect in raw_row.get("effects", []) or []:
            if not isinstance(raw_effect, dict):
                continue
            params = raw_effect.get("params") or {}
            if not isinstance(params, dict):
                params = {}
            normalized.append(
                {
                    "effectId": str(raw_effect.get("effectId") or ""),
                    "bypassed": bool(raw_effect.get("bypassed")),
                    "params": {str(k): v for k, v in params.items()},
                }
            )
        effects_by_row[row] = normalized
    return effects_by_row


def _normalize_master_effects(project_json):
    raw_master = project_json.get("master") if isinstance(project_json.get("master"), dict) else {}
    raw_effects = raw_master.get("effects") if isinstance(raw_master.get("effects"), dict) else {}
    normalized_effects = []
    for raw_effect in raw_effects.get("effects", []) or []:
        if not isinstance(raw_effect, dict):
            continue
        params = raw_effect.get("params") or {}
        if not isinstance(params, dict):
            params = {}
        normalized_effects.append(
            {
                "effectId": str(raw_effect.get("effectId") or ""),
                "bypassed": bool(raw_effect.get("bypassed")),
                "params": {str(k): v for k, v in params.items()},
            }
        )
    return {
        "gain": _safe_float(raw_master.get("gain"), UNITY_GAIN),
        "pan": _safe_float(raw_master.get("pan"), CENTER_PAN),
        "effects": normalized_effects,
    }


def _extract_track_intervals_ms(tracks, audio_root):
    duration_cache = {}
    row_intervals = defaultdict(list)

    for track in tracks:
        if not isinstance(track, dict):
            continue
        row = track.get("rowIndex")
        if not isinstance(row, int) or row < 0:
            continue

        start_ms = max(0.0, _safe_float(track.get("offset")) * 1000.0)
        trim_start_ms = max(0.0, _safe_float(track.get("trimStartMs")))
        trim_end_ms = max(0.0, _safe_float(track.get("trimEndMs")))
        clip_type = str(track.get("clipType") or "audio").lower()

        if clip_type == "midi":
            duration_ms = _midi_duration_ms(track)
        else:
            file_name = str(track.get("fileName") or "").strip()
            duration_ms = _audio_duration_ms(audio_root / "audio" / file_name, duration_cache)

        if duration_ms <= 0.0:
            duration_ms = FALLBACK_TRACK_DURATION_MS

        effective_ms = max(250.0, duration_ms - trim_start_ms - trim_end_ms)
        row_intervals[row].append((start_ms, start_ms + effective_ms))

    return row_intervals


def _midi_duration_ms(track):
    notes = track.get("midiNotes") or []
    if not isinstance(notes, list) or not notes:
        return FALLBACK_TRACK_DURATION_MS
    max_end_ms = 0.0
    for note in notes:
        if not isinstance(note, dict):
            continue
        start_beats = _safe_float(note.get("startBeat"))
        duration_beats = _safe_float(note.get("durationBeats"), 1.0)
        end_ms = (start_beats + duration_beats) * 500.0
        max_end_ms = max(max_end_ms, end_ms)
    return max(max_end_ms, FALLBACK_TRACK_DURATION_MS / 2.0)


def _audio_duration_ms(audio_path, cache):
    key = str(audio_path)
    if key in cache:
        return cache[key]

    if not audio_path.exists():
        cache[key] = FALLBACK_TRACK_DURATION_MS
        return cache[key]

    try:
        result = subprocess.run(
            [
                "ffprobe",
                "-v",
                "error",
                "-show_entries",
                "format=duration",
                "-of",
                "default=noprint_wrappers=1:nokey=1",
                str(audio_path),
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        duration_s = float((result.stdout or "0").strip() or "0")
        cache[key] = max(duration_s * 1000.0, FALLBACK_TRACK_DURATION_MS / 2.0)
    except Exception:
        cache[key] = FALLBACK_TRACK_DURATION_MS
    return cache[key]


def _overlap_matrices(row_intervals, row_count):
    overlap_matrix = [[0 for _ in range(row_count)] for _ in range(row_count)]
    overlap_ratio_matrix = [[0.0 for _ in range(row_count)] for _ in range(row_count)]

    totals = {}
    for row, intervals in row_intervals.items():
        totals[row] = sum(max(0.0, end - start) for start, end in intervals)

    for i in range(row_count):
        for j in range(i + 1, row_count):
            intervals_i = row_intervals.get(i, [])
            intervals_j = row_intervals.get(j, [])
            overlap_ms = 0.0
            for start_i, end_i in intervals_i:
                for start_j, end_j in intervals_j:
                    overlap_ms += max(0.0, min(end_i, end_j) - max(start_i, start_j))
            if overlap_ms <= 1.0:
                continue
            overlap_matrix[i][j] = 1
            overlap_matrix[j][i] = 1
            denom = min(max(totals.get(i, 1.0), 1.0), max(totals.get(j, 1.0), 1.0))
            ratio = _clamp(overlap_ms / denom)
            overlap_ratio_matrix[i][j] = ratio
            overlap_ratio_matrix[j][i] = ratio

    return overlap_matrix, overlap_ratio_matrix


def _mean_profile(profiles):
    if not profiles:
        return dict(ROLE_PROFILES["other"])
    keys = ROLE_PROFILES["other"].keys()
    return {key: sum(profile[key] for profile in profiles) / len(profiles) for key in keys}


def _apply_row_effect_modifiers(profile, effects):
    kinds = {_effect_kind(effect.get("effectId")) for effect in effects if not effect.get("bypassed")}
    modified = dict(profile)

    if "compressor" in kinds:
        modified["st_rms_mean"] = _clamp(modified["st_rms_mean"] + 0.10)
        modified["st_rms_p95"] = _clamp(modified["st_rms_p95"] + 0.08)
        modified["lra_est"] = max(2.0, modified["lra_est"] - 1.8)
    if "limiter" in kinds:
        modified["short_lufs_p95"] += 2.0
        modified["clip_ratio"] = _clamp(modified["clip_ratio"] + 0.05)
        modified["true_peak_dbfs"] = min(-0.6, modified["true_peak_dbfs"] + 1.5)
    if "clipper" in kinds:
        modified["clip_ratio"] = _clamp(modified["clip_ratio"] + 0.07)
        modified["spectral_flatness"] = _clamp(modified["spectral_flatness"] + 0.06)
    if "reverb" in kinds:
        modified["side_ratio"] = _clamp(modified["side_ratio"] + 0.18)
        modified["phase_corr"] = max(-1.0, modified["phase_corr"] - 0.18)
    if "delay" in kinds:
        modified["side_ratio"] = _clamp(modified["side_ratio"] + 0.10)
        modified["spectral_flux"] = _clamp(modified["spectral_flux"] + 0.04)
    if "deesser" in kinds:
        modified["sibilance"] = max(0.0, modified["sibilance"] - 0.8)
    if "distortion" in kinds:
        modified["noise_floor_dbfs"] = min(-36.0, modified["noise_floor_dbfs"] + 8.0)
        modified["spectral_flatness"] = _clamp(modified["spectral_flatness"] + 0.10)
    return modified


def _row_entry(row, row_state, row_tracks, effects):
    if not row_tracks:
        return {
            "row": row,
            "hasAudio": False,
            "mix": {
                "gain_0to3": _safe_float(row_state.get("gain"), UNITY_GAIN),
                "pan_0to1": _safe_float(row_state.get("pan"), CENTER_PAN),
            },
            "effects": [_effect_entry(effect) for effect in effects],
            "features": {
                "approx_rms": 0.0,
                "approx_crest": 0.0,
            },
            "audio_stats": {},
            "role_probs": {"other": 1.0},
        }

    inferred_roles = [_infer_role(track) for track in row_tracks]
    dominant_role = Counter(inferred_roles).most_common(1)[0][0]
    profiles = [dict(ROLE_PROFILES.get(role, ROLE_PROFILES["other"])) for role in inferred_roles]
    merged = _mean_profile(profiles)
    merged = _apply_row_effect_modifiers(merged, effects)

    density = _clamp(len(row_tracks) / 4.0)
    gain_bias = (_safe_float(row_state.get("gain"), UNITY_GAIN) - UNITY_GAIN) / UNITY_GAIN
    merged["approx_rms"] = _clamp(merged["approx_rms"] + 0.10 * density + 0.12 * gain_bias, 0.02, 0.98)
    merged["st_rms_mean"] = _clamp(merged["st_rms_mean"] + 0.08 * density + 0.10 * gain_bias)
    merged["st_rms_p95"] = _clamp(max(merged["st_rms_mean"] + 0.08, merged["st_rms_p95"]))
    merged["st_rms_std"] = _clamp(merged["st_rms_std"] + 0.03 * density)
    merged["approx_crest"] = max(2.0, merged["approx_crest"] - (1.6 * max(0.0, gain_bias)))
    merged["integrated_lufs_est"] = max(-36.0, merged["integrated_lufs_est"] + (8.0 * gain_bias))
    merged["short_lufs_mean"] = max(-34.0, merged["short_lufs_mean"] + (8.0 * gain_bias))
    merged["short_lufs_p95"] = max(-28.0, merged["short_lufs_p95"] + (8.0 * gain_bias))
    merged["true_peak_dbfs"] = min(-0.3, merged["true_peak_dbfs"] + (3.0 * gain_bias))
    merged["side_ratio"] = _clamp(merged["side_ratio"] + abs(_safe_float(row_state.get("pan"), CENTER_PAN) - CENTER_PAN) * 0.5)
    merged["stereo_imbalance"] = _clamp(abs(_safe_float(row_state.get("pan"), CENTER_PAN) - CENTER_PAN) * 2.0)

    role_probs = _role_probs(dominant_role)
    return {
        "row": row,
        "hasAudio": True,
        "mix": {
            "gain_0to3": _safe_float(row_state.get("gain"), UNITY_GAIN),
            "pan_0to1": _safe_float(row_state.get("pan"), CENTER_PAN),
        },
        "effects": [_effect_entry(effect) for effect in effects],
        "features": {
            "approx_rms": merged["approx_rms"],
            "approx_crest": merged["approx_crest"],
        },
        "audio_stats": {
            "centroid_hz": merged["centroid_hz"],
            "zcr": merged["zcr"],
            "sibilance": merged["sibilance"],
            "bassiness": merged["bassiness"],
            "hf_rms": merged["hf_rms"],
            "st_rms_mean": merged["st_rms_mean"],
            "st_rms_p95": merged["st_rms_p95"],
            "st_rms_std": merged["st_rms_std"],
            "transient_density": merged["transient_density"],
            "true_peak_dbfs": merged["true_peak_dbfs"],
            "integrated_lufs_est": merged["integrated_lufs_est"],
            "short_lufs_mean": merged["short_lufs_mean"],
            "short_lufs_p95": merged["short_lufs_p95"],
            "lra_est": merged["lra_est"],
            "clip_ratio": merged["clip_ratio"],
            "spectral_flatness": merged["spectral_flatness"],
            "spectral_rolloff_hz": merged["spectral_rolloff_hz"],
            "spectral_slope": merged["spectral_slope"],
            "spectral_flux": merged["spectral_flux"],
            "phase_corr": merged["phase_corr"],
            "side_ratio": merged["side_ratio"],
            "stereo_imbalance": merged["stereo_imbalance"],
            "silence_ratio": merged["silence_ratio"],
            "onset_rate_hz": merged["onset_rate_hz"],
            "noise_floor_dbfs": merged["noise_floor_dbfs"],
            "spectral_bandwidth_hz": merged["spectral_bandwidth_hz"],
            "low": merged["low"],
            "lowmid": merged["lowmid"],
            "mid": merged["mid"],
            "high": merged["high"],
        },
        "role_probs": role_probs,
    }


def _effect_entry(effect):
    params = effect.get("params") or {}
    return {
        "name": str(effect.get("effectId") or ""),
        "bypassed": bool(effect.get("bypassed")),
        "params": [{"name": str(name), "value": value} for name, value in params.items()],
    }


def _build_pre_snapshot(project_json, audio_root):
    count = _row_count(project_json)
    row_states = _normalize_row_states(project_json, count)
    row_effects = _normalize_effect_snapshot(project_json.get("rowEffects"), count)
    master = _normalize_master_effects(project_json)
    tracks = [track for track in (project_json.get("tracks") or []) if isinstance(track, dict)]
    row_tracks = defaultdict(list)
    for track in tracks:
        row_index = track.get("rowIndex")
        if isinstance(row_index, int) and row_index >= 0:
            row_tracks[row_index].append(track)

    row_intervals = _extract_track_intervals_ms(tracks, audio_root)
    overlap_matrix, overlap_ratio_matrix = _overlap_matrices(row_intervals, count)

    rows = []
    for row in range(count):
        rows.append(_row_entry(row, row_states[row], row_tracks.get(row, []), row_effects.get(row, [])))

    return {
        "tempo_bpm": _safe_float(project_json.get("tempoBpm"), 120.0),
        "project_state": {
            "bpm": _safe_float(project_json.get("tempoBpm"), 120.0),
            "max_rows": count,
            "rows": rows,
            "overlap_matrix": overlap_matrix,
            "overlap_ratio_matrix": overlap_ratio_matrix,
        },
        "master": {
            "gain": master["gain"],
            "pan": master["pan"],
            "effects": [_effect_entry(effect) for effect in master["effects"]],
        },
    }


def _kind_features(kind):
    features = {}
    for candidate in CANONICAL_KINDS:
        features[f"kind_{candidate}"] = 1 if candidate == kind else 0
    return features


def _positive_row_actions(row, row_state, effects):
    actions = []
    gain = _safe_float(row_state.get("gain"), UNITY_GAIN)
    pan = _safe_float(row_state.get("pan"), CENTER_PAN)

    if abs(gain - UNITY_GAIN) >= 0.08:
        actions.append(
            {
                "type": "set_row_gain",
                "row": row,
                "kind": "gain" if abs(gain - UNITY_GAIN) >= 0.16 else "balance",
                "magnitude": max(0.05, abs(gain - UNITY_GAIN)),
            }
        )
    if abs(pan - CENTER_PAN) >= 0.04:
        actions.append(
            {
                "type": "set_row_pan",
                "row": row,
                "kind": "pan",
                "magnitude": max(0.05, abs(pan - CENTER_PAN)),
            }
        )

    for effect in effects:
        if effect.get("bypassed"):
            continue
        effect_id = str(effect.get("effectId") or "").strip()
        if not effect_id:
            continue
        kind = _effect_kind(effect_id)
        actions.append(
            {
                "type": "ensure_effect",
                "row": row,
                "kind": kind,
                "magnitude": 0.35,
            }
        )
        for param_name, param_value in _salient_params(effect.get("params") or {}):
            magnitude = _estimate_param_magnitude(param_name, param_value)
            if magnitude < 0.05:
                continue
            actions.append(
                {
                    "type": "adjust_effect_param_by_name",
                    "row": row,
                    "kind": kind,
                    "magnitude": magnitude,
                }
            )
    return actions


def _positive_master_actions(master_state):
    actions = []
    gain = _safe_float(master_state.get("gain"), UNITY_GAIN)
    pan = _safe_float(master_state.get("pan"), CENTER_PAN)
    if abs(gain - UNITY_GAIN) >= 0.08:
        actions.append(
            {
                "type": "set_master_gain",
                "row": -1,
                "kind": "gain" if abs(gain - UNITY_GAIN) >= 0.16 else "balance",
                "magnitude": max(0.05, abs(gain - UNITY_GAIN)),
            }
        )
    if abs(pan - CENTER_PAN) >= 0.04:
        actions.append(
            {
                "type": "set_master_pan",
                "row": -1,
                "kind": "pan",
                "magnitude": max(0.05, abs(pan - CENTER_PAN)),
            }
        )

    for effect in master_state.get("effects", []):
        if effect.get("bypassed"):
            continue
        effect_id = str(effect.get("effectId") or "").strip()
        if not effect_id:
            continue
        kind = _effect_kind(effect_id)
        actions.append(
            {
                "type": "ensure_master_effect",
                "row": -1,
                "kind": kind,
                "magnitude": 0.35,
            }
        )
        for param_name, param_value in _salient_params(effect.get("params") or {}):
            magnitude = _estimate_param_magnitude(param_name, param_value)
            if magnitude < 0.05:
                continue
            actions.append(
                {
                    "type": "adjust_master_effect_param_by_name",
                    "row": -1,
                    "kind": kind,
                    "magnitude": magnitude,
                }
            )
    return actions


def _negative_row_actions(row, row_state, effects):
    actions = []
    gain = _safe_float(row_state.get("gain"), UNITY_GAIN)
    pan = _safe_float(row_state.get("pan"), CENTER_PAN)
    active_kinds = {_effect_kind(effect.get("effectId")) for effect in effects if not effect.get("bypassed")}

    if abs(gain - UNITY_GAIN) < 0.08:
        actions.append({"type": "set_row_gain", "row": row, "kind": "gain", "magnitude": 0.18})
    if abs(pan - CENTER_PAN) < 0.04:
        actions.append({"type": "set_row_pan", "row": row, "kind": "pan", "magnitude": 0.16})

    for kind in NEGATIVE_ROW_EFFECT_KINDS:
        if kind in active_kinds:
            continue
        actions.append({"type": "ensure_effect", "row": row, "kind": kind, "magnitude": 0.22})
    return actions


def _negative_master_actions(master_state):
    actions = []
    gain = _safe_float(master_state.get("gain"), UNITY_GAIN)
    pan = _safe_float(master_state.get("pan"), CENTER_PAN)
    active_kinds = {_effect_kind(effect.get("effectId")) for effect in master_state.get("effects", []) if not effect.get("bypassed")}

    if abs(gain - UNITY_GAIN) < 0.08:
        actions.append({"type": "set_master_gain", "row": -1, "kind": "gain", "magnitude": 0.18})
    if abs(pan - CENTER_PAN) < 0.04:
        actions.append({"type": "set_master_pan", "row": -1, "kind": "pan", "magnitude": 0.16})

    for kind in NEGATIVE_MASTER_EFFECT_KINDS:
        if kind in active_kinds:
            continue
        actions.append({"type": "ensure_master_effect", "row": -1, "kind": kind, "magnitude": 0.22})
    return actions


def _salient_params(params):
    if not isinstance(params, dict) or not params:
        return []
    picked = []
    for name, value in params.items():
        text = str(name).lower()
        if any(token in text for token in SALIENT_PARAM_TOKENS):
            picked.append((str(name), value))
    if picked:
        return picked[:4]
    return [(str(name), value) for name, value in list(params.items())[:2]]


def _estimate_param_magnitude(param_name, raw_value):
    value = _safe_float(raw_value)
    text = str(param_name or "").lower()
    abs_value = abs(value)

    if "frequency" in text or text.endswith("hz"):
        safe_hz = max(20.0, abs_value)
        return _clamp(math.log10(safe_hz / 20.0) / 3.0)
    if text == "q" or text.endswith(" q") or " q " in text:
        return _clamp(abs_value / 10.0)
    if "ratio" in text:
        return _clamp(abs_value / 20.0)
    if "attack" in text or "release" in text or "time" in text:
        return _clamp(math.log10(abs_value + 1.0) / 3.0)
    if "threshold" in text or "ceiling" in text or "gain" in text or "makeup" in text:
        return _clamp(abs_value / 24.0)
    if "mix" in text or "feedback" in text or "drive" in text or "amount" in text or "room" in text:
        if 0.0 <= value <= 1.0:
            return _clamp(value)
        return _clamp(abs_value / 100.0)
    return _clamp(abs_value / 10.0)


def _row_scope_features(is_master):
    return {
        "goal_intensity": 0.78,
        "strict_execute": 1,
        "scope_auto": 0,
        "scope_row": 0 if is_master else 1,
        "scope_master": 1 if is_master else 0,
    }


def _dataset_row(project_id, session_id, event_index, action, project_features, count_features, label_apply):
    action_type = action["type"]
    is_master = 1 if "master" in action_type else 0
    row = {
        "project_id": project_id,
        "session_id": session_id,
        "event_index": event_index,
        "action_type": action_type,
        "action_row_index": action["row"],
        "is_master_action": is_master,
        "ai_action_magnitude": float(action["magnitude"]),
        "label_apply": int(label_apply),
        "label_magnitude_scale": 1.0 if label_apply else 0.0,
        "label_source": "project_final_state",
        **_row_scope_features(is_master=bool(is_master)),
        **_kind_features(action["kind"]),
        **project_features,
        **count_features,
        **_action_type_features(action_type),
    }
    for feature in FEATURE_COLUMNS:
        row.setdefault(feature, 0.0)
    return row


def _project_rows(source_type, source_path, project_json, project_root):
    project_id = str(project_json.get("projectId") or project_json.get("project_id") or project_root.name).strip()
    if not project_id:
        project_id = project_root.name
    session_id = f"project_bootstrap_{project_id}"

    count = _row_count(project_json)
    row_states = _normalize_row_states(project_json, count)
    row_effects = _normalize_effect_snapshot(project_json.get("rowEffects"), count)
    master_state = _normalize_master_effects(project_json)
    tracks = [track for track in (project_json.get("tracks") or []) if isinstance(track, dict)]
    row_has_audio = {row: False for row in range(count)}
    for track in tracks:
        row_index = track.get("rowIndex")
        if isinstance(row_index, int) and 0 <= row_index < count:
            row_has_audio[row_index] = True

    pre_snapshot = _build_pre_snapshot(project_json, project_root)
    project_features = _project_stats(pre_snapshot)

    positive_actions = []
    negative_actions = []
    for row in range(count):
        positive_actions.extend(_positive_row_actions(row, row_states[row], row_effects.get(row, [])))
        if row_has_audio.get(row):
            negative_actions.extend(_negative_row_actions(row, row_states[row], row_effects.get(row, [])))
    positive_actions.extend(_positive_master_actions(master_state))
    negative_actions.extend(_negative_master_actions(master_state))

    count_features = _count_action_groups([{"type": action["type"]} for action in positive_actions])

    rows = []
    event_index = 0
    for action in positive_actions:
        row = _dataset_row(project_id, session_id, event_index, action, project_features, count_features, True)
        row["project_name"] = str(project_json.get("name") or "").strip()
        row["source_path"] = str(source_path)
        row["source_type"] = source_type
        rows.append(row)
        event_index += 1

    for action in negative_actions:
        row = _dataset_row(project_id, session_id, event_index, action, project_features, count_features, False)
        row["project_name"] = str(project_json.get("name") or "").strip()
        row["source_path"] = str(source_path)
        row["source_type"] = source_type
        rows.append(row)
        event_index += 1

    return rows


def _load_source(source_type, path):
    if source_type == "project_dir":
        project_root = Path(path)
        project_json_path = project_root / "project.json"
        with open(project_json_path, "r", encoding="utf-8") as handle:
            project_json = json.load(handle)
        return project_json, project_root, None

    temp_dir = tempfile.mkdtemp(prefix="mixroom_project_bootstrap_")
    with zipfile.ZipFile(path, "r") as archive:
        archive.extractall(temp_dir)
    project_root = Path(temp_dir)
    with open(project_root / "project.json", "r", encoding="utf-8") as handle:
        project_json = json.load(handle)
    return project_json, project_root, temp_dir


def main():
    args = parse_args()
    if len(FEATURE_COLUMNS) != EXPECTED_FEATURE_COUNT:
        raise SystemExit(
            f"Feature contract mismatch: expected {EXPECTED_FEATURE_COUNT}, got {len(FEATURE_COLUMNS)}"
        )

    sources = _discover_sources(args.projects_root)
    if not sources:
        raise SystemExit(f"No Mixroom project sources found under: {args.projects_root}")

    dataset_rows = []
    project_count = 0

    for source_type, source_path in sources:
        cleanup_dir = None
        try:
            project_json, project_root, cleanup_dir = _load_source(source_type, source_path)
            dataset_rows.extend(_project_rows(source_type, source_path, project_json, project_root))
            project_count += 1
        except Exception as exc:
            print(f"[warn] failed to process {source_path}: {exc}")
        finally:
            if cleanup_dir:
                shutil.rmtree(cleanup_dir, ignore_errors=True)

    if not dataset_rows:
        raise SystemExit("No usable rows were built from project sources.")

    frame = pd.DataFrame(dataset_rows)
    for feature in FEATURE_COLUMNS:
        if feature not in frame.columns:
            frame[feature] = 0.0

    out_path = Path(args.out_csv)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(out_path, index=False)

    positive_count = int(frame["label_apply"].sum())
    negative_count = int(len(frame) - positive_count)
    print(f"Wrote {len(frame)} rows to {out_path}")
    print(f"Projects processed: {project_count}")
    print(f"Positive rows: {positive_count}")
    print(f"Negative rows: {negative_count}")
    print(f"Unique projects: {frame['project_id'].astype(str).nunique()}")


if __name__ == "__main__":
    main()
