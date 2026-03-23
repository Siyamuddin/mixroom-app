#!/usr/bin/env python3
import argparse
import json
import math
import re
import shutil
import subprocess
import sys
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import (
    ExtraTreesClassifier,
    ExtraTreesRegressor,
    GradientBoostingClassifier,
    GradientBoostingRegressor,
    RandomForestClassifier,
    RandomForestRegressor,
)
from sklearn.metrics import accuracy_score, mean_absolute_error, roc_auc_score
from sklearn.model_selection import GroupShuffleSplit

from train import EXPECTED_FEATURE_COUNT, FEATURE_COLUMNS

KIND_COLUMNS = (
    "kind_balance",
    "kind_gain",
    "kind_pan",
    "kind_eq",
    "kind_compressor",
    "kind_limiter",
    "kind_clipper",
    "kind_reverb",
    "kind_delay",
    "kind_deesser",
    "kind_distortion",
)

ACTION_COLUMNS = (
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
)

ISSUE_PROFILES = {
    "balanced": {
        "density": -0.10,
        "brightness": 0.00,
        "low_weight": 0.00,
        "sibilance": -0.10,
        "dynamics": 0.12,
        "loudness": -0.12,
        "width": 0.08,
        "imbalance": -0.10,
        "transient": 0.05,
        "noise": -0.12,
        "silence": 0.02,
    },
    "muddy": {
        "density": 0.24,
        "brightness": -0.26,
        "low_weight": 0.34,
        "sibilance": -0.04,
        "dynamics": -0.04,
        "loudness": 0.08,
        "width": -0.05,
        "imbalance": 0.03,
        "transient": -0.06,
        "noise": 0.02,
        "silence": -0.03,
    },
    "harsh": {
        "density": 0.08,
        "brightness": 0.28,
        "low_weight": -0.04,
        "sibilance": 0.34,
        "dynamics": -0.06,
        "loudness": 0.12,
        "width": 0.02,
        "imbalance": 0.02,
        "transient": 0.12,
        "noise": 0.06,
        "silence": -0.02,
    },
    "dull": {
        "density": -0.02,
        "brightness": -0.32,
        "low_weight": 0.02,
        "sibilance": -0.16,
        "dynamics": -0.12,
        "loudness": -0.08,
        "width": -0.08,
        "imbalance": 0.04,
        "transient": -0.18,
        "noise": 0.02,
        "silence": 0.04,
    },
    "clipped": {
        "density": 0.10,
        "brightness": 0.06,
        "low_weight": 0.06,
        "sibilance": 0.04,
        "dynamics": -0.30,
        "loudness": 0.34,
        "width": -0.04,
        "imbalance": 0.00,
        "transient": 0.18,
        "noise": 0.10,
        "silence": -0.06,
    },
    "dynamic": {
        "density": 0.04,
        "brightness": 0.00,
        "low_weight": 0.02,
        "sibilance": 0.00,
        "dynamics": 0.36,
        "loudness": -0.06,
        "width": 0.02,
        "imbalance": 0.00,
        "transient": 0.18,
        "noise": -0.02,
        "silence": 0.02,
    },
    "crowded": {
        "density": 0.36,
        "brightness": 0.02,
        "low_weight": 0.08,
        "sibilance": 0.02,
        "dynamics": -0.08,
        "loudness": 0.08,
        "width": -0.02,
        "imbalance": 0.04,
        "transient": 0.04,
        "noise": 0.04,
        "silence": -0.08,
    },
    "wide_sparse": {
        "density": -0.24,
        "brightness": 0.04,
        "low_weight": -0.06,
        "sibilance": 0.00,
        "dynamics": 0.08,
        "loudness": -0.02,
        "width": 0.30,
        "imbalance": 0.06,
        "transient": -0.02,
        "noise": -0.02,
        "silence": 0.12,
    },
    "narrow": {
        "density": 0.02,
        "brightness": -0.02,
        "low_weight": 0.04,
        "sibilance": 0.00,
        "dynamics": -0.02,
        "loudness": 0.02,
        "width": -0.30,
        "imbalance": 0.18,
        "transient": 0.00,
        "noise": 0.00,
        "silence": 0.02,
    },
    "boomy": {
        "density": 0.10,
        "brightness": -0.16,
        "low_weight": 0.38,
        "sibilance": -0.04,
        "dynamics": -0.06,
        "loudness": 0.10,
        "width": -0.04,
        "imbalance": 0.02,
        "transient": -0.04,
        "noise": 0.02,
        "silence": -0.02,
    },
    "sibilant": {
        "density": 0.06,
        "brightness": 0.22,
        "low_weight": -0.06,
        "sibilance": 0.38,
        "dynamics": -0.04,
        "loudness": 0.04,
        "width": 0.02,
        "imbalance": 0.00,
        "transient": 0.08,
        "noise": 0.04,
        "silence": -0.02,
    },
    "noisy": {
        "density": 0.02,
        "brightness": 0.06,
        "low_weight": 0.00,
        "sibilance": 0.08,
        "dynamics": -0.08,
        "loudness": 0.04,
        "width": -0.02,
        "imbalance": 0.00,
        "transient": 0.04,
        "noise": 0.34,
        "silence": 0.10,
    },
}

STYLE_PROFILES = {
    "modern_punchy": {"loudness": 0.14, "dynamics": -0.06, "width": 0.04},
    "open_spacious": {"width": 0.18, "loudness": -0.08, "brightness": 0.04},
    "natural_clean": {"noise": -0.10, "loudness": -0.06, "dynamics": 0.08},
    "warm_glue": {"low_weight": 0.08, "brightness": -0.04, "dynamics": 0.02},
    "aggressive_edm": {"loudness": 0.18, "width": 0.10, "dynamics": -0.10},
}

SOURCE_PROFILES = {
    "clean_stems": {"noise": -0.12, "brightness": 0.04, "silence": -0.02},
    "prosumer": {"noise": 0.02, "brightness": 0.00, "silence": 0.02},
    "rough_live": {"noise": 0.16, "dynamics": 0.08, "silence": 0.06},
    "lofi_demo": {"noise": 0.20, "brightness": -0.06, "silence": 0.08},
}

ARRANGEMENT_PROFILES = {
    "sparse": {"density": -0.20, "width": 0.08, "silence": 0.12},
    "mid": {"density": 0.00, "width": 0.00, "silence": 0.00},
    "dense": {"density": 0.18, "width": -0.02, "silence": -0.08},
    "wall": {"density": 0.32, "width": -0.04, "silence": -0.10},
}

MIX_STAGE_PROFILES = {
    "rough": {"loudness": -0.06, "imbalance": 0.08, "noise": 0.06},
    "midmix": {"loudness": 0.02, "imbalance": 0.02, "noise": 0.02},
    "near_finish": {"loudness": 0.08, "imbalance": -0.06, "noise": -0.04},
}

