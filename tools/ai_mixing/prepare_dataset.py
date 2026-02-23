#!/usr/bin/env python3
import argparse
import glob
import json
import os
from statistics import median

import pandas as pd

FEATURE_COLUMNS = [
    "goal_intensity",
    "strict_execute",
    "project_bpm_norm",
    "rows_with_audio_ratio",
    "median_rms",
    "count_row_gain_ops_norm",
    "count_row_pan_ops_norm",
    "count_fx_ops_norm",
    "count_master_ops_norm",
    "scope_auto",
    "scope_row",
    "scope_master",
    "kind_balance",
    "kind_gain",
    "kind_pan",
    "kind_eq",
    "kind_compressor",
    "kind_limiter",
    "kind_reverb",
    "kind_delay",
    "kind_deesser",
    "kind_distortion",
    "median_crest_norm",
    "rms_iqr",
    "median_centroid_norm",
    "median_zcr",
    "median_sibilance_norm",
    "median_bassiness_norm",
    "median_hf_rms_norm",
    "median_st_rms_mean",
    "median_st_rms_p95",
    "median_st_rms_std",
    "median_transient_density",
    "overlap_density",
    "masking_pair_ratio",
    "centroid_collision_ratio",
    "avg_overlap_centroid_gap_norm",
    "overlap_rms_pressure",
    "role_overlap_ratio",
    "st_dynamic_headroom",
    "median_true_peak_norm",
    "median_integrated_lufs_norm",
    "median_short_lufs_mean_norm",
    "median_short_lufs_p95_norm",
    "median_lra_norm",
    "median_clip_ratio",
    "median_spectral_flatness",
    "median_spectral_rolloff_norm",
    "median_spectral_slope_norm",
    "median_spectral_flux",
    "median_phase_corr_norm",
    "median_side_ratio_norm",
    "median_stereo_imbalance",
    "median_silence_ratio",
    "median_onset_rate_norm",
    "median_noise_floor_norm",
    "median_spectral_bandwidth_norm",
    "overlap_low_collision",
    "overlap_lowmid_collision",
    "overlap_mid_collision",
    "overlap_high_collision",
    "ai_action_magnitude",
    "is_master_action",
    "action_set_row_gain",
    "action_set_row_pan",
    "action_set_master_gain",
    "action_set_master_pan",
    "action_adjust_effect_param_by_name",
    "action_adjust_master_effect_param_by_name",
    "action_ensure_effect",
    "action_ensure_master_effect",
    "action_delete_effect",
    "action_delete_master_effect",
    "action_hard_reset_row_fx",
    "action_hard_reset_master_fx",
    "action_other",
]
EXPECTED_FEATURE_COUNT = 76

CANONICAL_KINDS = (
    "balance",
    "gain",
    "pan",
    "eq",
    "compressor",
    "limiter",
    "reverb",
    "delay",
    "deesser",
    "distortion",
)


def parse_args():
    p = argparse.ArgumentParser(description="Build action-level dataset from producer session JSON files.")
    p.add_argument("--sessions-dir", required=True, help="Directory containing exported session .json files")
    p.add_argument("--out-csv", required=True, help="Output CSV path")
    return p.parse_args()


def _safe_get(d, *keys, default=None):
    cur = d
    for k in keys:
        if not isinstance(cur, dict) or k not in cur:
            return default
        cur = cur[k]
    return cur


def _to_float(v, default=0.0):
    return float(v) if isinstance(v, (int, float)) else default


def _quantile(sorted_vals, q):
    if not sorted_vals:
        return 0.0
    if len(sorted_vals) == 1:
        return float(sorted_vals[0])
    qq = max(0.0, min(1.0, float(q)))
    pos = qq * (len(sorted_vals) - 1)
    lo = int(pos)
    hi = min(len(sorted_vals) - 1, lo + 1)
    if lo == hi:
        return float(sorted_vals[lo])
    t = pos - lo
    return float(sorted_vals[lo] * (1.0 - t) + sorted_vals[hi] * t)


def _norm_dbfs(db):
    return max(0.0, min(1.0, (_to_float(db, -120.0) + 80.0) / 80.0))


def _norm_lufs(db):
    return max(0.0, min(1.0, (_to_float(db, -120.0) + 80.0) / 80.0))


def _norm_slope(s):
    return max(0.0, min(1.0, (_to_float(s) + 2.0) / 4.0))


def _lookup_row_by_index(pre_snapshot, row_idx):
    ps = _safe_get(pre_snapshot, "project_state", default={}) or {}
    rows = ps.get("rows", [])
    if not isinstance(rows, list):
        return None
    for r in rows:
        if isinstance(r, dict) and int(_to_float(r.get("row"), -1)) == int(row_idx):
            return r
    return None


