#!/usr/bin/env python3
"""Profile deterministic Mixroom V3 contract-6 provider requests offline."""

from __future__ import annotations

import argparse
import functools
import hashlib
import json
import statistics
import sys
import time
from pathlib import Path
from typing import Any, Callable


ROOT = Path(__file__).resolve().parents[2]
PROXY_SRC = ROOT / "backend" / "llm_proxy" / "src"
BASELINE_PATH = Path(__file__).with_name("v3_request_profile_baseline.json")
if str(PROXY_SRC) not in sys.path:
    sys.path.insert(0, str(PROXY_SRC))

from common import v3_server_contract  # noqa: E402
from common.llm_contract import build_openai_responses_request  # noqa: E402


_RESOURCE_IDENTIFIER_ENUM_FIELDS = frozenset(
    {
        "asset_id",
        "automation_target_id",
        "clip_id",
        "effect_id",
        "effect_instance_id",
        "group_id",
        "instrument_id",
        "parameter_id",
        "row_id",
    }
)


def _canonical_json(value: Any) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    )


def _json_bytes(value: Any) -> int:
    return len(_canonical_json(value).encode("utf-8"))


def _wire_json_bytes(value: Any) -> bytes:
    # This intentionally matches common.llm_provider._post_json_request.
    return json.dumps(value).encode("utf-8")


def _transform_schema_for_attribution(
    value: Any,
    *,
    field_name: str = "",
    remove_descriptions: bool = False,
    empty_resource_identifier_enums: bool = False,
) -> Any:
    if isinstance(value, dict):
        transformed: dict[str, Any] = {}
        for key, child in value.items():
            if remove_descriptions and key == "description":
                continue
            if (
                empty_resource_identifier_enums
                and key == "enum"
                and field_name in _RESOURCE_IDENTIFIER_ENUM_FIELDS
                and isinstance(child, list)
            ):
                transformed[key] = []
                continue
            transformed[key] = _transform_schema_for_attribution(
                child,
                field_name=key,
                remove_descriptions=remove_descriptions,
                empty_resource_identifier_enums=empty_resource_identifier_enums,
            )
        return transformed
    if isinstance(value, list):
        return [
            _transform_schema_for_attribution(
                child,
                field_name=field_name,
                remove_descriptions=remove_descriptions,
                empty_resource_identifier_enums=empty_resource_identifier_enums,
            )
            for child in value
        ]
    return value


def _enum_array_occurrence_bytes(value: Any) -> int:
    if isinstance(value, dict):
        return sum(
            _json_bytes(child)
            if key == "enum" and isinstance(child, list)
            else _enum_array_occurrence_bytes(child)
            for key, child in value.items()
        )
    if isinstance(value, list):
        return sum(_enum_array_occurrence_bytes(child) for child in value)
    return 0


def _schema_attribution(tool: dict[str, Any]) -> dict[str, int]:
    tool_bytes = _json_bytes(tool)
    variants = tool["parameters"]["properties"]["commands"]["items"]["anyOf"]
    without_descriptions = _transform_schema_for_attribution(
        tool,
        remove_descriptions=True,
    )
    without_resource_identifier_values = _transform_schema_for_attribution(
        tool,
        empty_resource_identifier_enums=True,
    )
    return {
        # These dimensions intentionally overlap; they are attribution lenses,
        # not additive partitions of the tool schema.
        "command_variant_array_bytes": _json_bytes(variants),
        "description_entry_bytes": tool_bytes - _json_bytes(without_descriptions),
        "enum_array_occurrence_bytes": _enum_array_occurrence_bytes(tool),
        "resource_identifier_enum_value_bytes": (
            tool_bytes - _json_bytes(without_resource_identifier_values)
        ),
    }