ISSUE_KIND_WEIGHTS = {
    "balanced": {"balance": 0.18, "gain": 0.16, "pan": 0.12, "eq": 0.14, "compressor": 0.12, "limiter": 0.06, "clipper": 0.04, "reverb": 0.08, "delay": 0.04, "deesser": 0.04, "distortion": 0.02},
    "muddy": {"eq": 0.28, "balance": 0.18, "gain": 0.16, "pan": 0.14, "compressor": 0.10, "limiter": 0.04, "clipper": 0.03, "reverb": 0.02, "delay": 0.01, "deesser": 0.02, "distortion": 0.02},
    "harsh": {"deesser": 0.24, "eq": 0.28, "balance": 0.10, "gain": 0.08, "compressor": 0.08, "limiter": 0.08, "clipper": 0.04, "reverb": 0.03, "delay": 0.02, "pan": 0.03, "distortion": 0.02},
    "dull": {"eq": 0.24, "reverb": 0.16, "delay": 0.12, "distortion": 0.10, "balance": 0.08, "gain": 0.08, "pan": 0.08, "compressor": 0.06, "limiter": 0.03, "clipper": 0.02, "deesser": 0.03},
    "clipped": {"limiter": 0.24, "clipper": 0.24, "gain": 0.18, "compressor": 0.14, "balance": 0.06, "eq": 0.04, "pan": 0.02, "reverb": 0.02, "delay": 0.01, "deesser": 0.02, "distortion": 0.01},
    "dynamic": {"compressor": 0.26, "limiter": 0.18, "clipper": 0.12, "gain": 0.14, "balance": 0.08, "eq": 0.06, "pan": 0.04, "reverb": 0.03, "delay": 0.03, "deesser": 0.03, "distortion": 0.03},
    "crowded": {"pan": 0.20, "eq": 0.20, "balance": 0.18, "gain": 0.12, "compressor": 0.08, "reverb": 0.04, "delay": 0.03, "limiter": 0.04, "clipper": 0.03, "deesser": 0.04, "distortion": 0.04},
    "wide_sparse": {"pan": 0.18, "reverb": 0.22, "delay": 0.18, "eq": 0.10, "balance": 0.06, "gain": 0.06, "compressor": 0.04, "limiter": 0.02, "clipper": 0.01, "deesser": 0.03, "distortion": 0.10},
    "narrow": {"pan": 0.28, "balance": 0.16, "reverb": 0.12, "delay": 0.10, "eq": 0.08, "gain": 0.06, "compressor": 0.04, "limiter": 0.03, "clipper": 0.01, "deesser": 0.04, "distortion": 0.08},
    "boomy": {"eq": 0.30, "balance": 0.18, "gain": 0.16, "compressor": 0.10, "pan": 0.08, "limiter": 0.04, "clipper": 0.03, "reverb": 0.02, "delay": 0.01, "deesser": 0.02, "distortion": 0.02},
    "sibilant": {"deesser": 0.34, "eq": 0.24, "compressor": 0.08, "balance": 0.06, "gain": 0.06, "pan": 0.04, "limiter": 0.06, "clipper": 0.03, "reverb": 0.03, "delay": 0.02, "distortion": 0.04},
    "noisy": {"eq": 0.16, "compressor": 0.10, "gain": 0.10, "balance": 0.10, "pan": 0.08, "deesser": 0.10, "reverb": 0.05, "delay": 0.04, "limiter": 0.08, "clipper": 0.05, "distortion": 0.14},
}

STYLE_KIND_MULTIPLIERS = {
    "modern_punchy": {"compressor": 1.14, "limiter": 1.18, "clipper": 1.12, "reverb": 0.82, "delay": 0.88},
    "open_spacious": {"pan": 1.12, "reverb": 1.22, "delay": 1.18, "clipper": 0.72, "limiter": 0.84},
    "natural_clean": {"balance": 1.08, "pan": 1.04, "reverb": 0.86, "delay": 0.82, "distortion": 0.70, "clipper": 0.76},
    "warm_glue": {"eq": 1.08, "compressor": 1.12, "balance": 1.06, "delay": 0.88},
    "aggressive_edm": {"limiter": 1.18, "clipper": 1.22, "pan": 1.06, "reverb": 0.78, "delay": 0.82, "distortion": 1.10},
}

MASTER_FRIENDLY_KINDS = {"balance", "gain", "compressor", "limiter", "clipper"}
SPACEY_KINDS = {"reverb", "delay"}
DESTRUCTIVE_ACTIONS = {
    "delete_effect",
    "delete_master_effect",
    "hard_reset_row_fx",
    "hard_reset_master_fx",
}

LATENT_KEYS = (
    "density",
    "brightness",
    "low_weight",
    "sibilance",
    "dynamics",
    "loudness",
    "width",
    "imbalance",
    "transient",
    "noise",
    "silence",
)

ISSUE_COMPANIONS = {
    "balanced": {
        "wide_sparse": 0.20,
        "narrow": 0.14,
        "dynamic": 0.12,
        "dull": 0.10,
        "muddy": 0.08,
        "harsh": 0.08,
        "crowded": 0.08,
        "clipped": 0.06,
        "boomy": 0.05,
        "sibilant": 0.05,
        "noisy": 0.04,
    },
    "muddy": {
        "crowded": 0.28,
        "boomy": 0.24,
        "noisy": 0.14,
        "dull": 0.10,
        "dynamic": 0.08,
        "harsh": 0.06,
        "narrow": 0.05,
        "clipped": 0.05,
    },
    "harsh": {
        "sibilant": 0.34,
        "clipped": 0.18,
        "crowded": 0.12,
        "dynamic": 0.10,
        "noisy": 0.08,
        "dull": 0.08,
        "narrow": 0.06,
        "muddy": 0.04,
    },
    "dull": {
        "wide_sparse": 0.22,
        "muddy": 0.18,
        "dynamic": 0.16,
        "crowded": 0.12,
        "boomy": 0.10,
        "narrow": 0.08,
        "noisy": 0.08,
        "harsh": 0.06,
    },
    "clipped": {
        "harsh": 0.20,
        "dynamic": 0.20,
        "crowded": 0.18,
        "muddy": 0.12,
        "boomy": 0.10,
        "sibilant": 0.08,
        "noisy": 0.08,
        "narrow": 0.04,
    },
    "dynamic": {
        "clipped": 0.22,
        "dull": 0.20,
        "wide_sparse": 0.16,
        "harsh": 0.10,
        "crowded": 0.10,
        "muddy": 0.08,
        "narrow": 0.08,
        "noisy": 0.06,
    },
    "crowded": {
        "muddy": 0.28,
        "narrow": 0.18,
        "harsh": 0.12,
        "clipped": 0.12,
        "boomy": 0.10,
        "dynamic": 0.08,
        "dull": 0.06,
        "noisy": 0.06,
    },
    "wide_sparse": {
        "dull": 0.24,
        "dynamic": 0.18,
        "balanced": 0.16,
        "narrow": 0.10,
        "harsh": 0.08,
        "muddy": 0.08,
        "sibilant": 0.06,
        "noisy": 0.06,
        "clipped": 0.04,
    },
    "narrow": {
        "crowded": 0.26,
        "wide_sparse": 0.16,
        "muddy": 0.14,
        "harsh": 0.10,
        "clipped": 0.10,
        "dynamic": 0.08,
        "sibilant": 0.08,
        "noisy": 0.08,
    },
    "boomy": {
        "muddy": 0.34,
        "crowded": 0.18,
        "clipped": 0.12,
        "dull": 0.10,
        "noisy": 0.08,
        "narrow": 0.08,
        "dynamic": 0.06,
        "harsh": 0.04,
    },
    "sibilant": {
        "harsh": 0.36,
        "clipped": 0.14,
        "noisy": 0.14,
        "crowded": 0.10,
        "dynamic": 0.08,
        "dull": 0.08,
        "narrow": 0.06,
        "muddy": 0.04,
    },
    "noisy": {
        "muddy": 0.20,
        "harsh": 0.16,
        "sibilant": 0.14,
        "crowded": 0.14,
        "dull": 0.10,
        "clipped": 0.10,
        "boomy": 0.08,
        "dynamic": 0.08,
    },
}


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Build a synthetic beta placeholder learned-magnitude ONNX model. "
            "This is stronger than the old smoke-test bootstrap, but it is still "
            "not a substitute for producer-labeled training data."
        )
    )
    parser.add_argument(
        "--rows",
        type=int,
        default=18000,
        help="Approximate number of synthetic action rows to generate.",
    )
    parser.add_argument(
        "--projects",
        type=int,
        default=420,
        help="Number of synthetic projects to simulate.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for reproducible output.",
    )
    parser.add_argument(
        "--out-root",
        default="tools/ai_mixing/out/bootstrap_sample",
        help="Output root for dataset/models/onnx.",
    )
    parser.add_argument(
        "--copy-assets",
        action="store_true",
        help="Copy exported ONNX files into assets/models.",
    )
    parser.add_argument(
        "--model-tag",
        default="",
        help=(
            "Optional archive tag. When set, the script also keeps versioned "
            "copies like mix_apply_classifier_<tag>.onnx instead of only the "
            "stable filenames."
        ),
    )
    parser.add_argument(
        "--candidate-profile",
        choices=("full", "fast"),
        default="full",
        help="Model-search profile. 'fast' skips the heaviest forest candidates.",
    )
    return parser.parse_args()