def _lookup_effect_in_row(row_state, effect_contains):
    if not isinstance(row_state, dict):
        return None
    effects = row_state.get("effects", [])
    if not isinstance(effects, list):
        return None
    needle = str(effect_contains or "").lower()
    for fx in effects:
        if not isinstance(fx, dict):
            continue
        name = str(fx.get("name") or "").lower()
        if needle and needle in name:
            return fx
    return None


def _lookup_master_effect(pre_snapshot, effect_contains):
    master = pre_snapshot.get("master", {})
    if not isinstance(master, dict):
        return None
    effects = master.get("effects", [])
    if not isinstance(effects, list):
        return None
    needle = str(effect_contains or "").lower()
    for fx in effects:
        if not isinstance(fx, dict):
            continue
        name = str(fx.get("name") or "").lower()
        if needle and needle in name:
            return fx
    return None


def _lookup_param_value(effect_state, action_data):
    if not isinstance(effect_state, dict):
        return None
    params = effect_state.get("params", effect_state.get("parameters"))
    if not isinstance(params, list):
        return None

    exact = action_data.get("param_name")
    exact_l = str(exact).lower() if exact is not None else None
    contains_any = action_data.get("param_name_contains_any")
    if not isinstance(contains_any, list):
        contains_any = []
    contains_any = [str(x).lower() for x in contains_any]

    for p in params:
        if not isinstance(p, dict):
            continue
        name = str(p.get("name") or "").lower()
        if exact_l and name == exact_l:
            return _to_float(p.get("value"), None)
        if contains_any and any(token in name for token in contains_any):
            return _to_float(p.get("value"), None)
    return None


def _extract_action_magnitude(action, pre_snapshot):
    data = action.get("data", {}) or {}

    if isinstance(data.get("delta"), (int, float)):
        return abs(float(data["delta"]))
    if isinstance(data.get("delta_norm"), (int, float)):
        return abs(float(data["delta_norm"]))

    mode = str(data.get("mode") or "delta").lower()
    if mode == "set":
        t = str(action.get("type") or "")
        if t == "set_row_gain":
            row = data.get("row")
            if isinstance(row, (int, float)):
                r = _lookup_row_by_index(pre_snapshot, int(row))
                old_v = _safe_get(r or {}, "mix", "gain_0to3", default=None)
                new_v = data.get("value")
                if isinstance(old_v, (int, float)) and isinstance(new_v, (int, float)):
                    return abs(float(new_v) - float(old_v))
        if t == "set_row_pan":
            row = data.get("row")
            if isinstance(row, (int, float)):
                r = _lookup_row_by_index(pre_snapshot, int(row))
                old_v = _safe_get(r or {}, "mix", "pan_0to1", default=None)
                new_v = data.get("value")
                if isinstance(old_v, (int, float)) and isinstance(new_v, (int, float)):
                    return abs(float(new_v) - float(old_v))
        if t == "set_master_gain":
            old_v = _safe_get(pre_snapshot, "master", "gain", default=None)
            new_v = data.get("value")
            if isinstance(old_v, (int, float)) and isinstance(new_v, (int, float)):
                return abs(float(new_v) - float(old_v))
        if t == "set_master_pan":
            old_v = _safe_get(pre_snapshot, "master", "pan", default=None)
            new_v = data.get("value")
            if isinstance(old_v, (int, float)) and isinstance(new_v, (int, float)):
                return abs(float(new_v) - float(old_v))
        if t == "adjust_effect_param_by_name":
            row = data.get("row")
            if isinstance(row, (int, float)):
                r = _lookup_row_by_index(pre_snapshot, int(row))
                fx = _lookup_effect_in_row(r, data.get("effect_name_contains"))
                old_v = _lookup_param_value(fx, data)
                new_v = data.get("value")
                if isinstance(old_v, (int, float)) and isinstance(new_v, (int, float)):
                    return abs(float(new_v) - float(old_v))
        if t == "adjust_master_effect_param_by_name":
            fx = _lookup_master_effect(pre_snapshot, data.get("effect_name_contains"))
            old_v = _lookup_param_value(fx, data)
            new_v = data.get("value")
            if isinstance(old_v, (int, float)) and isinstance(new_v, (int, float)):
                return abs(float(new_v) - float(old_v))

    # Fallback when exact anchor cannot be reconstructed from snapshot.
    return 1.0


def _is_master_action(action_type):
    t = str(action_type or "")
    return "master" in t


