#!/usr/bin/env python3
import argparse
import json
import os

import joblib
import numpy as np
import pandas as pd
from sklearn.metrics import accuracy_score, mean_absolute_error, roc_auc_score
from sklearn.model_selection import GroupShuffleSplit, train_test_split

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


def parse_args():
    p = argparse.ArgumentParser(description="Evaluate trained two-stage models.")
    p.add_argument("--dataset-csv", required=True)
    p.add_argument("--model-dir", required=True)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--test-size", type=float, default=0.2)
    p.add_argument(
        "--use-full-dataset",
        action="store_true",
        help="Evaluate on the full dataset instead of holdout split.",
    )
    return p.parse_args()


def _pick_group_series(df):
    for col in ("project_id", "session_id"):
        if col in df.columns:
            s = df[col].astype(str).fillna("")
            if s.nunique() >= 2:
                return s, col
    return None, None


def _split_indices(df, y_apply, seed, test_size):
    groups, group_col = _pick_group_series(df)
    if groups is not None:
        gss = GroupShuffleSplit(n_splits=1, test_size=test_size, random_state=seed)
        train_idx, val_idx = next(gss.split(df, y_apply, groups=groups))
        return train_idx, val_idx, "group", group_col

    idx = np.arange(len(df))
    stratify = y_apply if y_apply.nunique() > 1 else None
    train_idx, val_idx = train_test_split(
        idx,
        test_size=test_size,
        random_state=seed,
        stratify=stratify,
    )
    return train_idx, val_idx, "random", None


def _predict_apply_scores(model, X):
    if hasattr(model, "predict_proba"):
        probs = model.predict_proba(X)
        if probs.ndim == 2 and probs.shape[1] >= 2:
            return probs[:, 1]
    if hasattr(model, "decision_function"):
        logits = model.decision_function(X)
        return 1.0 / (1.0 + np.exp(-logits))
    return np.clip(model.predict(X), 0.0, 1.0)


def main():
    args = parse_args()
    if len(FEATURE_COLUMNS) != EXPECTED_FEATURE_COUNT:
        raise SystemExit(
            f"Feature contract mismatch: expected {EXPECTED_FEATURE_COUNT}, got {len(FEATURE_COLUMNS)}"
        )

    apply_path = os.path.join(args.model_dir, "apply_classifier.joblib")
    reg_path = os.path.join(args.model_dir, "magnitude_regressor.joblib")

    if not os.path.exists(apply_path) or not os.path.exists(reg_path):
        raise SystemExit("Missing trained model files in model-dir")

    apply_model = joblib.load(apply_path)
    reg_model = joblib.load(reg_path)

    manifest_path = os.path.join(args.model_dir, "feature_manifest.json")
    if os.path.exists(manifest_path):
        with open(manifest_path, "r", encoding="utf-8") as f:
            manifest = json.load(f)
        feature_cols = manifest.get("feature_columns", FEATURE_COLUMNS)
    else:
        feature_cols = FEATURE_COLUMNS

    df = pd.read_csv(args.dataset_csv)
    if df.empty:
        raise SystemExit("Dataset is empty")

    missing = [c for c in feature_cols if c not in df.columns]
    if missing:
        raise SystemExit(f"Dataset missing feature columns required by model: {missing}")

    y_apply = df["label_apply"].astype(float).clip(0.0, 1.0).round().astype(int)
    y_scale = df["label_magnitude_scale"].astype(float).clip(0.0, 3.0)
    X = df[feature_cols].astype(float)

    if args.use_full_dataset:
        eval_idx = np.arange(len(df))
        split_strategy = "full_dataset"
        split_group_col = None
    else:
        _, eval_idx, split_strategy, split_group_col = _split_indices(
            df, y_apply, args.seed, args.test_size
        )

    X_eval = X.iloc[eval_idx]
    y_apply_eval = y_apply.iloc[eval_idx]
    y_scale_eval = y_scale.iloc[eval_idx]

    apply_scores = np.clip(_predict_apply_scores(apply_model, X_eval), 0.0, 1.0)
    y_apply_pred = apply_model.predict(X_eval).astype(int)
    out = {
        "apply_accuracy": float(accuracy_score(y_apply_eval.astype(int), y_apply_pred)),
        "eval_rows": int(len(eval_idx)),
        "split_strategy": split_strategy,
        "split_group_column": split_group_col,
    }
    if split_group_col is not None:
        out["eval_groups"] = int(df.iloc[eval_idx][split_group_col].astype(str).nunique())

    if y_apply_eval.nunique() > 1:
        out["apply_roc_auc"] = float(roc_auc_score(y_apply_eval, apply_scores))

    # Evaluate regressor on rows where apply=1 by default
    mask = y_apply_eval == 1
    if mask.sum() < 4:
        mask = np.ones(len(X_eval), dtype=bool)

    y_scale_pred = np.clip(reg_model.predict(X_eval[mask]), 0.0, 3.0)
    out["scale_mae"] = float(mean_absolute_error(y_scale_eval[mask], y_scale_pred))

    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