def clamp(value, lo=0.0, hi=1.0):
    return max(lo, min(hi, float(value)))


def sigmoid(x):
    return 1.0 / (1.0 + math.exp(-x))


def choose_weighted(rng, weights):
    keys = list(weights.keys())
    probs = np.array([max(0.0, float(weights[key])) for key in keys], dtype=float)
    total = probs.sum()
    if total <= 0:
        probs = np.ones(len(keys), dtype=float) / len(keys)
    else:
        probs = probs / total
    return str(rng.choice(keys, p=probs))


def jitter(rng, center, spread, lo=0.0, hi=1.0):
    return clamp(rng.normal(center, spread), lo, hi)


def sanitize_model_tag(tag):
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "_", tag.strip())
    return cleaned.strip("._-")


def _neutral_latents(rng):
    return {
        "density": jitter(rng, 0.48, 0.16),
        "brightness": jitter(rng, 0.48, 0.16),
        "low_weight": jitter(rng, 0.46, 0.16),
        "sibilance": jitter(rng, 0.30, 0.14),
        "dynamics": jitter(rng, 0.50, 0.16),
        "loudness": jitter(rng, 0.48, 0.16),
        "width": jitter(rng, 0.46, 0.16),
        "imbalance": jitter(rng, 0.20, 0.12),
        "transient": jitter(rng, 0.42, 0.16),
        "noise": jitter(rng, 0.18, 0.12),
        "silence": jitter(rng, 0.14, 0.10),
    }


def _apply_profile(latents, profile):
    for key, delta in profile.items():
        latents[key] = clamp(latents[key] + delta)


def _sample_project_plan(rng):
    primary_issue = choose_weighted(
        rng,
        {
            "balanced": 0.10,
            "muddy": 0.12,
            "harsh": 0.10,
            "dull": 0.10,
            "clipped": 0.08,
            "dynamic": 0.09,
            "crowded": 0.12,
            "wide_sparse": 0.08,
            "narrow": 0.07,
            "boomy": 0.06,
            "sibilant": 0.04,
            "noisy": 0.04,
        },
    )
    issue_count = 1 if primary_issue == "balanced" else int(rng.choice([1, 2, 3], p=[0.45, 0.42, 0.13]))
    issues = [primary_issue]
    while len(issues) < issue_count:
        companion_weights = ISSUE_COMPANIONS.get(primary_issue, {})
        available = {
            issue: weight
            for issue, weight in companion_weights.items()
            if issue not in issues and issue in ISSUE_PROFILES
        }
        if not available:
            available = {
                issue: 1.0
                for issue in ISSUE_PROFILES
                if issue not in issues and issue != primary_issue and issue != "balanced"
            }
        candidate = choose_weighted(rng, available)
        if candidate not in issues:
            issues.append(candidate)
    style = choose_weighted(rng, {key: 1.0 for key in STYLE_PROFILES})
    source = choose_weighted(rng, {"clean_stems": 0.30, "prosumer": 0.38, "rough_live": 0.18, "lofi_demo": 0.14})
    arrangement = choose_weighted(rng, {"sparse": 0.16, "mid": 0.40, "dense": 0.28, "wall": 0.16})
    stage = choose_weighted(rng, {"rough": 0.28, "midmix": 0.42, "near_finish": 0.30})
    return {
        "issues": issues,
        "style": style,
        "source": source,
        "arrangement": arrangement,
        "stage": stage,
    }


def _latents_to_context(latents, rng):
    density = latents["density"]
    brightness = latents["brightness"]
    low_weight = latents["low_weight"]
    sibilance = latents["sibilance"]
    dynamics = latents["dynamics"]
    loudness = latents["loudness"]
    width = latents["width"]
    imbalance = latents["imbalance"]
    transient = latents["transient"]
    noise = latents["noise"]
    silence = latents["silence"]

    ctx = {
        "project_bpm_norm": jitter(rng, 0.48 + 0.10 * transient - 0.04 * silence, 0.14),
        "rows_with_audio_ratio": clamp(0.16 + 0.74 * density - 0.22 * silence + rng.normal(0.0, 0.05)),
        "median_rms": clamp(0.10 + 0.76 * loudness - 0.18 * silence + rng.normal(0.0, 0.04)),
        "median_crest_norm": clamp(0.18 + 0.70 * dynamics - 0.18 * loudness + rng.normal(0.0, 0.05)),
        "rms_iqr": clamp(0.12 + 0.64 * dynamics + 0.10 * density + rng.normal(0.0, 0.05)),
        "median_centroid_norm": clamp(0.12 + 0.76 * brightness - 0.12 * low_weight + rng.normal(0.0, 0.04)),
        "median_zcr": clamp(0.10 + 0.58 * brightness + 0.18 * noise + rng.normal(0.0, 0.05)),
        "median_sibilance_norm": clamp(0.06 + 0.76 * sibilance + 0.12 * brightness + rng.normal(0.0, 0.04)),
        "median_bassiness_norm": clamp(0.08 + 0.78 * low_weight - 0.12 * brightness + rng.normal(0.0, 0.04)),
        "median_hf_rms_norm": clamp(0.10 + 0.72 * brightness + 0.08 * sibilance + rng.normal(0.0, 0.04)),
        "median_st_rms_mean": clamp(0.12 + 0.68 * loudness - 0.12 * silence + rng.normal(0.0, 0.04)),
        "median_st_rms_p95": clamp(0.18 + 0.66 * loudness + 0.16 * transient + rng.normal(0.0, 0.05)),
        "median_st_rms_std": clamp(0.08 + 0.58 * dynamics + 0.18 * transient + rng.normal(0.0, 0.05)),
        "median_transient_density": clamp(0.08 + 0.68 * transient + 0.16 * density + rng.normal(0.0, 0.05)),
        "overlap_density": clamp(0.04 + 0.84 * density - 0.10 * width + rng.normal(0.0, 0.05)),
        "masking_pair_ratio": clamp(0.04 + 0.58 * density + 0.20 * low_weight + 0.10 * loudness + rng.normal(0.0, 0.05)),
        "centroid_collision_ratio": clamp(0.04 + 0.46 * density + 0.16 * abs(brightness - 0.50) + rng.normal(0.0, 0.05)),
        "avg_overlap_centroid_gap_norm": clamp(0.80 - (0.48 * density + 0.18 * low_weight + 0.10 * brightness) + rng.normal(0.0, 0.05)),
        "overlap_rms_pressure": clamp(0.04 + 0.54 * density + 0.24 * loudness + rng.normal(0.0, 0.05)),
        "role_overlap_ratio": clamp(0.04 + 0.72 * density + 0.10 * low_weight + rng.normal(0.0, 0.05)),
        "st_dynamic_headroom": clamp(0.10 + 0.68 * dynamics - 0.34 * loudness - 0.10 * noise + rng.normal(0.0, 0.05)),
        "median_true_peak_norm": clamp(0.16 + 0.68 * loudness + 0.20 * transient + rng.normal(0.0, 0.04)),
        "median_integrated_lufs_norm": clamp(0.08 + 0.76 * loudness + rng.normal(0.0, 0.04)),
        "median_short_lufs_mean_norm": clamp(0.10 + 0.74 * loudness + 0.08 * transient + rng.normal(0.0, 0.04)),
        "median_short_lufs_p95_norm": clamp(0.14 + 0.72 * loudness + 0.16 * transient + rng.normal(0.0, 0.04)),
        "median_lra_norm": clamp(0.10 + 0.68 * dynamics - 0.16 * loudness + rng.normal(0.0, 0.05)),
        "median_clip_ratio": clamp(0.02 + 0.48 * loudness + 0.18 * transient - 0.28 * dynamics + rng.normal(0.0, 0.04)),
        "median_spectral_flatness": clamp(0.06 + 0.54 * noise + 0.18 * brightness + rng.normal(0.0, 0.05)),
        "median_spectral_rolloff_norm": clamp(0.10 + 0.72 * brightness + rng.normal(0.0, 0.04)),
        "median_spectral_slope_norm": clamp(0.18 + 0.58 * brightness - 0.14 * low_weight + rng.normal(0.0, 0.05)),
        "median_spectral_flux": clamp(0.08 + 0.58 * transient + 0.16 * brightness + 0.08 * noise + rng.normal(0.0, 0.05)),
        "median_phase_corr_norm": clamp(0.86 - 0.66 * width + 0.14 * imbalance + rng.normal(0.0, 0.04)),
        "median_side_ratio_norm": clamp(0.08 + 0.80 * width - 0.10 * imbalance + rng.normal(0.0, 0.05)),
        "median_stereo_imbalance": clamp(0.04 + 0.82 * imbalance + 0.10 * density + rng.normal(0.0, 0.05)),
        "median_silence_ratio": clamp(0.02 + 0.72 * silence - 0.18 * density + rng.normal(0.0, 0.04)),
        "median_onset_rate_norm": clamp(0.06 + 0.56 * transient + 0.18 * density + rng.normal(0.0, 0.05)),
        "median_noise_floor_norm": clamp(0.04 + 0.78 * noise + 0.06 * loudness + rng.normal(0.0, 0.04)),
        "median_spectral_bandwidth_norm": clamp(0.10 + 0.68 * brightness + 0.10 * width + rng.normal(0.0, 0.04)),
        "overlap_low_collision": clamp(0.04 + 0.42 * density + 0.34 * low_weight + rng.normal(0.0, 0.05)),
        "overlap_lowmid_collision": clamp(0.04 + 0.46 * density + 0.26 * low_weight + 0.08 * loudness + rng.normal(0.0, 0.05)),
        "overlap_mid_collision": clamp(0.04 + 0.52 * density + 0.10 * loudness + rng.normal(0.0, 0.05)),
        "overlap_high_collision": clamp(0.04 + 0.38 * density + 0.26 * brightness + 0.18 * sibilance + rng.normal(0.0, 0.05)),
    }
    return {key: clamp(value) for key, value in ctx.items()}