def _action_type_features(action_type):
    t = str(action_type or "")
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
    return {
        "action_set_row_gain": 1 if t == "set_row_gain" else 0,
        "action_set_row_pan": 1 if t == "set_row_pan" else 0,
        "action_set_master_gain": 1 if t == "set_master_gain" else 0,
        "action_set_master_pan": 1 if t == "set_master_pan" else 0,
        "action_adjust_effect_param_by_name": 1 if t == "adjust_effect_param_by_name" else 0,
        "action_adjust_master_effect_param_by_name": 1 if t == "adjust_master_effect_param_by_name" else 0,
        "action_ensure_effect": 1 if t == "ensure_effect" else 0,
        "action_ensure_master_effect": 1 if t == "ensure_master_effect" else 0,
        "action_delete_effect": 1 if t == "delete_effect" else 0,
        "action_delete_master_effect": 1 if t == "delete_master_effect" else 0,
        "action_hard_reset_row_fx": 1 if t == "hard_reset_row_fx" else 0,
        "action_hard_reset_master_fx": 1 if t == "hard_reset_master_fx" else 0,
        "action_other": 0 if t in known else 1,
    }


def _normalize_kind(kind):
    k = str(kind or "").strip().lower()
    aliases = {
        "volume": "gain",
        "levels": "gain",
        "balance": "balance",
        "stereo": "pan",
        "tone": "eq",
        "compress": "compressor",
        "compression": "compressor",
        "de-esser": "deesser",
        "de_esser": "deesser",
        "saturation": "distortion",
    }
    k = aliases.get(k, k)
    if k in CANONICAL_KINDS:
        return k
    return "balance"


def _action_row_index(action):
    data = action.get("data", {}) or {}
    row = data.get("row")
    if isinstance(row, int):
        return row
    if isinstance(row, float):
        return int(row)
    return -1