def _percentile(values: list[float], percentile: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return 0.0
    index = min(int((len(ordered) - 1) * percentile + 0.999999), len(ordered) - 1)
    return ordered[index]


def _effects() -> list[dict[str, Any]]:
    effect_ids = (
        "EQ 3-Band",
        "EQ Parametric",
        "Compressor",
        "Limiter",
        "Reverb",
        "Delay",
        "Distortion",
        "De-Esser",
        "Clipper",
        "Chorus",
    )
    return [
        {
            "effect_id": effect_id,
            "parameters": [
                {"parameter_id": "Amount", "range": [0.0, 1.0]},
                {"parameter_id": "Mix", "range": [0.0, 1.0]},
            ],
        }
        for effect_id in effect_ids
    ]


def _conversation(turn_count: int, *, padded: bool) -> list[dict[str, str]]:
    padding = " synthetic-context" * 100 if padded else ""
    return [
        {
            "role": "user" if index % 2 == 0 else "assistant",
            "content": f"Synthetic conversation turn {index + 1}.{padding}",
        }
        for index in range(turn_count)
    ]


def _context(
    *,
    row_count: int,
    clip_count: int,
    library_asset_count: int | None = None,
    midi_note_count: int = 0,
    include_library_asset_metadata: bool = False,
) -> dict[str, Any]:
    instrument_ids = [f"synthetic-instrument-{index}" for index in range(1, 5)]
    rows: list[dict[str, Any]] = []
    for index in range(row_count):
        row_id = index + 1
        is_instrument = index % 2 == 1
        rows.append(
            {
                "row_id": row_id,
                "lane_kind": "instrument" if is_instrument else "audio",
                "instrument_id": (
                    instrument_ids[index % len(instrument_ids)]
                    if is_instrument
                    else ""
                ),
                "mix_processing_supported": True,
                "has_usable_signal": True,
                "effects": [{"effect_instance_id": f"synthetic-fx-{row_id}"}],
            }
        )

    clips: list[dict[str, Any]] = []
    midi_clip_indexes = [
        index
        for index in range(clip_count)
        if rows[index % len(rows)]["lane_kind"] == "instrument"
    ]
    if midi_note_count and not midi_clip_indexes:
        raise ValueError("MIDI notes require at least one MIDI clip.")
    notes_per_clip, notes_remainder = (
        divmod(midi_note_count, len(midi_clip_indexes))
        if midi_clip_indexes
        else (0, 0)
    )
    midi_clip_position = {
        clip_index: position
        for position, clip_index in enumerate(midi_clip_indexes)
    }
    for index in range(clip_count):
        row = rows[index % len(rows)]
        is_midi = row["lane_kind"] == "instrument"
        note_count = 0
        if is_midi:
            position = midi_clip_position[index]
            note_count = notes_per_clip + (1 if position < notes_remainder else 0)
        clips.append(
            {
                "clip_id": f"synthetic-clip-{index + 1:04d}",
                "row_id": row["row_id"],
                "kind": "midi" if is_midi else "audio",
                "instrument_id": row["instrument_id"] if is_midi else "",
                "length_beats": 8.0,
                "source_available": True,
                "midi_notes": [
                    {
                        "pitch": 48 + note_index % 24,
                        "start_beat": float(note_index % 16) / 2,
                        "length_beats": 0.5,
                        "velocity": 0.75,
                    }
                    for note_index in range(note_count)
                ],
            }
        )

    groups = [
        {
            "group_id": f"synthetic-group-{index // 2 + 1}",
            "member_row_ids": [index + 1, index + 2],
        }
        for index in range(0, row_count - 1, 2)
    ]
    if library_asset_count is None:
        library_asset_count = min(
            clip_count,
            v3_server_contract.MAX_COLLECTION_ITEMS,
        )
    library_assets = []
    for index in range(library_asset_count):
        asset = {"asset_id": f"synthetic-asset-{index + 1:04d}"}
        if include_library_asset_metadata:
            asset.update(
                {
                    "path": f"Synthetic/Library/asset-{index + 1:04d}.wav",
                    "role": "drums" if index % 2 == 0 else "melodic",
                }
            )
        library_assets.append(asset)

    return {
        "schema_version": "core_context_v3_prototype_1",
        "project": {
            "project_id": "synthetic-project",
            "bpm": 120,
            "row_capacity": {
                "current_rows": row_count,
                "max_rows": row_count + 8,
                "can_create": True,
            },
        },
        "rows": rows,
        "clips": clips,
        "groups": groups,
        "library_assets": library_assets,
        "instruments": instrument_ids,
        "instrument_catalog": [
            {
                "instrument_id": instrument_id,
                "name": f"Synthetic Instrument {index + 1}",
                "playable_pitch_ranges": [{"low": 24, "high": 108}],
            }
            for index, instrument_id in enumerate(instrument_ids)
        ],
        "effects": _effects(),
    }


def _request(
    *,
    row_count: int,
    clip_count: int,
    turn_count: int,
    full_command_surface: bool,
    padded_conversation: bool = False,
    library_asset_count: int | None = None,
    midi_note_count: int = 0,
    include_library_asset_metadata: bool = False,
) -> dict[str, Any]:
    return {
        "request_contract": v3_server_contract.REQUEST_CONTRACT,
        "original_request": "Build a polished synthetic arrangement and mix.",
        "conversation": _conversation(turn_count, padded=padded_conversation),
        "core_context": _context(
            row_count=row_count,
            clip_count=clip_count,
            library_asset_count=library_asset_count,
            midi_note_count=midi_note_count,
            include_library_asset_metadata=include_library_asset_metadata,
        ),
        "plan_schema_version": v3_server_contract.PLAN_SCHEMA_VERSION,
        "supported_command_types": (
            sorted(v3_server_contract.SERVER_COMMAND_TYPES)
            if full_command_surface
            else ["transport.restart"]
        ),
        "resource_refs_enabled": True,
        "project_id": "synthetic-project",
        "prompt_trace_id": "synthetic-profile-trace",
        "analytics_context": {
            "app_version": "profile",
            "platform": "offline",
            "ai_architecture": "v3",
        },
    }


def _build_provider_request(body: dict[str, Any]) -> dict[str, Any]:
    validated = v3_server_contract.validate_context_request(
        body,
        raw_body_bytes=_json_bytes(body),
    )
    return v3_server_contract.build_provider_request(
        validated,
        model="gpt-5.6-luna",
        reasoning_effort="low",
        max_output_tokens=8192,
        prompt_cache_retention="24h",
        store=True,
    )


@functools.lru_cache(maxsize=1)
def _boundary_request() -> dict[str, Any]:
    def candidate(row_count: int) -> dict[str, Any]:
        return _request(
            row_count=row_count,
            clip_count=min(row_count * 4, v3_server_contract.MAX_COLLECTION_ITEMS),
            turn_count=v3_server_contract.MAX_CONVERSATION_TURNS,
            full_command_surface=True,
            padded_conversation=True,
        )

    def is_valid(body: dict[str, Any]) -> bool:
        try:
            _build_provider_request(body)
        except v3_server_contract.V3ContractError as error:
            if error.code not in {
                "v3_capability_context_limit",
                "v3_context_request_limit",
            }:
                raise
            return False
        return True

    lower = 8
    if not is_valid(candidate(lower)):
        raise RuntimeError("No valid boundary profiling request could be built.")
    upper = 16
    while upper <= v3_server_contract.MAX_COLLECTION_ITEMS and is_valid(
        candidate(upper)
    ):
        lower = upper
        upper *= 2
    upper = min(upper, v3_server_contract.MAX_COLLECTION_ITEMS + 1)

    while lower + 1 < upper:
        midpoint = (lower + upper) // 2
        if is_valid(candidate(midpoint)):
            lower = midpoint
        else:
            upper = midpoint
    return candidate(lower)


def scenarios() -> dict[str, dict[str, Any]]:
    return {
        "small": _request(
            row_count=1,
            clip_count=1,
            turn_count=0,
            full_command_surface=False,
        ),
        "medium": _request(
            row_count=8,
            clip_count=16,
            turn_count=6,
            full_command_surface=True,
        ),
        "product_max": _request(
            row_count=32,
            clip_count=128,
            library_asset_count=250,
            midi_note_count=512,
            turn_count=8,
            full_command_surface=True,
            padded_conversation=True,
            include_library_asset_metadata=True,
        ),
        "boundary": _boundary_request(),
    }


def _timed_ms(operation: Callable[[], Any]) -> tuple[Any, float]:
    started_at = time.perf_counter()
    result = operation()
    return result, (time.perf_counter() - started_at) * 1000.0


def profile_scenario(
    name: str,
    body: dict[str, Any],
    *,
    iterations: int,
) -> dict[str, Any]:
    validation_times: list[float] = []
    build_times: list[float] = []
    validated: dict[str, Any] | None = None
    provider_request: dict[str, Any] | None = None
    raw_body_bytes = _json_bytes(body)
    for _ in range(iterations):
        validated, validation_ms = _timed_ms(
            lambda: v3_server_contract.validate_context_request(
                body,
                raw_body_bytes=raw_body_bytes,
            )
        )
        provider_request, build_ms = _timed_ms(
            lambda: v3_server_contract.build_provider_request(
                validated,
                model="gpt-5.6-luna",
                reasoning_effort="low",
                max_output_tokens=8192,
                prompt_cache_retention="24h",
                store=True,
            )
        )
        validation_times.append(validation_ms)
        build_times.append(build_ms)

    assert validated is not None and provider_request is not None
    upstream_request = build_openai_responses_request(provider_request)
    wire_request = _wire_json_bytes(upstream_request)
    tool = provider_request["tools"][0]
    variants = tool["parameters"]["properties"]["commands"]["items"]["anyOf"]
    deterministic = {
        "name": name,
        "client_request_bytes": raw_body_bytes,
        "original_request_bytes": len(validated["original_request"].encode("utf-8")),
        "conversation_bytes": _json_bytes(validated["conversation"]),
        "conversation_turn_count": len(validated["conversation"]),
        "core_context_bytes": _json_bytes(validated["core_context"]),
        "instructions_bytes": len(provider_request["instructions"].encode("utf-8")),
        "messages_bytes": _json_bytes(provider_request["messages"]),
        "tool_schema_bytes": _json_bytes(tool),
        "provider_request_bytes": _json_bytes(provider_request),
        "canonical_upstream_request_bytes": _json_bytes(upstream_request),
        "wire_request_bytes": len(wire_request),
        "effective_command_type_count": len(validated["supported_command_types"]),
        "tool_command_variant_count": len(variants),
        "row_count": len(validated["capability_surface"].rows),
        "clip_count": len(validated["capability_surface"].clips),
        "group_count": len(validated["capability_surface"].groups),
        "library_asset_count": len(
            validated["capability_surface"].library_asset_ids
        ),
        "midi_note_count": sum(
            len(clip.midi_notes)
            for clip in validated["capability_surface"].clips
        ),
        "provider_request_sha256": hashlib.sha256(
            _canonical_json(provider_request).encode("utf-8")
        ).hexdigest(),
        "canonical_upstream_request_sha256": hashlib.sha256(
            _canonical_json(upstream_request).encode("utf-8")
        ).hexdigest(),
        "wire_request_sha256": hashlib.sha256(wire_request).hexdigest(),
        "schema_attribution": _schema_attribution(tool),
    }
    return {
        **deterministic,
        "timing_ms": {
            "iterations": iterations,
            "validation_median": round(statistics.median(validation_times), 3),
            "validation_p95": round(_percentile(validation_times, 0.95), 3),
            "provider_request_build_median": round(
                statistics.median(build_times), 3
            ),
            "provider_request_build_p95": round(
                _percentile(build_times, 0.95), 3
            ),
        },
    }


def deterministic_profile(profile: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in profile.items() if key != "timing_ms"}


def run_profiles(*, iterations: int) -> dict[str, Any]:
    profiles = [
        profile_scenario(name, body, iterations=iterations)
        for name, body in scenarios().items()
    ]
    boundary = next(profile for profile in profiles if profile["name"] == "boundary")
    size_components = {
        "instructions": boundary["instructions_bytes"],
        "messages": boundary["messages_bytes"],
        "tool_schema": boundary["tool_schema_bytes"],
    }
    slowest_local_phase = max(
        (
            ("context_validation", boundary["timing_ms"]["validation_median"]),
            (
                "provider_request_build",
                boundary["timing_ms"]["provider_request_build_median"],
            ),
        ),
        key=lambda item: item[1],
    )[0]
    return {
        "contract_version": v3_server_contract.CONTRACT_VERSION,
        "profiles": profiles,
        "summary": {
            "largest_boundary_component": max(
                size_components,
                key=size_components.get,
            ),
            "slowest_local_non_provider_phase": slowest_local_phase,
        },
    }


def verify_baseline(report: dict[str, Any]) -> None:
    expected = json.loads(BASELINE_PATH.read_text(encoding="utf-8"))
    actual = {
        "contract_version": report["contract_version"],
        "profiles": [deterministic_profile(profile) for profile in report["profiles"]],
    }
    if actual != expected:
        raise SystemExit(
            "V3 request profile differs from the approved baseline. "
            "Review the contract change and update the baseline intentionally."
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iterations", type=int, default=5)
    parser.add_argument(
        "--skip-baseline-check",
        action="store_true",
        help="Print current measurements without comparing deterministic fields.",
    )
    args = parser.parse_args()
    if args.iterations < 1:
        parser.error("--iterations must be at least 1")
    report = run_profiles(iterations=args.iterations)
    if not args.skip_baseline_check:
        verify_baseline(report)
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