def _build_project_context(rng, plan):
    latents = _neutral_latents(rng)
    for issue in plan["issues"]:
        _apply_profile(latents, ISSUE_PROFILES[issue])
    _apply_profile(latents, STYLE_PROFILES[plan["style"]])
    _apply_profile(latents, SOURCE_PROFILES[plan["source"]])
    _apply_profile(latents, ARRANGEMENT_PROFILES[plan["arrangement"]])
    _apply_profile(latents, MIX_STAGE_PROFILES[plan["stage"]])
    latents["brightness"] = clamp(latents["brightness"] + 0.10 * latents["sibilance"] - 0.08 * latents["low_weight"])
    latents["width"] = clamp(latents["width"] - 0.10 * latents["density"] + 0.05 * latents["silence"])
    latents["loudness"] = clamp(latents["loudness"] + 0.10 * latents["density"] - 0.12 * latents["dynamics"])
    latents["imbalance"] = clamp(latents["imbalance"] + 0.06 * max(0.0, 0.45 - latents["width"]))
    return _latents_to_context(latents, rng)


def _scope_values(scope):
    return {
        "scope_auto": 1.0 if scope == "auto" else 0.0,
        "scope_row": 1.0 if scope == "row" else 0.0,
        "scope_master": 1.0 if scope == "master" else 0.0,
    }


def _kind_values(kind):
    out = {column: 0.0 for column in KIND_COLUMNS}
    out[f"kind_{kind}"] = 1.0
    return out


def _action_values(action_type):
    out = {column: 0.0 for column in ACTION_COLUMNS}
    column = f"action_{action_type}"
    if column in out:
        out[column] = 1.0
    else:
        out["action_other"] = 1.0
    return out


def _choose_scope(rng, plan, context):
    issues = set(plan["issues"])
    crowded = _crowded_pressure(context)
    clipped = _clipping_pressure(context)
    imbalance = _imbalance_pressure(context)

    if "clipped" in issues or "dynamic" in issues or clipped > 0.60:
        return str(rng.choice(["row", "auto", "master"], p=[0.24, 0.20, 0.56]))
    if "crowded" in issues or "muddy" in issues or crowded > 0.58:
        return str(rng.choice(["row", "auto", "master"], p=[0.60, 0.26, 0.14]))
    if "wide_sparse" in issues or "narrow" in issues or imbalance > 0.50:
        return str(rng.choice(["row", "auto", "master"], p=[0.56, 0.30, 0.14]))
    if plan["stage"] == "rough":
        return str(rng.choice(["row", "auto", "master"], p=[0.56, 0.28, 0.16]))
    return str(rng.choice(["row", "auto", "master"], p=[0.44, 0.30, 0.26]))


def _choose_kind_and_action(rng, plan, scope, context):
    weights = {column[5:]: 0.01 for column in KIND_COLUMNS}
    for issue in plan["issues"]:
        for kind, weight in ISSUE_KIND_WEIGHTS[issue].items():
            weights[kind] = weights.get(kind, 0.0) + weight
    for kind, multiplier in STYLE_KIND_MULTIPLIERS[plan["style"]].items():
        weights[kind] = weights.get(kind, 0.01) * multiplier
    if plan["stage"] == "near_finish":
        weights["reverb"] *= 0.86
        weights["delay"] *= 0.88
        weights["distortion"] *= 0.84
    for kind in list(weights):
        weights[kind] *= _kind_context_multiplier(kind, scope, plan, context)
    kind = choose_weighted(rng, weights)
    is_master = scope == "master"

    if kind == "gain":
        action_type = "set_master_gain" if is_master else "set_row_gain"
    elif kind == "pan":
        action_type = "set_master_pan" if is_master else "set_row_pan"
    elif kind in ("eq", "compressor", "limiter", "clipper", "reverb", "delay", "deesser", "distortion"):
        if is_master:
            action_weights = {
                "adjust_master_effect_param_by_name": 0.56,
                "ensure_master_effect": 0.26,
                "delete_master_effect": 0.08,
                "hard_reset_master_fx": 0.03,
                "other": 0.07,
            }
        else:
            action_weights = {
                "adjust_effect_param_by_name": 0.58,
                "ensure_effect": 0.24,
                "delete_effect": 0.08,
                "hard_reset_row_fx": 0.03,
                "other": 0.07,
            }
        action_type = choose_weighted(rng, action_weights)
    else:
        action_type = "set_master_gain" if is_master else "set_row_gain"

    if kind == "balance" and action_type in DESTRUCTIVE_ACTIONS:
        action_type = "set_master_gain" if is_master else "set_row_gain"
    return kind, action_type