def _project_stats(pre_snapshot):
    ps = _safe_get(pre_snapshot, "project_state", default={}) or {}
    rows = ps.get("rows", []) if isinstance(ps.get("rows"), list) else []
    overlap_matrix = ps.get("overlap_matrix", [])
    overlap_ratio_matrix = ps.get("overlap_ratio_matrix", [])
    if not isinstance(overlap_matrix, list):
        overlap_matrix = []
    if not isinstance(overlap_ratio_matrix, list):
        overlap_ratio_matrix = []

    tempo_bpm = pre_snapshot.get("tempo_bpm")
    if not isinstance(tempo_bpm, (int, float)):
        tempo_bpm = ps.get("bpm")
    if not isinstance(tempo_bpm, (int, float)):
        tempo_bpm = 120.0

    rows_with_audio = 0
    rms_values = []
    crest_norm_values = []
    centroid_norm_values = []
    zcr_values = []
    sibilance_norm_values = []
    bassiness_norm_values = []
    hf_rms_values = []
    st_rms_mean_values = []
    st_rms_p95_values = []
    st_rms_std_values = []
    transient_density_values = []
    true_peak_norm_values = []
    integrated_lufs_norm_values = []
    short_lufs_mean_norm_values = []
    short_lufs_p95_norm_values = []
    lra_norm_values = []
    clip_ratio_values = []
    spectral_flatness_values = []
    spectral_rolloff_norm_values = []
    spectral_slope_norm_values = []
    spectral_flux_values = []
    phase_corr_norm_values = []
    side_ratio_norm_values = []
    stereo_imbalance_values = []
    silence_ratio_values = []
    onset_rate_norm_values = []
    noise_floor_norm_values = []
    spectral_bandwidth_norm_values = []
    rows_audio = []

    for r in rows:
        if not isinstance(r, dict):
            continue
        if r.get("hasAudio") is True:
            rows_with_audio += 1
            rows_audio.append(r)
        rms = _safe_get(r, "features", "approx_rms", default=None)
        if isinstance(rms, (int, float)):
            rms_values.append(float(rms))
        crest = _safe_get(r, "features", "approx_crest", default=None)
        if isinstance(crest, (int, float)):
            crest_norm_values.append(max(0.0, min(1.0, float(crest) / 20.0)))

        audio_stats = r.get("audio_stats", {})
        if isinstance(audio_stats, dict):
            centroid_norm_values.append(max(0.0, min(1.0, _to_float(audio_stats.get("centroid_hz")) / 8000.0)))
            zcr_values.append(max(0.0, min(1.0, _to_float(audio_stats.get("zcr")))))
            sibilance_norm_values.append(max(0.0, min(1.0, _to_float(audio_stats.get("sibilance")) / 5.0)))
            bassiness_norm_values.append(max(0.0, min(1.0, _to_float(audio_stats.get("bassiness")) / 5.0)))
            hf_rms_values.append(max(0.0, min(1.0, _to_float(audio_stats.get("hf_rms")))))
            st_rms_mean_values.append(max(0.0, min(1.0, _to_float(audio_stats.get("st_rms_mean")))))
            st_rms_p95_values.append(max(0.0, min(1.0, _to_float(audio_stats.get("st_rms_p95")))))
            st_rms_std_values.append(max(0.0, min(1.0, _to_float(audio_stats.get("st_rms_std")))))
            transient_density_values.append(max(0.0, min(1.0, _to_float(audio_stats.get("transient_density")))))
            true_peak_norm_values.append(_norm_dbfs(audio_stats.get("true_peak_dbfs")))
            integrated_lufs_norm_values.append(_norm_lufs(audio_stats.get("integrated_lufs_est")))
            short_lufs_mean_norm_values.append(_norm_lufs(audio_stats.get("short_lufs_mean")))
            short_lufs_p95_norm_values.append(_norm_lufs(audio_stats.get("short_lufs_p95")))
            lra_norm_values.append(max(0.0, min(1.0, _to_float(audio_stats.get("lra_est")) / 40.0)))
            clip_ratio_values.append(max(0.0, min(1.0, _to_float(audio_stats.get("clip_ratio")))))
            spectral_flatness_values.append(max(0.0, min(1.0, _to_float(audio_stats.get("spectral_flatness")))))
            spectral_rolloff_norm_values.append(max(0.0, min(1.0, _to_float(audio_stats.get("spectral_rolloff_hz")) / 8000.0)))
            spectral_slope_norm_values.append(_norm_slope(audio_stats.get("spectral_slope")))
            spectral_flux_values.append(max(0.0, min(1.0, _to_float(audio_stats.get("spectral_flux")))))
            phase_corr_norm_values.append(max(0.0, min(1.0, (_to_float(audio_stats.get("phase_corr"), 1.0) + 1.0) / 2.0)))
            side_ratio_norm_values.append(max(0.0, min(1.0, _to_float(audio_stats.get("side_ratio")) / 2.0)))
            stereo_imbalance_values.append(max(0.0, min(1.0, _to_float(audio_stats.get("stereo_imbalance")))))
            silence_ratio_values.append(max(0.0, min(1.0, _to_float(audio_stats.get("silence_ratio")))))
            onset_rate_norm_values.append(max(0.0, min(1.0, _to_float(audio_stats.get("onset_rate_hz")) / 20.0)))
            noise_floor_norm_values.append(_norm_dbfs(audio_stats.get("noise_floor_dbfs")))
            spectral_bandwidth_norm_values.append(max(0.0, min(1.0, _to_float(audio_stats.get("spectral_bandwidth_hz")) / 8000.0)))

    med_rms = float(median(rms_values)) if rms_values else 0.0
    rms_sorted = sorted(rms_values)
    rms_iqr = _quantile(rms_sorted, 0.75) - _quantile(rms_sorted, 0.25) if rms_sorted else 0.0
    median_crest_norm = _quantile(sorted(crest_norm_values), 0.5)
    median_centroid_norm = _quantile(sorted(centroid_norm_values), 0.5)
    median_zcr = _quantile(sorted(zcr_values), 0.5)
    median_sibilance_norm = _quantile(sorted(sibilance_norm_values), 0.5)
    median_bassiness_norm = _quantile(sorted(bassiness_norm_values), 0.5)
    median_hf_rms_norm = _quantile(sorted(hf_rms_values), 0.5)
    median_st_rms_mean = _quantile(sorted(st_rms_mean_values), 0.5)
    median_st_rms_p95 = _quantile(sorted(st_rms_p95_values), 0.5)
    median_st_rms_std = _quantile(sorted(st_rms_std_values), 0.5)
    median_transient_density = _quantile(sorted(transient_density_values), 0.5)
    median_true_peak_norm = _quantile(sorted(true_peak_norm_values), 0.5)
    median_integrated_lufs_norm = _quantile(sorted(integrated_lufs_norm_values), 0.5)
    median_short_lufs_mean_norm = _quantile(sorted(short_lufs_mean_norm_values), 0.5)
    median_short_lufs_p95_norm = _quantile(sorted(short_lufs_p95_norm_values), 0.5)
    median_lra_norm = _quantile(sorted(lra_norm_values), 0.5)
    median_clip_ratio = _quantile(sorted(clip_ratio_values), 0.5)
    median_spectral_flatness = _quantile(sorted(spectral_flatness_values), 0.5)
    median_spectral_rolloff_norm = _quantile(sorted(spectral_rolloff_norm_values), 0.5)
    median_spectral_slope_norm = _quantile(sorted(spectral_slope_norm_values), 0.5)
    median_spectral_flux = _quantile(sorted(spectral_flux_values), 0.5)
    median_phase_corr_norm = _quantile(sorted(phase_corr_norm_values), 0.5)
    median_side_ratio_norm = _quantile(sorted(side_ratio_norm_values), 0.5)
    median_stereo_imbalance = _quantile(sorted(stereo_imbalance_values), 0.5)
    median_silence_ratio = _quantile(sorted(silence_ratio_values), 0.5)
    median_onset_rate_norm = _quantile(sorted(onset_rate_norm_values), 0.5)
    median_noise_floor_norm = _quantile(sorted(noise_floor_norm_values), 0.5)
    median_spectral_bandwidth_norm = _quantile(sorted(spectral_bandwidth_norm_values), 0.5)

    max_rows = int(ps.get("max_rows") or 0)
    if max_rows <= 0:
        max_rows = max(1, len(rows))
    rows_ratio = max(0.0, min(1.0, rows_with_audio / float(max_rows)))

    # Overlap + masking proxies among rows that actually contain audio.
    pair_count = len(rows_audio) * (len(rows_audio) - 1) / 2.0
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

    def top_role(row):
        probs = row.get("role_probs", {})
        if not isinstance(probs, dict) or not probs:
            return "other"
        best_key = "other"
        best_val = float("-inf")
        for k, v in probs.items():
            vv = _to_float(v)
            if vv > best_val:
                best_val = vv
                best_key = str(k).lower()
        return best_key if best_key else "other"

    def band_share(row, key):
        s = row.get("audio_stats", {})
        if not isinstance(s, dict):
            return 0.0
        low = max(0.0, _to_float(s.get("low")))
        lowmid = max(0.0, _to_float(s.get("lowmid")))
        mid = max(0.0, _to_float(s.get("mid")))
        high = max(0.0, _to_float(s.get("high")))
        total = max(1e-9, low + lowmid + mid + high)
        return max(0.0, min(1.0, max(0.0, _to_float(s.get(key))) / total))

    def band_collision(a, b, key):
        sa = band_share(a, key)
        sb = band_share(b, key)
        similarity = max(0.0, min(1.0, 1.0 - abs(sa - sb)))
        both_present = max(0.0, min(1.0, 2.0 * min(sa, sb)))
        return max(0.0, min(1.0, similarity * both_present))

    def overlap_strength(ri, rj):
        ratio = 0.0
        if 0 <= ri < len(overlap_ratio_matrix) and isinstance(overlap_ratio_matrix[ri], list):
            if 0 <= rj < len(overlap_ratio_matrix[ri]):
                ratio = max(ratio, max(0.0, min(1.0, _to_float(overlap_ratio_matrix[ri][rj]))))
        if 0 <= rj < len(overlap_ratio_matrix) and isinstance(overlap_ratio_matrix[rj], list):
            if 0 <= ri < len(overlap_ratio_matrix[rj]):
                ratio = max(ratio, max(0.0, min(1.0, _to_float(overlap_ratio_matrix[rj][ri]))))
        if ratio > 0.0:
            return ratio

        overlaps = False
        if 0 <= ri < len(overlap_matrix) and isinstance(overlap_matrix[ri], list):
            if 0 <= rj < len(overlap_matrix[ri]):
                overlaps = overlaps or (int(_to_float(overlap_matrix[ri][rj])) == 1)
        if 0 <= rj < len(overlap_matrix) and isinstance(overlap_matrix[rj], list):
            if 0 <= ri < len(overlap_matrix[rj]):
                overlaps = overlaps or (int(_to_float(overlap_matrix[rj][ri])) == 1)
        return 1.0 if overlaps else 0.0

    for i in range(len(rows_audio)):
        for j in range(i + 1, len(rows_audio)):
            ri = int(_to_float(rows_audio[i].get("row"), i))
            rj = int(_to_float(rows_audio[j].get("row"), j))

            strength = overlap_strength(ri, rj)
            if strength <= 1e-6:
                continue

            overlap_strength_sum += strength

            c_i = _to_float(_safe_get(rows_audio[i], "audio_stats", "centroid_hz"))
            c_j = _to_float(_safe_get(rows_audio[j], "audio_stats", "centroid_hz"))
            gap_norm = max(0.0, min(1.0, abs(c_i - c_j) / 8000.0))
            sum_gap_norm += gap_norm * strength
            if gap_norm < 0.12:
                centroid_collision_strength_sum += strength

            rms_i = max(1e-6, _to_float(_safe_get(rows_audio[i], "features", "approx_rms")))
            rms_j = max(1e-6, _to_float(_safe_get(rows_audio[j], "features", "approx_rms")))
            ratio = max(rms_i, rms_j) / min(rms_i, rms_j)
            rms_pressure = max(0.0, min(1.0, (ratio - 1.0) / 3.0))
            sum_rms_pressure += rms_pressure * strength
            if ratio > 1.4 and gap_norm < 0.20:
                masking_strength_sum += strength

            role_i = top_role(rows_audio[i])
            role_j = top_role(rows_audio[j])
            if role_i != role_j and role_i != "other" and role_j != "other":
                role_overlap_strength_sum += strength

            low_collision_sum += band_collision(rows_audio[i], rows_audio[j], "low") * strength
            lowmid_collision_sum += band_collision(rows_audio[i], rows_audio[j], "lowmid") * strength
            mid_collision_sum += band_collision(rows_audio[i], rows_audio[j], "mid") * strength
            high_collision_sum += band_collision(rows_audio[i], rows_audio[j], "high") * strength

    if overlap_strength_sum > 1e-6:
        overlap_density = max(0.0, min(1.0, overlap_strength_sum / pair_count)) if pair_count > 0 else 0.0
        masking_pair_ratio = max(0.0, min(1.0, masking_strength_sum / overlap_strength_sum))
        centroid_collision_ratio = max(0.0, min(1.0, centroid_collision_strength_sum / overlap_strength_sum))
        avg_overlap_centroid_gap_norm = max(0.0, min(1.0, sum_gap_norm / overlap_strength_sum))
        overlap_rms_pressure = max(0.0, min(1.0, sum_rms_pressure / overlap_strength_sum))
        role_overlap_ratio = max(0.0, min(1.0, role_overlap_strength_sum / overlap_strength_sum))
        overlap_low_collision = max(0.0, min(1.0, low_collision_sum / overlap_strength_sum))
        overlap_lowmid_collision = max(0.0, min(1.0, lowmid_collision_sum / overlap_strength_sum))
        overlap_mid_collision = max(0.0, min(1.0, mid_collision_sum / overlap_strength_sum))
        overlap_high_collision = max(0.0, min(1.0, high_collision_sum / overlap_strength_sum))
    else:
        overlap_density = 0.0
        masking_pair_ratio = 0.0
        centroid_collision_ratio = 0.0
        avg_overlap_centroid_gap_norm = 0.0
        overlap_rms_pressure = 0.0
        role_overlap_ratio = 0.0
        overlap_low_collision = 0.0
        overlap_lowmid_collision = 0.0
        overlap_mid_collision = 0.0
        overlap_high_collision = 0.0

    st_dynamic_headroom = max(0.0, min(1.0, median_st_rms_p95 - median_st_rms_mean))

    return {
        "project_bpm_norm": max(0.0, min(1.0, float(tempo_bpm) / 240.0)),
        "rows_with_audio_ratio": rows_ratio,
        "median_rms": med_rms,
        "median_crest_norm": median_crest_norm,
        "rms_iqr": max(0.0, min(1.0, rms_iqr)),
        "median_centroid_norm": median_centroid_norm,
        "median_zcr": median_zcr,
        "median_sibilance_norm": median_sibilance_norm,
        "median_bassiness_norm": median_bassiness_norm,
        "median_hf_rms_norm": median_hf_rms_norm,
        "median_st_rms_mean": median_st_rms_mean,
        "median_st_rms_p95": median_st_rms_p95,
        "median_st_rms_std": median_st_rms_std,
        "median_transient_density": median_transient_density,
        "median_true_peak_norm": median_true_peak_norm,
        "median_integrated_lufs_norm": median_integrated_lufs_norm,
        "median_short_lufs_mean_norm": median_short_lufs_mean_norm,
        "median_short_lufs_p95_norm": median_short_lufs_p95_norm,
        "median_lra_norm": median_lra_norm,
        "median_clip_ratio": median_clip_ratio,
        "median_spectral_flatness": median_spectral_flatness,
        "median_spectral_rolloff_norm": median_spectral_rolloff_norm,
        "median_spectral_slope_norm": median_spectral_slope_norm,
        "median_spectral_flux": median_spectral_flux,
        "median_phase_corr_norm": median_phase_corr_norm,
        "median_side_ratio_norm": median_side_ratio_norm,
        "median_stereo_imbalance": median_stereo_imbalance,
        "median_silence_ratio": median_silence_ratio,
        "median_onset_rate_norm": median_onset_rate_norm,
        "median_noise_floor_norm": median_noise_floor_norm,
        "median_spectral_bandwidth_norm": median_spectral_bandwidth_norm,
        "overlap_density": overlap_density,
        "masking_pair_ratio": masking_pair_ratio,
        "centroid_collision_ratio": centroid_collision_ratio,
        "avg_overlap_centroid_gap_norm": avg_overlap_centroid_gap_norm,
        "overlap_rms_pressure": overlap_rms_pressure,
        "role_overlap_ratio": role_overlap_ratio,
        "overlap_low_collision": overlap_low_collision,
        "overlap_lowmid_collision": overlap_lowmid_collision,
        "overlap_mid_collision": overlap_mid_collision,
        "overlap_high_collision": overlap_high_collision,
        "st_dynamic_headroom": st_dynamic_headroom,
    }