def _sample_action_magnitude(rng, kind, action_type, plan, context, scope):
    issues = set(plan["issues"])
    crowded = _crowded_pressure(context)
    clipped = _clipping_pressure(context)
    low_end_anchor = _low_end_anchor_pressure(context)
    noise = _noise_pressure(context)
    space_capacity = _space_capacity(context)

    if action_type in DESTRUCTIVE_ACTIONS:
        hi = 0.56 if plan["stage"] == "near_finish" else 0.74
        return jitter(rng, 0.18, 0.08, 0.02, hi)
    if action_type == "other":
        return jitter(rng, 0.28, 0.12, 0.02, 0.95)
    if action_type.startswith("ensure_"):
        center = 0.56 + 0.20 * space_capacity - 0.18 * crowded - 0.14 * clipped
        return jitter(rng, center, 0.14, 0.08, 1.10)
    if kind in ("gain", "balance"):
        center = 0.72 if {"clipped", "dynamic"} & issues else 0.52
        center += 0.10 * clipped + 0.06 * low_end_anchor
        hi = 1.26 if plan["stage"] == "near_finish" else 1.45
        return jitter(rng, center, 0.14, 0.05, hi)
    if kind == "pan":
        center = 0.32 + 0.14 * (1.0 - low_end_anchor) + 0.08 * _imbalance_pressure(context)
        hi = 0.84 if scope == "master" or plan["stage"] == "near_finish" else 0.98
        return jitter(rng, center, 0.12, 0.02, hi)
    if kind in ("eq", "deesser"):
        center = 0.62 + 0.18 * max(_mud_pressure(context), _harsh_pressure(context), _dull_pressure(context))
        hi = 1.40 if plan["stage"] == "near_finish" else 1.72
        return jitter(rng, center, 0.14, 0.08, hi)
    if kind in ("compressor", "limiter", "clipper"):
        center = 0.82 if "dynamic" in issues or "clipped" in issues else 0.68
        center += 0.18 * clipped + 0.10 * _dynamic_pressure(context)
        hi = 1.58 if plan["style"] == "natural_clean" else 1.92
        return jitter(rng, center, 0.16, 0.08, hi)
    if kind in ("reverb", "delay", "distortion"):
        center = 0.38 + 0.24 * space_capacity - 0.20 * crowded - 0.16 * clipped - 0.12 * noise
        hi = 0.92 if plan["stage"] == "near_finish" else 1.18
        return jitter(rng, center, 0.12, 0.06, hi)
    return jitter(rng, 0.56, 0.18, 0.05, 1.60)


def _goal_intensity(rng, plan):
    issues = set(plan["issues"])
    center = 0.56
    if "balanced" in issues:
        center -= 0.16
    if {"muddy", "harsh", "crowded", "clipped"} & issues:
        center += 0.12
    if plan["stage"] == "near_finish":
        center -= 0.04
    if plan["style"] == "aggressive_edm":
        center += 0.06
    return jitter(rng, center, 0.16)


def _op_counts(rng, action_type, scope, plan):
    stage_bias = {"rough": 0, "midmix": 1, "near_finish": 2}[plan["stage"]]
    source_bias = {"clean_stems": 0, "prosumer": 1, "rough_live": 1, "lofi_demo": 2}[plan["source"]]
    row_gain = 1.0 if action_type == "set_row_gain" else 0.0
    row_pan = 1.0 if action_type == "set_row_pan" else 0.0
    fx = 1.0 if "effect" in action_type or "reset" in action_type else 0.0
    master_ops = 1.0 if "master" in action_type else 0.0
    return {
        "count_row_gain_ops_norm": clamp((row_gain + stage_bias + rng.integers(0, 3)) / 12.0),
        "count_row_pan_ops_norm": clamp((row_pan + rng.integers(0, 3)) / 12.0),
        "count_fx_ops_norm": clamp((fx + stage_bias + source_bias + rng.integers(0, 7)) / 20.0),
        "count_master_ops_norm": clamp((master_ops + stage_bias + rng.integers(0, 4)) / 12.0),
        "is_master_action": 1.0 if scope == "master" else 0.0,
    }


def _mean(*values):
    return float(sum(values) / len(values))


def _crowded_pressure(row):
    return _mean(
        row["overlap_density"],
        row["masking_pair_ratio"],
        row["role_overlap_ratio"],
        row["overlap_mid_collision"],
    )


def _mud_pressure(row):
    return _mean(
        row["median_bassiness_norm"],
        row["overlap_low_collision"],
        row["overlap_lowmid_collision"],
        1.0 - row["median_centroid_norm"],
    )


def _harsh_pressure(row):
    return _mean(
        row["median_sibilance_norm"],
        row["median_hf_rms_norm"],
        row["overlap_high_collision"],
        row["median_true_peak_norm"],
    )


def _dull_pressure(row):
    return _mean(
        1.0 - row["median_centroid_norm"],
        1.0 - row["median_spectral_rolloff_norm"],
        1.0 - row["median_spectral_bandwidth_norm"],
        1.0 - row["median_transient_density"],
    )


def _dynamic_pressure(row):
    return _mean(
        row["st_dynamic_headroom"],
        row["median_lra_norm"],
        row["median_crest_norm"],
        row["rms_iqr"],
    )


def _clipping_pressure(row):
    return _mean(
        row["median_clip_ratio"],
        row["median_true_peak_norm"],
        row["median_integrated_lufs_norm"],
        row["median_short_lufs_p95_norm"],
    )


def _space_capacity(row):
    return _mean(
        row["median_side_ratio_norm"],
        1.0 - row["overlap_density"],
        1.0 - row["masking_pair_ratio"],
        1.0 - row["median_clip_ratio"],
    )


def _imbalance_pressure(row):
    return _mean(
        row["median_stereo_imbalance"],
        1.0 - row["median_phase_corr_norm"],
        1.0 - row["median_side_ratio_norm"],
    )


def _noise_pressure(row):
    return _mean(
        row["median_noise_floor_norm"],
        row["median_spectral_flatness"],
        row["median_silence_ratio"],
    )


def _low_end_anchor_pressure(row):
    return _mean(
        row["median_bassiness_norm"],
        row["overlap_low_collision"],
        row["overlap_lowmid_collision"],
        1.0 - row["median_phase_corr_norm"],
    )


def _kind_context_multiplier(kind, scope, plan, row):
    # Bias actions toward a more conservative "balance first, ambience later" mix flow.
    multiplier = 1.0

    if plan["stage"] == "rough":
        if kind in {"balance", "gain", "pan", "eq"}:
            multiplier *= 1.14
        if kind in {"limiter", "clipper", "deesser", "distortion"}:
            multiplier *= 0.84
    elif plan["stage"] == "near_finish":
        if kind in {"balance", "gain", "pan"}:
            multiplier *= 0.90
        if kind in {"compressor", "eq"}:
            multiplier *= 1.05
        if kind in {"reverb", "delay", "distortion", "clipper"}:
            multiplier *= 0.82

    if plan["source"] in {"rough_live", "lofi_demo"}:
        if kind in {"eq", "compressor", "deesser", "gain", "balance"}:
            multiplier *= 1.10
        if kind in {"reverb", "delay", "distortion"}:
            multiplier *= 0.78
    elif plan["source"] == "clean_stems":
        if kind in {"reverb", "delay"}:
            multiplier *= 1.05

    if plan["arrangement"] in {"dense", "wall"} and kind in {"reverb", "delay"}:
        multiplier *= 0.72
    if plan["arrangement"] == "sparse" and kind in {"pan", "reverb", "delay"}:
        multiplier *= 1.10

    crowded = _crowded_pressure(row)
    clipped = _clipping_pressure(row)
    noise = _noise_pressure(row)
    low_end_anchor = _low_end_anchor_pressure(row)
    space_capacity = _space_capacity(row)
    harsh = _harsh_pressure(row)
    mono_risk = _mean(1.0 - row["median_phase_corr_norm"], row["median_stereo_imbalance"])

    if low_end_anchor > 0.56:
        if kind in {"pan", "reverb", "delay", "distortion"}:
            multiplier *= 0.70
        if kind in {"balance", "gain", "eq", "compressor"}:
            multiplier *= 1.10

    if crowded > 0.58:
        if kind in {"reverb", "delay", "distortion"}:
            multiplier *= 0.60
        if kind in {"balance", "eq", "pan"}:
            multiplier *= 1.10

    if harsh > 0.56:
        if kind in {"deesser", "eq"}:
            multiplier *= 1.16
        if kind in {"reverb", "delay", "distortion"}:
            multiplier *= 0.76

    if clipped > 0.58:
        if kind in {"reverb", "delay", "distortion"}:
            multiplier *= 0.68
        if kind in {"gain", "compressor", "limiter", "clipper"}:
            multiplier *= 1.12

    if noise > 0.52:
        if kind in {"distortion", "reverb", "delay"}:
            multiplier *= 0.72
        if kind in {"eq", "deesser", "compressor"}:
            multiplier *= 1.08

    if mono_risk > 0.46:
        if kind in {"pan", "reverb", "delay"}:
            multiplier *= 0.74
        if kind in {"balance", "eq", "compressor"}:
            multiplier *= 1.06

    if space_capacity < 0.42 and kind in {"reverb", "delay"}:
        multiplier *= 0.68
    if space_capacity > 0.64 and kind in {"pan", "reverb", "delay"}:
        multiplier *= 1.08

    if scope == "master":
        if kind in {"pan", "reverb", "delay", "deesser"}:
            multiplier *= 0.62
        if kind in {"gain", "compressor", "limiter", "clipper", "balance"}:
            multiplier *= 1.06

    return max(0.02, multiplier)


def _action_need_score(row, kind):
    crowded_pressure = _crowded_pressure(row)
    mud_pressure = _mud_pressure(row)
    harsh_pressure = _harsh_pressure(row)
    dull_pressure = _dull_pressure(row)
    dynamic_pressure = _dynamic_pressure(row)
    clipping_pressure = _clipping_pressure(row)
    space_capacity = _space_capacity(row)
    imbalance_pressure = _imbalance_pressure(row)
    noise_pressure = _noise_pressure(row)
    low_end_anchor = _low_end_anchor_pressure(row)
    mono_risk = _mean(1.0 - row["median_phase_corr_norm"], row["median_stereo_imbalance"])
    low_level_pressure = _mean(1.0 - row["median_rms"], 1.0 - row["median_st_rms_mean"])

    if kind == "balance":
        return clamp(
            0.52 * crowded_pressure
            + 0.34 * imbalance_pressure
            + 0.18 * low_level_pressure
            + 0.10 * low_end_anchor
        )
    if kind == "gain":
        return clamp(
            0.46 * clipping_pressure
            + 0.18 * crowded_pressure
            + 0.28 * low_level_pressure
            + 0.12 * row["median_true_peak_norm"]
        )
    if kind == "pan":
        return clamp(
            0.42 * crowded_pressure
            + 0.42 * imbalance_pressure
            + 0.18 * (1.0 - row["median_side_ratio_norm"])
            - 0.18 * low_end_anchor
            - 0.12 * mono_risk
        )
    if kind == "eq":
        return clamp(max(mud_pressure, harsh_pressure, dull_pressure) + 0.18 * crowded_pressure + 0.06 * noise_pressure)
    if kind == "compressor":
        return clamp(0.58 * dynamic_pressure + 0.16 * crowded_pressure + 0.18 * clipping_pressure + 0.06 * low_end_anchor)
    if kind == "limiter":
        return clamp(0.76 * clipping_pressure + 0.18 * dynamic_pressure)
    if kind == "clipper":
        return clamp(0.78 * clipping_pressure + 0.16 * dynamic_pressure + 0.08 * row["median_spectral_flux"])
    if kind == "reverb":
        return clamp(
            0.58 * space_capacity
            + 0.18 * dull_pressure
            - 0.54 * clipping_pressure
            - 0.38 * crowded_pressure
            - 0.14 * noise_pressure
            - 0.12 * mono_risk
        )
    if kind == "delay":
        return clamp(
            0.50 * space_capacity
            + 0.18 * dull_pressure
            - 0.34 * crowded_pressure
            - 0.24 * noise_pressure
            - 0.10 * low_end_anchor
            - 0.10 * mono_risk
        )
    if kind == "deesser":
        return clamp(0.88 * harsh_pressure + 0.12 * row["median_sibilance_norm"])
    if kind == "distortion":
        return clamp(
            0.24 * dull_pressure
            + 0.14 * (1.0 - row["median_spectral_flatness"])
            + 0.10 * space_capacity
            - 0.42 * noise_pressure
            - 0.40 * clipping_pressure
            - 0.12 * crowded_pressure
        )
    return 0.35


def _label_apply_and_scale(rng, row, kind, action_type):
    base_need = _action_need_score(row, kind)
    crowded_pressure = _crowded_pressure(row)
    clipping_pressure = _clipping_pressure(row)
    ops_pressure = _mean(row["count_fx_ops_norm"], row["count_master_ops_norm"])
    scope_match = 0.16 if row["is_master_action"] and kind in MASTER_FRIENDLY_KINDS else 0.0
    scope_match -= 0.16 if row["is_master_action"] and kind in {"pan", "reverb", "delay", "deesser"} else 0.0
    destructive = 1.0 if action_type in DESTRUCTIVE_ACTIONS else 0.0
    ensure_action = 1.0 if action_type in {"ensure_effect", "ensure_master_effect"} else 0.0
    other_action = 1.0 if action_type == "other" else 0.0
    spacey_action = 1.0 if kind in SPACEY_KINDS else 0.0
    low_end_anchor = _low_end_anchor_pressure(row)
    noise_pressure = _noise_pressure(row)
    harsh_pressure = _harsh_pressure(row)
    mono_risk = _mean(1.0 - row["median_phase_corr_norm"], row["median_stereo_imbalance"])
    subtlety_pressure = _mean(row["count_fx_ops_norm"], crowded_pressure, clipping_pressure)
    magnitude_overshoot = max(0.0, row["ai_action_magnitude"] - (0.38 + 1.12 * base_need))

    if destructive:
        action_support = clamp(
            0.16
            + 0.60 * ops_pressure
            + 0.24 * clipping_pressure
            + 0.12 * crowded_pressure
            + (0.14 if kind in SPACEY_KINDS or kind == "distortion" else -0.08)
            - 0.32 * base_need
        )
    elif ensure_action:
        action_support = clamp(0.18 + 0.74 * base_need + 0.18 * (1.0 - ops_pressure))
    elif other_action:
        action_support = clamp(0.12 + 0.44 * base_need - 0.22 * ops_pressure)
    else:
        action_support = base_need

    logit = (
        -2.05
        + 3.45 * action_support
        + 0.86 * row["goal_intensity"]
        + 0.34 * row["strict_execute"]
        + scope_match
        - 0.54 * magnitude_overshoot
        - 0.34 * spacey_action * clipping_pressure
        - 0.22 * spacey_action * subtlety_pressure
        - 0.20 * low_end_anchor * (1.0 if kind == "pan" else 0.0)
        - 0.18 * noise_pressure * (1.0 if kind in {"reverb", "delay", "distortion"} else 0.0)
        - 0.18 * mono_risk * (1.0 if kind in {"pan", "reverb", "delay"} else 0.0)
        + 0.14 * harsh_pressure * (1.0 if kind in {"deesser", "eq"} else 0.0)
        - 0.24 * other_action
        + rng.normal(0.0, 0.14)
    )
    apply_prob = clamp(sigmoid(logit))
    label_apply = 1 if apply_prob >= (0.56 + rng.normal(0.0, 0.03)) else 0

    scale = (
        0.10
        + 1.40 * action_support
        + 0.34 * row["goal_intensity"]
        + 0.12 * row["strict_execute"]
        + 0.10 * scope_match
        - 0.22 * magnitude_overshoot
        - 0.16 * destructive
        - 0.24 * spacey_action * crowded_pressure
        - 0.14 * spacey_action * clipping_pressure
        - 0.12 * low_end_anchor * (1.0 if kind == "pan" else 0.0)
        - 0.12 * noise_pressure * (1.0 if kind in {"reverb", "delay", "distortion"} else 0.0)
        - 0.12 * mono_risk * (1.0 if kind in {"pan", "reverb", "delay"} else 0.0)
        + 0.10 * harsh_pressure * (1.0 if kind in {"deesser", "eq"} else 0.0)
        + rng.normal(0.0, 0.06)
    )
    scale = clamp(scale, 0.04, 3.0)
    if label_apply == 0:
        scale = clamp(scale * jitter(rng, 0.22, 0.06, 0.05, 0.42), 0.02, 0.40)
    return label_apply, scale, apply_prob