def _goal_meta_for_action(llm_payload, action):
    mode = str(llm_payload.get("mode") or "propose").lower()
    strict_execute = 1 if mode == "execute" else 0

    llm_actions = llm_payload.get("llm_actions")
    if not isinstance(llm_actions, list):
        llm_actions = _safe_get(llm_payload, "tool_args", "actions", default=[])
    if not isinstance(llm_actions, list):
        llm_actions = []

    action_type = str(action.get("type") or "")
    action_data = action.get("data", {}) if isinstance(action, dict) else {}
    action_row = action_data.get("row")
    action_row = int(action_row) if isinstance(action_row, (int, float)) else None

    candidate_goals = []
    for a in llm_actions:
        g = a.get("goal") if isinstance(a, dict) else None
        if not isinstance(g, dict):
            continue
        target = g.get("target") if isinstance(g.get("target"), dict) else {}
        scope = str(target.get("scope") or "auto").lower()
        goal_row = target.get("row_index")
        goal_row = int(goal_row) if isinstance(goal_row, (int, float)) else None

        if "master" in action_type:
            if scope == "master":
                candidate_goals.append(g)
                continue
        elif action_row is not None and goal_row == action_row:
            candidate_goals.append(g)
            continue
        elif action_row is not None and scope == "row":
            candidate_goals.append(g)
            continue

    if candidate_goals:
        first_goal = candidate_goals[0]
    else:
        first_goal = None
        for a in llm_actions:
            g = a.get("goal") if isinstance(a, dict) else None
            if isinstance(g, dict):
                first_goal = g
                break

    intensity = 0.5
    scope = "auto"
    if isinstance(first_goal, dict):
        if isinstance(first_goal.get("intensity"), (int, float)):
            intensity = float(first_goal["intensity"])
        target = first_goal.get("target") if isinstance(first_goal.get("target"), dict) else {}
        s = str(target.get("scope") or "auto").lower()
        if s in ("auto", "row", "master"):
            scope = s
    first_kind = "balance"
    if isinstance(first_goal, dict):
        intents = first_goal.get("intents")
        if isinstance(intents, list) and intents:
            first_intent = intents[0] if isinstance(intents[0], dict) else {}
            first_kind = _normalize_kind(first_intent.get("kind"))

    out = {
        "strict_execute": strict_execute,
        "goal_intensity": float(max(0.0, min(1.0, intensity))),
        "scope_auto": 1 if scope == "auto" else 0,
        "scope_row": 1 if scope == "row" else 0,
        "scope_master": 1 if scope == "master" else 0,
    }
    for kind in CANONICAL_KINDS:
        out[f"kind_{kind}"] = 1 if first_kind == kind else 0
    return out