def _candidate_model_specs(seed, profile):
    specs = [
        {
            "name": "gb_v1",
            "apply_model": GradientBoostingClassifier(
                random_state=seed,
                learning_rate=0.05,
                n_estimators=220,
                subsample=0.85,
                max_depth=3,
                min_samples_leaf=12,
                max_features="sqrt",
            ),
            "reg_model": GradientBoostingRegressor(
                random_state=seed,
                learning_rate=0.05,
                n_estimators=260,
                subsample=0.85,
                max_depth=3,
                min_samples_leaf=12,
                max_features="sqrt",
            ),
        },
        {
            "name": "gb_v2",
            "apply_model": GradientBoostingClassifier(
                random_state=seed,
                learning_rate=0.04,
                n_estimators=320,
                subsample=0.82,
                max_depth=3,
                min_samples_leaf=10,
                max_features=None,
            ),
            "reg_model": GradientBoostingRegressor(
                random_state=seed,
                learning_rate=0.04,
                n_estimators=340,
                subsample=0.82,
                max_depth=3,
                min_samples_leaf=10,
                max_features=None,
            ),
        },
        {
            "name": "gb_v3",
            "apply_model": GradientBoostingClassifier(
                random_state=seed,
                learning_rate=0.03,
                n_estimators=460,
                subsample=0.80,
                max_depth=3,
                min_samples_leaf=8,
                max_features=None,
            ),
            "reg_model": GradientBoostingRegressor(
                random_state=seed,
                learning_rate=0.03,
                n_estimators=480,
                subsample=0.80,
                max_depth=3,
                min_samples_leaf=8,
                max_features=None,
            ),
        },
        {
            "name": "rf_v1",
            "apply_model": RandomForestClassifier(
                n_estimators=360,
                max_depth=14,
                min_samples_leaf=5,
                max_features="sqrt",
                class_weight="balanced_subsample",
                n_jobs=-1,
                random_state=seed,
            ),
            "reg_model": RandomForestRegressor(
                n_estimators=320,
                max_depth=16,
                min_samples_leaf=4,
                max_features="sqrt",
                n_jobs=-1,
                random_state=seed,
            ),
        },
        {
            "name": "et_v1",
            "apply_model": ExtraTreesClassifier(
                n_estimators=420,
                max_depth=18,
                min_samples_leaf=3,
                max_features="sqrt",
                class_weight="balanced_subsample",
                n_jobs=-1,
                random_state=seed,
            ),
            "reg_model": ExtraTreesRegressor(
                n_estimators=360,
                max_depth=20,
                min_samples_leaf=3,
                max_features="sqrt",
                n_jobs=-1,
                random_state=seed,
            ),
        },
        {
            "name": "et_v2",
            "apply_model": ExtraTreesClassifier(
                n_estimators=520,
                max_depth=24,
                min_samples_leaf=2,
                max_features=None,
                class_weight="balanced_subsample",
                n_jobs=-1,
                random_state=seed,
            ),
            "reg_model": ExtraTreesRegressor(
                n_estimators=460,
                max_depth=26,
                min_samples_leaf=2,
                max_features=None,
                n_jobs=-1,
                random_state=seed,
            ),
        },
    ]
    if profile == "fast":
        allowed = {"gb_v1", "gb_v2", "gb_v3", "et_v1"}
        specs = [spec for spec in specs if spec["name"] in allowed]
    return specs


def _fit_with_optional_sample_weight(model, X, y, sample_weight):
    try:
        model.fit(X, y, sample_weight=sample_weight)
    except TypeError:
        model.fit(X, y)
    return model


def _score_candidate_metrics(metrics):
    roc_auc = float(metrics.get("apply_roc_auc", 0.0))
    accuracy = float(metrics.get("apply_accuracy", 0.0))
    scale_mae = float(metrics.get("scale_mae", 1.0))
    mae_score = max(0.0, 1.0 - min(1.0, scale_mae))
    return 0.58 * roc_auc + 0.24 * accuracy + 0.18 * mae_score


def _train_and_score(dataset_csv, model_dir, seed, candidate_profile):
    df = pd.read_csv(dataset_csv)
    X = df[FEATURE_COLUMNS].astype(float)
    y_apply = df["label_apply"].astype(float).clip(0.0, 1.0).round().astype(int)
    y_scale = df["label_magnitude_scale"].astype(float).clip(0.0, 3.0)
    groups = df["project_id"].astype(str)
    splitter = GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=seed)
    train_idx, val_idx = next(splitter.split(X, y_apply, groups=groups))
    X_train = X.iloc[train_idx]
    X_val = X.iloc[val_idx]
    y_apply_train = y_apply.iloc[train_idx]
    y_apply_val = y_apply.iloc[val_idx]
    y_scale_train = y_scale.iloc[train_idx]
    y_scale_val = y_scale.iloc[val_idx]

    class_counts = y_apply_train.value_counts().to_dict()
    total = float(len(y_apply_train))
    sample_weight = np.array(
        [total / max(1.0, 2.0 * class_counts.get(int(label), 1)) for label in y_apply_train],
        dtype=float,
    )

    reg_train_mask = y_apply_train == 1
    reg_val_mask = y_apply_val == 1
    if reg_train_mask.sum() < 16:
        reg_train_mask = np.ones(len(X_train), dtype=bool)
    if reg_val_mask.sum() < 4:
        reg_val_mask = np.ones(len(X_val), dtype=bool)

    best = None
    candidate_results = []
    for spec in _candidate_model_specs(seed, candidate_profile):
        apply_model = _fit_with_optional_sample_weight(
            spec["apply_model"], X_train, y_apply_train, sample_weight
        )
        reg_model = _fit_with_optional_sample_weight(
            spec["reg_model"],
            X_train[reg_train_mask],
            y_scale_train[reg_train_mask],
            None,
        )

        if hasattr(apply_model, "predict_proba"):
            apply_scores = np.clip(apply_model.predict_proba(X_val)[:, 1], 0.0, 1.0)
        else:
            apply_scores = np.clip(apply_model.predict(X_val), 0.0, 1.0)
        y_apply_pred = apply_model.predict(X_val).astype(int)
        y_scale_pred = np.clip(reg_model.predict(X_val[reg_val_mask]), 0.0, 3.0)

        metrics = {
            "name": spec["name"],
            "apply_accuracy": float(accuracy_score(y_apply_val.astype(int), y_apply_pred)),
            "apply_roc_auc": float(roc_auc_score(y_apply_val, apply_scores)),
            "scale_mae": float(mean_absolute_error(y_scale_val[reg_val_mask], y_scale_pred)),
        }
        metrics["selection_score"] = _score_candidate_metrics(metrics)
        candidate_results.append(metrics)

        if best is None or metrics["selection_score"] > best["metrics"]["selection_score"]:
            best = {
                "spec": spec,
                "apply_model": apply_model,
                "reg_model": reg_model,
                "metrics": metrics,
            }

    model_dir.mkdir(parents=True, exist_ok=True)
    joblib.dump(best["apply_model"], model_dir / "apply_classifier.joblib")
    joblib.dump(best["reg_model"], model_dir / "magnitude_regressor.joblib")

    manifest = {
        "feature_columns": FEATURE_COLUMNS,
        "feature_vector_size": len(FEATURE_COLUMNS),
        "model_family": {
            "apply_classifier": best["apply_model"].__class__.__name__,
            "magnitude_regressor": best["reg_model"].__class__.__name__,
        },
        "model_selection": candidate_results,
        "selected_candidate": best["metrics"]["name"],
    }
    with open(model_dir / "feature_manifest.json", "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2)

    metrics = {
        "apply_accuracy": best["metrics"]["apply_accuracy"],
        "apply_roc_auc": best["metrics"]["apply_roc_auc"],
        "scale_mae": best["metrics"]["scale_mae"],
        "train_rows": int(len(train_idx)),
        "val_rows": int(len(val_idx)),
        "train_groups": int(df.iloc[train_idx]["project_id"].astype(str).nunique()),
        "val_groups": int(df.iloc[val_idx]["project_id"].astype(str).nunique()),
        "apply_rate_train": float(y_apply_train.mean()),
        "apply_rate_val": float(y_apply_val.mean()),
        "split_strategy": "group",
        "split_group_column": "project_id",
        "selected_candidate": best["metrics"]["name"],
        "selection_score": float(best["metrics"]["selection_score"]),
        "candidate_metrics": candidate_results,
    }
    with open(model_dir / "metrics.json", "w", encoding="utf-8") as handle:
        json.dump(metrics, handle, indent=2)
    return metrics


def build_dataset(rows_target, projects, seed):
    rng = np.random.default_rng(seed)
    project_count = max(24, projects)
    rows_per_project = max(20, int(math.ceil(rows_target / project_count)))

    dataset = []
    for project_index in range(project_count):
        plan = _sample_project_plan(rng)
        context = _build_project_context(rng, plan)
        project_id = f"bootstrap_project_{project_index:04d}"
        session_id = f"bootstrap_session_{project_index // 10:03d}"

        for action_index in range(rows_per_project):
            if len(dataset) >= rows_target:
                break
            scope = _choose_scope(rng, plan, context)
            kind, action_type = _choose_kind_and_action(rng, plan, scope, context)
            row = {feature: 0.0 for feature in FEATURE_COLUMNS}
            row.update(context)
            row.update(_scope_values(scope))
            row.update(_kind_values(kind))
            row.update(_action_values(action_type))
            row.update(_op_counts(rng, action_type, scope, plan))
            row["goal_intensity"] = _goal_intensity(rng, plan)
            row["strict_execute"] = 1.0 if rng.random() < (0.76 if scope != "auto" else 0.62) else 0.0
            row["ai_action_magnitude"] = _sample_action_magnitude(
                rng, kind, action_type, plan, context, scope
            )
            row["project_bpm_norm"] = clamp(context["project_bpm_norm"] + rng.normal(0.0, 0.03))

            label_apply, label_scale, apply_prob = _label_apply_and_scale(rng, row, kind, action_type)
            row["label_apply"] = label_apply
            row["label_magnitude_scale"] = label_scale
            row["project_id"] = project_id
            row["session_id"] = session_id
            row["scenario"] = "+".join(plan["issues"])
            row["style_profile"] = plan["style"]
            row["source_profile"] = plan["source"]
            row["arrangement_profile"] = plan["arrangement"]
            row["mix_stage"] = plan["stage"]
            row["sample_action_type"] = action_type
            row["sample_kind"] = kind
            row["sample_apply_probability"] = round(apply_prob, 6)
            row["sample_index_in_project"] = action_index
            dataset.append(row)

        if len(dataset) >= rows_target:
            break

    frame = pd.DataFrame(dataset)
    missing = [column for column in FEATURE_COLUMNS if column not in frame.columns]
    if missing:
        raise SystemExit(f"Bootstrap dataset missing feature columns: {missing}")
    if len(FEATURE_COLUMNS) != EXPECTED_FEATURE_COUNT:
        raise SystemExit(
            f"Feature contract mismatch: expected {EXPECTED_FEATURE_COUNT}, got {len(FEATURE_COLUMNS)}"
        )
    return frame


def run_python(script_path, *args):
    cmd = [sys.executable, str(script_path), *args]
    subprocess.run(cmd, check=True)


def main():
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[2]
    tools_dir = repo_root / "tools" / "ai_mixing"
    out_root = (repo_root / args.out_root).resolve()
    dataset_csv = out_root / "dataset.csv"
    model_dir = out_root / "models"
    onnx_dir = out_root / "onnx"
    model_tag = sanitize_model_tag(args.model_tag)

    out_root.mkdir(parents=True, exist_ok=True)
    frame = build_dataset(args.rows, args.projects, args.seed)
    frame.to_csv(dataset_csv, index=False)

    metrics = _train_and_score(dataset_csv, model_dir, args.seed, args.candidate_profile)
    run_python(tools_dir / "export_onnx.py", "--model-dir", str(model_dir), "--out-dir", str(onnx_dir))

    metadata = {
        "rows": int(len(frame)),
        "projects": int(frame["project_id"].nunique()),
        "sessions": int(frame["session_id"].nunique()),
        "seed": int(args.seed),
        "model_tag": model_tag or None,
        "issue_mix": frame["scenario"].value_counts().head(12).to_dict(),
        "style_mix": frame["style_profile"].value_counts().to_dict(),
        "source_mix": frame["source_profile"].value_counts().to_dict(),
        "arrangement_mix": frame["arrangement_profile"].value_counts().to_dict(),
        "mix_stage_mix": frame["mix_stage"].value_counts().to_dict(),
        "apply_rate": float(frame["label_apply"].mean()),
        "scale_mean": float(frame["label_magnitude_scale"].mean()),
        "note": (
            "Synthetic beta placeholder dataset for learned-magnitude app flow. "
            "Useful for internal beta coverage, not equivalent to producer-trained supervision."
        ),
        "holdout_metrics": metrics,
    }
    with open(out_root / "bootstrap_metadata.json", "w", encoding="utf-8") as handle:
        json.dump(metadata, handle, indent=2)

    if args.copy_assets:
        assets_dir = repo_root / "assets" / "models"
        assets_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(onnx_dir / "mix_apply_classifier.onnx", assets_dir / "mix_apply_classifier.onnx")
        shutil.copy2(onnx_dir / "mix_magnitude_regressor.onnx", assets_dir / "mix_magnitude_regressor.onnx")

    if model_tag:
        tagged_apply = onnx_dir / f"mix_apply_classifier_{model_tag}.onnx"
        tagged_reg = onnx_dir / f"mix_magnitude_regressor_{model_tag}.onnx"
        shutil.copy2(onnx_dir / "mix_apply_classifier.onnx", tagged_apply)
        shutil.copy2(onnx_dir / "mix_magnitude_regressor.onnx", tagged_reg)
        if args.copy_assets:
            assets_dir = repo_root / "assets" / "models"
            shutil.copy2(tagged_apply, assets_dir / tagged_apply.name)
            shutil.copy2(tagged_reg, assets_dir / tagged_reg.name)
        metadata["tagged_files"] = {
            "apply": tagged_apply.name,
            "regressor": tagged_reg.name,
        }
        with open(out_root / "bootstrap_metadata.json", "w", encoding="utf-8") as handle:
            json.dump(metadata, handle, indent=2)

    print(json.dumps(metrics, indent=2))
    print(f"[ok] dataset: {dataset_csv}")
    print(f"[ok] models: {model_dir}")
    print(f"[ok] onnx: {onnx_dir}")
    if args.copy_assets:
        print(f"[ok] copied assets into: {repo_root / 'assets' / 'models'}")
    if model_tag:
        print(f"[ok] archived tagged copies with tag: {model_tag}")


if __name__ == "__main__":
    main()