def _count_action_groups(resolved_actions):
    row_gain = 0
    row_pan = 0
    fx_ops = 0
    master_ops = 0

    for a in resolved_actions:
        t = str(a.get("type") or "")
        if t == "set_row_gain":
            row_gain += 1
        if t == "set_row_pan":
            row_pan += 1
        if "effect" in t:
            fx_ops += 1
        if "master" in t:
            master_ops += 1

    return {
        "count_row_gain_ops_norm": row_gain / 12.0,
        "count_row_pan_ops_norm": row_pan / 12.0,
        "count_fx_ops_norm": fx_ops / 20.0,
        "count_master_ops_norm": master_ops / 12.0,
    }


def _manual_kind_for_action(action_type):
    mapping = {
        "set_row_gain": "row_gain",
        "set_row_pan": "row_pan",
        "set_master_gain": "master_gain",
        "set_master_pan": "master_pan",
        "adjust_effect_param_by_name": "row_fx_param",
        "adjust_master_effect_param_by_name": "master_fx_param",
    }
    return mapping.get(action_type)


def _tokenize_action_param_hints(action):
    data = action.get("data", {}) if isinstance(action, dict) else {}
    toks = []
    p = data.get("param_name")
    if isinstance(p, str) and p.strip():
        toks.append(p.strip().lower())
    contains_any = data.get("param_name_contains_any")
    if isinstance(contains_any, list):
        for v in contains_any:
            sv = str(v).strip().lower()
            if sv:
                toks.append(sv)
    return toks


def _infer_manual_scale(ai_row, manual_events, start_index, end_index):
    kind = _manual_kind_for_action(ai_row["action_type"])
    if not kind:
        return None

    target_row = ai_row["action_row_index"]
    ai_param_hints = ai_row.get("action_param_hints", [])
    if not isinstance(ai_param_hints, list):
        ai_param_hints = []

    for ev in manual_events:
        if ev["event_index"] <= start_index:
            continue
        if ev["event_index"] >= end_index:
            break
        if ev.get("kind") != kind:
            continue

        payload = ev.get("payload") if isinstance(ev.get("payload"), dict) else {}
        if target_row >= 0:
            ev_row = payload.get("row")
            if isinstance(ev_row, (int, float)) and int(ev_row) != target_row:
                continue

        if kind in ("row_fx_param", "master_fx_param") and ai_param_hints:
            pid = str(payload.get("param_id") or "").lower()
            if pid and not any(h in pid or pid in h for h in ai_param_hints):
                continue

        old_v = payload.get("old_value", payload.get("old_gain", payload.get("old_pan")))
        new_v = payload.get("new_value", payload.get("new_gain", payload.get("new_pan")))

        if isinstance(old_v, (int, float)) and isinstance(new_v, (int, float)):
            manual_mag = abs(float(new_v) - float(old_v))
            ai_mag = max(1e-6, ai_row["ai_action_magnitude"])
            return max(0.0, min(3.0, manual_mag / ai_mag))

    return None


def build_rows(session_path):
    with open(session_path, "r", encoding="utf-8") as f:
        session = json.load(f)

    session_id = str(session.get("session_id") or os.path.basename(session_path))
    project_id = str(session.get("project_id") or session_id)
    events = session.get("events", []) if isinstance(session.get("events"), list) else []

    manual_events = []
    for e in events:
        if isinstance(e, dict) and e.get("type") == "manual_edit":
            manual_events.append(
                {
                    "event_index": int(e.get("index") or 0),
                    "kind": e.get("kind"),
                    "payload": e.get("payload") if isinstance(e.get("payload"), dict) else {},
                }
            )
    manual_events.sort(key=lambda x: x["event_index"])

    ai_step_indices = [
        int(e.get("index") or 0)
        for e in events
        if isinstance(e, dict) and e.get("type") == "ai_step"
    ]
    ai_step_indices_sorted = sorted(ai_step_indices)
    rows = []

    for ev in events:
        if not isinstance(ev, dict) or ev.get("type") != "ai_step":
            continue

        event_index = int(ev.get("index") or 0)
        next_ai_index = None
        for idx in ai_step_indices_sorted:
            if idx > event_index:
                next_ai_index = idx
                break
        if next_ai_index is None:
            next_ai_index = 1 << 30

        pre_snapshot = ev.get("pre_snapshot") if isinstance(ev.get("pre_snapshot"), dict) else {}
        llm_payload = ev.get("llm_payload") if isinstance(ev.get("llm_payload"), dict) else {}
        resolved_actions = ev.get("resolved_actions") if isinstance(ev.get("resolved_actions"), list) else []

        proj = _project_stats(pre_snapshot)
        counts = _count_action_groups(resolved_actions)

        for a in resolved_actions:
            if not isinstance(a, dict):
                continue

            action_type = str(a.get("type") or "")
            goal = _goal_meta_for_action(llm_payload, a)

            row = {
                "project_id": project_id,
                "session_id": session_id,
                "event_index": event_index,
                "action_type": action_type,
                "is_master_action": 1 if _is_master_action(action_type) else 0,
                **goal,
                **proj,
                **counts,
                **_action_type_features(action_type),
                "action_row_index": _action_row_index(a),
                "ai_action_magnitude": _extract_action_magnitude(a, pre_snapshot),
                "label_apply": 1,
                "label_magnitude_scale": 1.0,
                "action_param_hints": _tokenize_action_param_hints(a),
            }

            manual_scale = _infer_manual_scale(
                row,
                manual_events,
                event_index,
                next_ai_index,
            )
            if manual_scale is not None:
                row["label_magnitude_scale"] = manual_scale
                if manual_scale < 0.05:
                    row["label_apply"] = 0

            row["label_magnitude_scale"] = float(max(0.0, min(3.0, row["label_magnitude_scale"])))
            row.pop("action_param_hints", None)
            rows.append(row)

    return rows


def main():
    args = parse_args()
    if len(FEATURE_COLUMNS) != EXPECTED_FEATURE_COUNT:
        raise SystemExit(
            f"Feature contract mismatch: expected {EXPECTED_FEATURE_COUNT}, got {len(FEATURE_COLUMNS)}"
        )

    session_files = sorted(glob.glob(os.path.join(args.sessions_dir, "*.json")))
    if not session_files:
        raise SystemExit(f"No session files found in: {args.sessions_dir}")

    rows = []
    for fp in session_files:
        try:
            rows.extend(build_rows(fp))
        except Exception as exc:
            print(f"[warn] failed to parse {fp}: {exc}")

    if not rows:
        raise SystemExit("No usable ai_step action rows were produced.")

    df = pd.DataFrame(rows)
    for col in FEATURE_COLUMNS:
        if col not in df.columns:
            df[col] = 0.0

    out_dir = os.path.dirname(args.out_csv)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    df.to_csv(args.out_csv, index=False)

    print(f"Wrote {len(df)} rows to {args.out_csv}")


if __name__ == "__main__":
    main()
