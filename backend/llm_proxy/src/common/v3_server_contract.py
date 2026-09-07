from __future__ import annotations

import copy
import hashlib
import json
import math
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Sequence


REQUEST_CONTRACT = "mixroom_v3_context_v2"
RESPONSE_SCHEMA_VERSION = "v3_plan_response_server_v1"
CONTRACT_VERSION = "mixroom_v3_server_contract_6"

_ASSET_DIRECTORY = Path(__file__).with_name("v3_contract_assets")
_METADATA = json.loads(
    (_ASSET_DIRECTORY / "v3_contract_metadata.json").read_text(encoding="utf-8")
)
PLAN_SCHEMA_VERSION = str(_METADATA["plan_schema_version"])
SERVER_COMMAND_TYPES = frozenset(str(value) for value in _METADATA["command_types"])
RESOURCE_REF_COMMAND_TYPES = frozenset(
    str(value) for value in _METADATA["resource_ref_command_types"]
)

_INSTRUCTIONS = (_ASSET_DIRECTORY / "v3_instructions.txt").read_text(
    encoding="utf-8"
).strip()
_RESOURCE_REF_INSTRUCTIONS = (
    _ASSET_DIRECTORY / "v3_instructions_resource_refs.txt"
).read_text(encoding="utf-8").strip()
_TOOLS = {
    False: json.loads(
        (_ASSET_DIRECTORY / "v3_submit_plan_tool.json").read_text(encoding="utf-8")
    ),
    True: json.loads(
        (_ASSET_DIRECTORY / "v3_submit_plan_tool_resource_refs.json").read_text(
            encoding="utf-8"
        )
    ),
}

_REQUIRED_REQUEST_FIELDS = frozenset(
    {
        "request_contract",
        "original_request",
        "conversation",
        "core_context",
        "plan_schema_version",
        "supported_command_types",
        "resource_refs_enabled",
    }
)
_OPTIONAL_REQUEST_FIELDS = frozenset(
    {"project_id", "prompt_trace_id", "analytics_context"}
)
_ALLOWED_REQUEST_FIELDS = _REQUIRED_REQUEST_FIELDS | _OPTIONAL_REQUEST_FIELDS
_PROHIBITED_AI_FIELDS = frozenset(
    {
        "instructions",
        "prompt",
        "system_prompt",
        "developer_prompt",
        "tools",
        "tool_choice",
        "parallel_tool_calls",
        "model",
        "provider",
        "reasoning",
        "temperature",
        "max_output_tokens",
        "max_tokens",
        "prompt_cache_key",
        "prompt_cache_retention",
        "cache",
        "store",
        "input",
        "messages",
        "request_overrides",
    }
)
_ALLOWED_ANALYTICS_FIELDS = frozenset(
    {"app_version", "platform", "ai_architecture", "subscription_plan"}
)

MAX_REQUEST_BYTES = 180_000
MAX_ORIGINAL_REQUEST_CHARS = 8_000
MAX_CONVERSATION_TURNS = 12
MAX_CONVERSATION_TURN_CHARS = 8_000
MAX_CONVERSATION_CHARS = 32_000
MAX_CORE_CONTEXT_BYTES = 140_000
MAX_CONTEXT_DEPTH = 12
MAX_CONTEXT_NODES = 10_000
MAX_COLLECTION_ITEMS = 512
MAX_CONTEXT_STRING_CHARS = 32_000
MAX_CONTEXT_TOTAL_STRING_CHARS = 120_000
MAX_SUPPORTED_COMMAND_TYPES = 64
MAX_IDENTIFIER_CHARS = 128
MAX_TRACE_ID_CHARS = 64
MAX_EFFECT_CAPABILITIES = 64
MAX_EFFECT_PARAMETERS = 16
MAX_RUNTIME_TOOL_BYTES = 400_000
MAX_ACCEPTED_PROVIDER_PLAN_BYTES = 24_000

_EFFECT_STATE_POLICY_VERSION = "ordered_semantic_effect_chain_v1"
_MIX_SCOPE_POLICY_VERSION = "contained_local_mix_generation_v1"
_PHONE_CLEANUP_CONFLICT_POLICY_VERSION = "phone_cleanup_sound_conflict_v1"
_TYPED_CLIP_STATE_POLICY_VERSION = "ordered_typed_clip_reference_v1"
_GROUP_STATE_POLICY_VERSION = "ordered_group_lifecycle_v1"
_USER_VISIBLE_TEXT_POLICY_VERSION = "current_request_language_anchor_v2"

_PRIVATE_PROMPT_MARKERS = frozenset(
    {
        "original_request_verbatim",
        "recent_conversation_json",
        "core_context_v3_json",
        "semantic_repair_required",
    }
)

_MIX_INTENT_REQUIRED_EFFECT_IDS = {
    "balance": frozenset({"EQ 3-Band", "Compressor", "Limiter"}),
    "clipper": frozenset({"Clipper"}),
    "compressor": frozenset({"Compressor"}),
    "deesser": frozenset({"De-Esser"}),
    "delay": frozenset({"Delay"}),
    "distortion": frozenset({"Distortion"}),
    "eq": frozenset({"EQ 3-Band", "EQ Parametric"}),
    "gain": frozenset(),
    "limiter": frozenset({"Limiter"}),
    "pan": frozenset(),
    "reverb": frozenset({"Reverb"}),
}


class V3ContractError(ValueError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


def _contract_error(code: str, message: str) -> V3ContractError:
    return V3ContractError(code, message)


@dataclass(frozen=True)
class V3ParameterCapability:
    parameter_id: str
    minimum: float
    maximum: float


@dataclass(frozen=True)
class V3EffectCapability:
    effect_id: str
    parameters: tuple[V3ParameterCapability, ...]


@dataclass(frozen=True)
class V3MidiPitchRange:
    low: int
    high: int


@dataclass(frozen=True)
class V3InstrumentCapability:
    instrument_id: str
    playable_pitch_ranges: tuple[V3MidiPitchRange, ...]

    def can_play(self, pitch: int) -> bool:
        if not self.playable_pitch_ranges:
            return 0 <= pitch <= 127
        return any(item.low <= pitch <= item.high for item in self.playable_pitch_ranges)


@dataclass(frozen=True)
class V3RowCapability:
    row_id: int
    lane_kind: str
    instrument_id: str
    effect_instance_ids: tuple[str, ...]
    mix_processing_supported: bool
    has_usable_signal: bool


@dataclass(frozen=True)
class V3MidiNote:
    pitch: int
    start_beat: float
    length_beats: float
    velocity: float


@dataclass(frozen=True)
class V3ClipCapability:
    clip_id: str
    row_id: int
    kind: str
    instrument_id: str
    length_beats: float | None
    source_available: bool | None
    midi_notes: tuple[V3MidiNote, ...]


@dataclass(frozen=True)
class V3GroupCapability:
    group_id: str
    member_row_ids: tuple[int, ...]


@dataclass(frozen=True)
class V3CapabilitySurface:
    effects: tuple[V3EffectCapability, ...]
    instruments: tuple[V3InstrumentCapability, ...]
    selectable_instrument_ids: frozenset[str]
    rows: tuple[V3RowCapability, ...]
    clips: tuple[V3ClipCapability, ...]
    groups: tuple[V3GroupCapability, ...]
    effect_instance_ids: frozenset[str]
    library_asset_ids: frozenset[str]
    current_rows: int
    maximum_rows: int

    @property
    def effect_by_id(self) -> dict[str, V3EffectCapability]:
        return {effect.effect_id: effect for effect in self.effects}

    @property
    def instrument_by_id(self) -> dict[str, V3InstrumentCapability]:
        return {instrument.instrument_id: instrument for instrument in self.instruments}

    @property
    def instrument_ids(self) -> frozenset[str]:
        return self.selectable_instrument_ids

    @property
    def row_by_id(self) -> dict[int, V3RowCapability]:
        return {row.row_id: row for row in self.rows}

    @property
    def row_ids(self) -> frozenset[int]:
        return frozenset(self.row_by_id)

    @property
    def mixable_row_ids(self) -> frozenset[int]:
        return frozenset(
            row.row_id for row in self.rows if row.mix_processing_supported
        )

    @property
    def instrument_row_ids(self) -> frozenset[int]:
        return frozenset(row.row_id for row in self.rows if row.lane_kind == "instrument")

    @property
    def audio_row_ids(self) -> frozenset[int]:
        return frozenset(row.row_id for row in self.rows if row.lane_kind == "audio")

    @property
    def clip_by_id(self) -> dict[str, V3ClipCapability]:
        return {clip.clip_id: clip for clip in self.clips}

    @property
    def clip_ids(self) -> frozenset[str]:
        return frozenset(self.clip_by_id)

    @property
    def midi_clip_ids(self) -> frozenset[str]:
        return frozenset(clip.clip_id for clip in self.clips if clip.kind == "midi")

    @property
    def audio_clip_ids(self) -> frozenset[str]:
        return frozenset(clip.clip_id for clip in self.clips if clip.kind == "audio")

    @property
    def group_ids(self) -> frozenset[str]:
        return frozenset(group.group_id for group in self.groups)

    @property
    def mixable_group_ids(self) -> frozenset[str]:
        mixable_rows = self.mixable_row_ids
        return frozenset(
            group.group_id
            for group in self.groups
            if mixable_rows.intersection(group.member_row_ids)
        )


def _capability_identifier(value: Any, *, field: str) -> str:
    if not isinstance(value, str):
        raise _contract_error("v3_capability_context_invalid", f"'{field}' must be a string.")
    normalized = value.strip()
    if not normalized or len(normalized) > MAX_IDENTIFIER_CHARS:
        raise _contract_error("v3_capability_context_invalid", f"'{field}' is invalid.")
    return normalized


def _capability_list(core_context: Mapping[str, Any], field: str) -> list[Any]:
    value = core_context.get(field, [])
    if not isinstance(value, list):
        raise _contract_error("v3_capability_context_invalid", f"'{field}' must be a list.")
    return value


def _unique_string_capabilities(core_context: Mapping[str, Any], field: str) -> frozenset[str]:
    values = [
        _capability_identifier(value, field=f"{field}[]")
        for value in _capability_list(core_context, field)
    ]
    if len(values) != len(set(values)):
        raise _contract_error("v3_capability_context_duplicate", f"'{field}' contains duplicates.")
    return frozenset(values)


def _optional_finite_number(value: Any, *, field: str) -> float | None:
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise _contract_error("v3_capability_context_invalid", f"'{field}' must be numeric.")
    normalized = float(value)
    if not math.isfinite(normalized):
        raise _contract_error("v3_capability_context_invalid", f"'{field}' must be finite.")
    return normalized


def _optional_bool(value: Any, *, field: str) -> bool | None:
    if value is None:
        return None
    if not isinstance(value, bool):
        raise _contract_error("v3_capability_context_invalid", f"'{field}' must be a boolean.")
    return value


def extract_capability_surface(core_context: Mapping[str, Any]) -> V3CapabilitySurface:
    effects: list[V3EffectCapability] = []
    seen_effect_ids: set[str] = set()
    raw_effects = _capability_list(core_context, "effects")
    if len(raw_effects) > MAX_EFFECT_CAPABILITIES:
        raise _contract_error(
            "v3_capability_context_limit", "The effect capability catalog is too large."
        )
    for index, raw_effect in enumerate(raw_effects):
        if not isinstance(raw_effect, dict):
            raise _contract_error("v3_capability_context_invalid", "'effects[]' must be an object.")
        effect_id = _capability_identifier(
            raw_effect.get("effect_id"), field=f"effects[{index}].effect_id"
        )
        if effect_id in seen_effect_ids:
            raise _contract_error("v3_capability_context_duplicate", "'effects' contains duplicates.")
        seen_effect_ids.add(effect_id)
        raw_parameters = raw_effect.get("parameters", [])
        if not isinstance(raw_parameters, list):
            raise _contract_error(
                "v3_capability_context_invalid", "'effects[].parameters' must be a list."
            )
        if len(raw_parameters) > MAX_EFFECT_PARAMETERS:
            raise _contract_error(
                "v3_capability_context_limit", "An effect exposes too many parameters."
            )
        parameters: list[V3ParameterCapability] = []
        seen_parameter_ids: set[str] = set()
        for parameter_index, raw_parameter in enumerate(raw_parameters):
            if not isinstance(raw_parameter, dict):
                raise _contract_error(
                    "v3_capability_context_invalid", "'effects[].parameters[]' must be an object."
                )
            parameter_id = _capability_identifier(
                raw_parameter.get("parameter_id"),
                field=f"effects[{index}].parameters[{parameter_index}].parameter_id",
            )
            if parameter_id in seen_parameter_ids:
                raise _contract_error(
                    "v3_capability_context_duplicate", "An effect contains duplicate parameters."
                )
            seen_parameter_ids.add(parameter_id)
            raw_range = raw_parameter.get("range")
            if (
                not isinstance(raw_range, list)
                or len(raw_range) != 2
                or any(isinstance(value, bool) or not isinstance(value, (int, float)) for value in raw_range)
            ):
                raise _contract_error(
                    "v3_capability_context_invalid", "An effect parameter range is invalid."
                )
            minimum, maximum = (float(raw_range[0]), float(raw_range[1]))
            if (
                not math.isfinite(minimum)
                or not math.isfinite(maximum)
                or minimum < 0
                or maximum > 1
                or minimum > maximum
            ):
                raise _contract_error(
                    "v3_capability_context_invalid", "An effect parameter range is invalid."
                )
            parameters.append(V3ParameterCapability(parameter_id, minimum, maximum))
        effects.append(V3EffectCapability(effect_id, tuple(parameters)))

    allowed_instrument_ids = _unique_string_capabilities(core_context, "instruments")
    instruments: list[V3InstrumentCapability] = []
    seen_instrument_ids: set[str] = set()
    raw_instrument_catalog = _capability_list(core_context, "instrument_catalog")
    for index, raw_instrument in enumerate(raw_instrument_catalog):
        if not isinstance(raw_instrument, dict):
            raise _contract_error(
                "v3_capability_context_invalid", "'instrument_catalog[]' must be an object."
            )
        instrument_id = _capability_identifier(
            raw_instrument.get("instrument_id"),
            field=f"instrument_catalog[{index}].instrument_id",
        )
        if instrument_id in seen_instrument_ids:
            raise _contract_error(
                "v3_capability_context_duplicate", "'instrument_catalog' contains duplicate IDs."
            )
        seen_instrument_ids.add(instrument_id)
        raw_ranges = raw_instrument.get("playable_pitch_ranges", [])
        if not isinstance(raw_ranges, list):
            raise _contract_error(
                "v3_capability_context_invalid", "An instrument pitch-range list is invalid."
            )
        ranges: list[V3MidiPitchRange] = []
        previous_high = -1
        for raw_range in raw_ranges:
            if not isinstance(raw_range, dict) or set(raw_range) != {"low", "high"}:
                raise _contract_error(
                    "v3_capability_context_invalid", "An instrument pitch range is invalid."
                )
            low = raw_range.get("low")
            high = raw_range.get("high")
            if (
                not isinstance(low, int)
                or isinstance(low, bool)
                or not isinstance(high, int)
                or isinstance(high, bool)
                or low < 0
                or high > 127
                or high < low
                or low <= previous_high
            ):
                raise _contract_error(
                    "v3_capability_context_invalid", "Instrument pitch ranges overlap or are invalid."
                )
            ranges.append(V3MidiPitchRange(low, high))
            previous_high = high
        instruments.append(V3InstrumentCapability(instrument_id, tuple(ranges)))
    rows = _capability_list(core_context, "rows")
    row_ids: set[int] = set()
    effect_instance_ids: set[str] = set()
    typed_rows: list[V3RowCapability] = []
    for row_index, raw_row in enumerate(rows):
        if not isinstance(raw_row, dict):
            raise _contract_error("v3_capability_context_invalid", "'rows[]' must be an object.")
        row_id = raw_row.get("row_id")
        if not isinstance(row_id, int) or isinstance(row_id, bool) or row_id < 0:
            raise _contract_error("v3_capability_context_invalid", "A row ID is invalid.")
        if row_id in row_ids:
            raise _contract_error("v3_capability_context_duplicate", "'rows' contains duplicate IDs.")
        row_ids.add(row_id)
        lane_kind = str(raw_row.get("lane_kind") or "").strip()
        if lane_kind not in {"audio", "instrument"}:
            raise _contract_error("v3_capability_context_invalid", "A row lane kind is invalid.")
        if lane_kind == "instrument":
            # Existing project state can outlive the owner's current selection
            # entitlements. The instrument catalog constrains new selections.
            instrument_id = _capability_identifier(
                raw_row.get("instrument_id"),
                field=f"rows[{row_index}].instrument_id",
            )
        else:
            instrument_id = str(raw_row.get("instrument_id") or "").strip()
        if lane_kind == "audio" and instrument_id:
            raise _contract_error(
                "v3_capability_context_invalid", "An audio row cannot declare an instrument."
            )
        raw_instances = raw_row.get("effects", [])
        if not isinstance(raw_instances, list):
            raise _contract_error("v3_capability_context_invalid", "A row effect list is invalid.")
        row_effect_instance_ids: list[str] = []
        for raw_instance in raw_instances:
            if not isinstance(raw_instance, dict):
                raise _contract_error("v3_capability_context_invalid", "A row effect is invalid.")
            instance_id = _capability_identifier(
                raw_instance.get("effect_instance_id"), field="effect_instance_id"
            )
            if instance_id in effect_instance_ids:
                raise _contract_error(
                    "v3_capability_context_duplicate", "Effect instance IDs must be unique."
                )
            effect_instance_ids.add(instance_id)
            row_effect_instance_ids.append(instance_id)
        mix_processing_supported = raw_row.get("mix_processing_supported", False)
        has_usable_signal = raw_row.get("has_usable_signal", False)
        if not isinstance(mix_processing_supported, bool) or not isinstance(has_usable_signal, bool):
            raise _contract_error(
                "v3_capability_context_invalid", f"Row {row_index} readiness flags are invalid."
            )
        typed_rows.append(
            V3RowCapability(
                row_id=row_id,
                lane_kind=lane_kind,
                instrument_id=instrument_id,
                effect_instance_ids=tuple(row_effect_instance_ids),
                mix_processing_supported=mix_processing_supported,
                has_usable_signal=has_usable_signal,
            )
        )

    existing_instrument_ids = {
        row.instrument_id for row in typed_rows if row.lane_kind == "instrument"
    }
    if not set(allowed_instrument_ids).issubset(seen_instrument_ids):
        raise _contract_error(
            "v3_capability_context_invalid",
            "The instrument catalog must describe every selectable instrument.",
        )
    if not seen_instrument_ids.issubset(
        set(allowed_instrument_ids) | existing_instrument_ids
    ):
        raise _contract_error(
            "v3_capability_context_invalid",
            "The instrument catalog contains unrelated instrument state.",
        )
    for instrument_id in sorted(existing_instrument_ids - seen_instrument_ids):
        instruments.append(V3InstrumentCapability(instrument_id, ()))

    clip_ids: set[str] = set()
    typed_clips: list[V3ClipCapability] = []
    for raw_clip in _capability_list(core_context, "clips"):
        if not isinstance(raw_clip, dict):
            raise _contract_error("v3_capability_context_invalid", "'clips[]' must be an object.")
        clip_id = _capability_identifier(raw_clip.get("clip_id"), field="clip_id")
        if clip_id in clip_ids:
            raise _contract_error("v3_capability_context_duplicate", "'clips' contains duplicate IDs.")
        clip_ids.add(clip_id)
        clip_row_id = raw_clip.get("row_id")
        if (
            not isinstance(clip_row_id, int)
            or isinstance(clip_row_id, bool)
            or clip_row_id < 0
        ):
            raise _contract_error("v3_capability_context_invalid", "A clip row ID is invalid.")
        if clip_row_id not in row_ids:
            raise _contract_error("v3_capability_context_invalid", "A clip references an unknown row.")
        row = next(item for item in typed_rows if item.row_id == clip_row_id)
        kind = str(raw_clip.get("kind") or "").strip()
        if kind not in {"audio", "midi"}:
            raise _contract_error("v3_capability_context_invalid", "A clip kind is invalid.")
        if (kind == "midi") != (row.lane_kind == "instrument"):
            raise _contract_error(
                "v3_capability_context_invalid", "A clip kind does not match its row lane."
            )
        instrument_id = str(raw_clip.get("instrument_id") or "").strip()
        if kind == "midi":
            if instrument_id:
                instrument_id = _capability_identifier(
                    raw_clip.get("instrument_id"), field="clips[].instrument_id"
                )
            else:
                instrument_id = row.instrument_id
            if instrument_id != row.instrument_id:
                raise _contract_error(
                    "v3_capability_context_invalid",
                    "A MIDI clip instrument is inconsistent with its row.",
                )
        elif instrument_id:
            raise _contract_error(
                "v3_capability_context_invalid", "An audio clip cannot declare an instrument."
            )
        length_beats = _optional_finite_number(
            raw_clip.get("length_beats"), field="clips[].length_beats"
        )
        if length_beats is not None and length_beats < 0:
            raise _contract_error(
                "v3_capability_context_invalid", "A clip length cannot be negative."
            )
        source_available = _optional_bool(
            raw_clip.get("source_available"), field="clips[].source_available"
        )
        raw_midi_notes = raw_clip.get("midi_notes", [])
        if not isinstance(raw_midi_notes, list):
            raise _contract_error("v3_capability_context_invalid", "A MIDI note list is invalid.")
        midi_notes: list[V3MidiNote] = []
        if kind == "audio" and raw_midi_notes:
            raise _contract_error("v3_capability_context_invalid", "An audio clip cannot contain MIDI notes.")
        for raw_note in raw_midi_notes:
            if not isinstance(raw_note, dict):
                raise _contract_error("v3_capability_context_invalid", "A MIDI note is invalid.")
            pitch = raw_note.get("pitch")
            start_beat = _optional_finite_number(
                raw_note.get("start_beat"), field="clips[].midi_notes[].start_beat"
            )
            note_length = _optional_finite_number(
                raw_note.get("length_beats"), field="clips[].midi_notes[].length_beats"
            )
            velocity = _optional_finite_number(
                raw_note.get("velocity"), field="clips[].midi_notes[].velocity"
            )
            if (
                not isinstance(pitch, int)
                or isinstance(pitch, bool)
                or pitch < 0
                or pitch > 127
                or start_beat is None
                or start_beat < 0
                or note_length is None
                or note_length <= 0
                or velocity is None
                or velocity < 0
                or velocity > 1
            ):
                raise _contract_error("v3_capability_context_invalid", "A MIDI note is invalid.")
            midi_notes.append(V3MidiNote(pitch, start_beat, note_length, velocity))
        typed_clips.append(
            V3ClipCapability(
                clip_id=clip_id,
                row_id=clip_row_id,
                kind=kind,
                instrument_id=instrument_id,
                length_beats=length_beats,
                source_available=source_available,
                midi_notes=tuple(midi_notes),
            )
        )

    group_ids: set[str] = set()
    typed_groups: list[V3GroupCapability] = []
    grouped_row_ids: set[int] = set()
    for raw_group in _capability_list(core_context, "groups"):
        if not isinstance(raw_group, dict):
            raise _contract_error("v3_capability_context_invalid", "'groups[]' must be an object.")
        group_id = _capability_identifier(raw_group.get("group_id"), field="group_id")
        if group_id in group_ids:
            raise _contract_error("v3_capability_context_duplicate", "'groups' contains duplicate IDs.")
        group_ids.add(group_id)
        raw_member_ids = raw_group.get("member_row_ids", [])
        if (
            not isinstance(raw_member_ids, list)
            or len(raw_member_ids) < 2
            or any(
                not isinstance(row_id, int)
                or isinstance(row_id, bool)
                or row_id not in row_ids
                for row_id in raw_member_ids
            )
            or len(raw_member_ids) != len(set(raw_member_ids))
            or grouped_row_ids.intersection(raw_member_ids)
        ):
            raise _contract_error("v3_capability_context_invalid", "A group membership is invalid.")
        grouped_row_ids.update(raw_member_ids)
        typed_groups.append(V3GroupCapability(group_id, tuple(raw_member_ids)))

    library_asset_ids: set[str] = set()
    for raw_asset in _capability_list(core_context, "library_assets"):
        if not isinstance(raw_asset, dict):
            raise _contract_error(
                "v3_capability_context_invalid", "'library_assets[]' must be an object."
            )
        asset_id = _capability_identifier(raw_asset.get("asset_id"), field="asset_id")
        if asset_id in library_asset_ids:
            raise _contract_error(
                "v3_capability_context_duplicate", "'library_assets' contains duplicate IDs."
            )
        library_asset_ids.add(asset_id)

    project = core_context.get("project", {})
    if not isinstance(project, dict):
        raise _contract_error("v3_capability_context_invalid", "'project' must be an object.")
    row_capacity = project.get("row_capacity")
    if row_capacity is None:
        current_rows = len(row_ids)
        maximum_rows = current_rows
    else:
        if not isinstance(row_capacity, dict):
            raise _contract_error("v3_capability_context_invalid", "'row_capacity' must be an object.")
        current_rows = row_capacity.get("current_rows")
        maximum_rows = row_capacity.get("max_rows")
        can_create = row_capacity.get("can_create")
        if (
            not isinstance(current_rows, int)
            or isinstance(current_rows, bool)
            or not isinstance(maximum_rows, int)
            or isinstance(maximum_rows, bool)
            or current_rows != len(row_ids)
            or current_rows < 0
            or maximum_rows < 0
            or can_create is not (current_rows < maximum_rows)
        ):
            raise _contract_error("v3_capability_context_invalid", "'row_capacity' is inconsistent.")

    return V3CapabilitySurface(
        effects=tuple(effects),
        instruments=tuple(instruments),
        selectable_instrument_ids=allowed_instrument_ids,
        rows=tuple(typed_rows),
        clips=tuple(typed_clips),
        groups=tuple(typed_groups),
        effect_instance_ids=frozenset(effect_instance_ids),
        library_asset_ids=frozenset(library_asset_ids),
        current_rows=current_rows,
        maximum_rows=maximum_rows,
    )


def _canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def _bounded_string(value: Any, *, field: str, maximum: int, allow_empty: bool = False) -> str:
    if not isinstance(value, str):
        raise _contract_error("invalid_v3_context_request", f"'{field}' must be a string.")
    normalized = value.strip()
    if not allow_empty and not normalized:
        raise _contract_error("invalid_v3_context_request", f"'{field}' must not be empty.")
    if len(value) > maximum:
        raise _contract_error("v3_context_request_limit", f"'{field}' exceeds its size limit.")
    return normalized


def _validate_context_value(value: Any) -> None:
    state = {"nodes": 0, "string_chars": 0}

    def visit(current: Any, depth: int) -> None:
        state["nodes"] += 1
        if state["nodes"] > MAX_CONTEXT_NODES or depth > MAX_CONTEXT_DEPTH:
            raise _contract_error("v3_context_request_limit", "'core_context' is too complex.")
        if current is None or isinstance(current, bool):
            return
        if isinstance(current, (int, float)) and not isinstance(current, bool):
            if isinstance(current, float) and not math.isfinite(current):
                raise _contract_error("invalid_v3_context_request", "'core_context' contains a non-finite number.")
            return
        if isinstance(current, str):
            if len(current) > MAX_CONTEXT_STRING_CHARS:
                raise _contract_error("v3_context_request_limit", "'core_context' contains an oversized string.")
            state["string_chars"] += len(current)
            if state["string_chars"] > MAX_CONTEXT_TOTAL_STRING_CHARS:
                raise _contract_error("v3_context_request_limit", "'core_context' contains too much text.")
            return
        if isinstance(current, list):
            if len(current) > MAX_COLLECTION_ITEMS:
                raise _contract_error("v3_context_request_limit", "'core_context' contains an oversized list.")
            for item in current:
                visit(item, depth + 1)
            return
        if isinstance(current, dict):
            if len(current) > MAX_COLLECTION_ITEMS:
                raise _contract_error("v3_context_request_limit", "'core_context' contains an oversized object.")
            for key, item in current.items():
                if not isinstance(key, str) or not key or len(key) > MAX_IDENTIFIER_CHARS:
                    raise _contract_error("invalid_v3_context_request", "'core_context' contains an invalid key.")
                visit(item, depth + 1)
            return
        raise _contract_error("invalid_v3_context_request", "'core_context' contains an unsupported value.")

    visit(value, 0)


def _validate_conversation(value: Any) -> list[dict[str, str]]:
    if not isinstance(value, list):
        raise _contract_error("invalid_v3_context_request", "'conversation' must be a list.")
    if len(value) > MAX_CONVERSATION_TURNS:
        raise _contract_error("v3_context_request_limit", "'conversation' has too many turns.")
    result: list[dict[str, str]] = []
    total_chars = 0
    for item in value:
        if not isinstance(item, dict) or set(item) != {"role", "content"}:
            raise _contract_error("invalid_v3_context_request", "Each conversation turn must contain only role and content.")
        role = str(item.get("role") or "").strip()
        if role not in {"user", "assistant"}:
            raise _contract_error("invalid_v3_context_request", "Conversation roles must be user or assistant.")
        content = _bounded_string(
            item.get("content"),
            field="conversation.content",
            maximum=MAX_CONVERSATION_TURN_CHARS,
        )
        total_chars += len(content)
        if total_chars > MAX_CONVERSATION_CHARS:
            raise _contract_error("v3_context_request_limit", "'conversation' exceeds its text limit.")
        result.append({"role": role, "content": content})
    return result


def validate_context_request(body: Mapping[str, Any], *, raw_body_bytes: int) -> dict[str, Any]:
    if raw_body_bytes > MAX_REQUEST_BYTES:
        raise _contract_error("v3_context_request_limit", "V3 context request is too large.")
    actual_fields = set(body)
    prohibited = actual_fields & _PROHIBITED_AI_FIELDS
    if prohibited:
        raise _contract_error(
            "v3_client_ai_configuration_forbidden",
            "Client-provided AI configuration is not allowed for this request contract.",
        )
    unknown = actual_fields - _ALLOWED_REQUEST_FIELDS
    if unknown:
        raise _contract_error("v3_context_unknown_fields", "V3 context request contains unknown fields.")
    missing = _REQUIRED_REQUEST_FIELDS - actual_fields
    if missing:
        raise _contract_error("v3_context_missing_fields", "V3 context request is missing required fields.")
    if body.get("request_contract") != REQUEST_CONTRACT:
        raise _contract_error("v3_request_contract_unsupported", "Unsupported V3 request contract.")
    if body.get("plan_schema_version") != PLAN_SCHEMA_VERSION:
        raise _contract_error("v3_plan_schema_unsupported", "Unsupported V3 plan schema version.")

    original_request = _bounded_string(
        body.get("original_request"),
        field="original_request",
        maximum=MAX_ORIGINAL_REQUEST_CHARS,
    )
    conversation = _validate_conversation(body.get("conversation"))
    core_context = body.get("core_context")
    if not isinstance(core_context, dict):
        raise _contract_error("invalid_v3_context_request", "'core_context' must be an object.")
    _validate_context_value(core_context)
    if len(_canonical_json(core_context).encode("utf-8")) > MAX_CORE_CONTEXT_BYTES:
        raise _contract_error("v3_context_request_limit", "'core_context' exceeds its size limit.")

    raw_command_types = body.get("supported_command_types")
    if not isinstance(raw_command_types, list) or not raw_command_types:
        raise _contract_error("invalid_v3_context_request", "'supported_command_types' must be a non-empty list.")
    if len(raw_command_types) > MAX_SUPPORTED_COMMAND_TYPES:
        raise _contract_error("v3_context_request_limit", "Too many supported command types were supplied.")
    if any(not isinstance(value, str) or not value.strip() for value in raw_command_types):
        raise _contract_error("invalid_v3_context_request", "Supported command types must be non-empty strings.")
    declared_types = {value.strip() for value in raw_command_types}
    effective_types = frozenset(declared_types & SERVER_COMMAND_TYPES)
    if not effective_types:
        raise _contract_error("v3_command_surface_empty", "No mutually supported V3 commands were supplied.")

    resource_refs_enabled = body.get("resource_refs_enabled")
    if not isinstance(resource_refs_enabled, bool):
        raise _contract_error("invalid_v3_context_request", "'resource_refs_enabled' must be a boolean.")

    analytics_context = body.get("analytics_context", {})
    if not isinstance(analytics_context, dict) or set(analytics_context) - _ALLOWED_ANALYTICS_FIELDS:
        raise _contract_error("invalid_v3_context_request", "'analytics_context' contains unsupported fields.")
    normalized_analytics: dict[str, str] = {}
    for key, value in analytics_context.items():
        normalized_analytics[key] = _bounded_string(
            value,
            field=f"analytics_context.{key}",
            maximum=128,
            allow_empty=True,
        )

    project_id = _bounded_string(
        body.get("project_id", ""), field="project_id", maximum=MAX_IDENTIFIER_CHARS, allow_empty=True
    )
    prompt_trace_id = _bounded_string(
        body.get("prompt_trace_id", ""), field="prompt_trace_id", maximum=MAX_TRACE_ID_CHARS, allow_empty=True
    )
    capability_surface = extract_capability_surface(core_context)
    return {
        "original_request": original_request,
        "conversation": conversation,
        "core_context": copy.deepcopy(core_context),
        "supported_command_types": effective_types,
        "resource_refs_enabled": resource_refs_enabled,
        "project_id": project_id,
        "prompt_trace_id": prompt_trace_id,
        "analytics_context": normalized_analytics,
        "capability_surface": capability_surface,
    }


def _command_type_for_variant(variant: Mapping[str, Any]) -> str:
    values = (
        variant.get("properties", {}).get("type", {}).get("enum", [])
        if isinstance(variant.get("properties"), dict)
        else []
    )
    return str(values[0]) if isinstance(values, list) and len(values) == 1 else ""


def _constrain_identifier_properties(
    value: Any, capability_surface: V3CapabilitySurface
) -> None:
    identifiers: dict[str, Sequence[Any]] = {
        "instrument_id": sorted(capability_surface.instrument_ids),
        "row_id": sorted(capability_surface.row_ids),
        "clip_id": sorted(capability_surface.clip_ids),
        "effect_instance_id": sorted(capability_surface.effect_instance_ids),
        "group_id": sorted(capability_surface.group_ids),
        "asset_id": sorted(capability_surface.library_asset_ids),
    }
    if isinstance(value, list):
        for child in value:
            _constrain_identifier_properties(child, capability_surface)
        return
    if not isinstance(value, dict):
        return
    properties = value.get("properties")
    if isinstance(properties, dict):
        for name, allowed_values in identifiers.items():
            schema = properties.get(name)
            if allowed_values and isinstance(schema, dict):
                schema.setdefault("enum", list(allowed_values))
        row_ids_schema = properties.get("row_ids")
        if capability_surface.row_ids and isinstance(row_ids_schema, dict):
            items = row_ids_schema.get("items")
            if isinstance(items, dict):
                items["enum"] = sorted(capability_surface.row_ids)
    for child in value.values():
        _constrain_identifier_properties(child, capability_surface)


def _prune_unavailable_identifier_schemas(
    schema: Any, capability_surface: V3CapabilitySurface
) -> bool:
    """Prune request-specific schema alternatives that require absent stable IDs.

    Returns False when the schema itself cannot be satisfied. Typed resource-reference
    alternatives do not contain stable-ID properties, so they remain available for
    legitimate create-then-act plans.
    """

    if not isinstance(schema, dict):
        return True

    identifiers: dict[str, Sequence[Any]] = {
        "instrument_id": capability_surface.instrument_ids,
        "row_id": capability_surface.row_ids,
        "clip_id": capability_surface.clip_ids,
        "effect_instance_id": capability_surface.effect_instance_ids,
        "group_id": capability_surface.group_ids,
        "asset_id": capability_surface.library_asset_ids,
        "row_ids": capability_surface.row_ids,
    }
    properties = schema.get("properties")
    required = schema.get("required")
    required_names = set(required) if isinstance(required, list) else set()
    if isinstance(properties, dict):
        for name, allowed_values in identifiers.items():
            if name in required_names and name in properties and not allowed_values:
                return False

    for keyword in ("anyOf", "oneOf"):
        alternatives = schema.get(keyword)
        if not isinstance(alternatives, list):
            continue
        retained = [
            alternative
            for alternative in alternatives
            if _prune_unavailable_identifier_schemas(
                alternative, capability_surface
            )
        ]
        if not retained:
            return False
        schema[keyword] = retained

    if isinstance(properties, dict):
        for name in list(properties):
            property_schema = properties[name]
            if _prune_unavailable_identifier_schemas(
                property_schema, capability_surface
            ):
                continue
            if name in required_names:
                return False
            del properties[name]

    items = schema.get("items")
    if isinstance(items, dict) and not _prune_unavailable_identifier_schemas(
        items, capability_surface
    ):
        return False
    return True


def _set_property_enum(value: Any, property_name: str, allowed_values: Sequence[Any]) -> None:
    if isinstance(value, list):
        for child in value:
            _set_property_enum(child, property_name, allowed_values)
        return
    if not isinstance(value, dict):
        return
    properties = value.get("properties")
    if isinstance(properties, dict) and isinstance(properties.get(property_name), dict):
        properties[property_name]["enum"] = list(allowed_values)
    for child in value.values():
        _set_property_enum(child, property_name, allowed_values)


_MIDI_CLIP_COMMANDS = frozenset(
    {"midi.replace_notes", "midi.append_notes", "midi.chop_notes", "midi.transpose"}
)
_AUDIO_CLIP_COMMANDS = frozenset(
    {
        "clip.trim_to_range",
        "clip.glue",
        "clip.separate_stems",
        "clip.convert_to_midi",
        "clip.set_pitch_semitones",
        "clip.adjust_pitch_semitones",
        "clip.set_timeline_length_beats",
        "clip.scale_timeline_length",
        "clip.set_source_tempo_bpm",
        "clip.set_tempo_follow_mode",
        "clip.align_tempo_to_project",
        "clip.trim_silence",
        "clip.align_first_sound",
        "sample.replace",
        "project.set_tempo_from_clip",
    }
)


def _constrain_typed_command_targets(
    variant: dict[str, Any],
    capability_surface: V3CapabilitySurface,
    *,
    resource_refs_enabled: bool,
) -> bool:
    command_type = _command_type_for_variant(variant)
    if command_type == "row.set_instrument":
        if not capability_surface.instrument_row_ids:
            return False
        _set_property_enum(variant, "row_id", sorted(capability_surface.instrument_row_ids))
    elif command_type in _MIDI_CLIP_COMMANDS:
        if capability_surface.midi_clip_ids:
            _set_property_enum(
                variant, "clip_id", sorted(capability_surface.midi_clip_ids)
            )
        elif not resource_refs_enabled:
            return False
    elif command_type in _AUDIO_CLIP_COMMANDS:
        if capability_surface.audio_clip_ids:
            _set_property_enum(
                variant, "clip_id", sorted(capability_surface.audio_clip_ids)
            )
        elif not resource_refs_enabled:
            return False
    return True


def _reachable_clip_kinds(
    variants: Sequence[Mapping[str, Any]],
    capability_surface: V3CapabilitySurface,
) -> frozenset[str]:
    available_types = {_command_type_for_variant(variant) for variant in variants}
    kinds = {clip.kind for clip in capability_surface.clips}
    if "sample.place" in available_types:
        kinds.add("audio")
    if "midi.create_clip" in available_types:
        kinds.add("midi")
    if "audio" in kinds and "clip.convert_to_midi" in available_types:
        kinds.add("midi")
    return frozenset(kinds)


def _effect_command_variants(
    base_variant: Mapping[str, Any], capability_surface: V3CapabilitySurface
) -> list[dict[str, Any]]:
    base_arguments = base_variant.get("properties", {}).get("arguments", {})
    target_variants = base_arguments.get("anyOf", [])
    if not isinstance(target_variants, list):
        raise _contract_error(
            "v3_server_contract_invalid", "The effect command schema is invalid."
        )
    constrained_arguments: list[dict[str, Any]] = []
    for effect in capability_surface.effects:
        for raw_target_variant in target_variants:
            target_variant = copy.deepcopy(raw_target_variant)
            properties = target_variant.get("properties", {})
            effect_schema = properties.get("effect_id")
            parameters_schema = properties.get("parameters")
            if not isinstance(effect_schema, dict) or not isinstance(parameters_schema, dict):
                raise _contract_error(
                    "v3_server_contract_invalid", "The effect command schema is invalid."
                )
            effect_schema.pop("minLength", None)
            effect_schema["enum"] = [effect.effect_id]
            parameters_schema["maxItems"] = min(
                int(parameters_schema.get("maxItems") or 16), len(effect.parameters)
            )
            if effect.parameters:
                item_template = parameters_schema.get("items")
                if not isinstance(item_template, dict):
                    raise _contract_error(
                        "v3_server_contract_invalid", "The effect parameter schema is invalid."
                    )
                item_variants: list[dict[str, Any]] = []
                for parameter in effect.parameters:
                    item_variant = copy.deepcopy(item_template)
                    item_properties = item_variant.get("properties", {})
                    parameter_schema = item_properties.get("parameter_id")
                    value_schema = item_properties.get("value")
                    if not isinstance(parameter_schema, dict) or not isinstance(value_schema, dict):
                        raise _contract_error(
                            "v3_server_contract_invalid", "The effect parameter schema is invalid."
                        )
                    parameter_schema.pop("minLength", None)
                    parameter_schema["enum"] = [parameter.parameter_id]
                    value_schema["minimum"] = parameter.minimum
                    value_schema["maximum"] = parameter.maximum
                    item_variants.append(item_variant)
                parameters_schema["items"] = {"anyOf": item_variants}
            constrained_arguments.append(target_variant)
    if not constrained_arguments:
        return []
    variant = copy.deepcopy(dict(base_variant))
    variant["properties"]["arguments"]["anyOf"] = constrained_arguments
    return [variant]


def _available_mix_intent_kinds(
    capability_surface: V3CapabilitySurface,
) -> frozenset[str]:
    available_effect_ids = frozenset(capability_surface.effect_by_id)
    return frozenset(
        intent_kind
        for intent_kind, required_effect_ids in _MIX_INTENT_REQUIRED_EFFECT_IDS.items()
        if required_effect_ids.issubset(available_effect_ids)
    )


def _constrain_mix_goal_intents(
    variant: dict[str, Any], capability_surface: V3CapabilitySurface
) -> None:
    try:
        kind_schema = variant["properties"]["arguments"]["properties"]["intents"]
        kind_schema = kind_schema["items"]["properties"]["kind"]
    except (KeyError, TypeError) as error:
        raise _contract_error(
            "v3_server_contract_invalid", "The mix goal schema is invalid."
        ) from error
    if not isinstance(kind_schema, dict):
        raise _contract_error(
            "v3_server_contract_invalid", "The mix goal schema is invalid."
        )
    kind_schema["enum"] = sorted(_available_mix_intent_kinds(capability_surface))


def _constrain_mix_goal_targets(
    variant: dict[str, Any], capability_surface: V3CapabilitySurface
) -> None:
    try:
        target_variants = variant["properties"]["arguments"]["properties"]["target"][
            "anyOf"
        ]
    except (KeyError, TypeError) as error:
        raise _contract_error(
            "v3_server_contract_invalid", "The mix goal target schema is invalid."
        ) from error
    if not isinstance(target_variants, list):
        raise _contract_error(
            "v3_server_contract_invalid", "The mix goal target schema is invalid."
        )

    constrained: list[dict[str, Any]] = []
    for raw_target in target_variants:
        if not isinstance(raw_target, dict):
            raise _contract_error(
                "v3_server_contract_invalid", "The mix goal target schema is invalid."
            )
        target = copy.deepcopy(raw_target)
        properties = target.get("properties")
        if not isinstance(properties, dict):
            raise _contract_error(
                "v3_server_contract_invalid", "The mix goal target schema is invalid."
            )
        if "row_id" in properties:
            if not capability_surface.mixable_row_ids:
                continue
            properties["row_id"]["enum"] = sorted(capability_surface.mixable_row_ids)
        elif "group_id" in properties:
            if not capability_surface.mixable_group_ids:
                continue
            properties["group_id"]["enum"] = sorted(
                capability_surface.mixable_group_ids
            )
        constrained.append(target)
    if not constrained:
        raise _contract_error(
            "v3_command_surface_empty", "No mix target is available in this project."
        )
    variant["properties"]["arguments"]["properties"]["target"]["anyOf"] = constrained


def build_submit_plan_tool(
    *,
    command_types: Sequence[str],
    resource_refs_enabled: bool,
    capability_surface: V3CapabilitySurface,
) -> dict[str, Any]:
    effective_types = frozenset(command_types) & SERVER_COMMAND_TYPES
    if not effective_types:
        raise _contract_error("v3_command_surface_empty", "The effective V3 command surface is empty.")
    tool = copy.deepcopy(_TOOLS[resource_refs_enabled])
    command_items = tool["parameters"]["properties"]["commands"]["items"]
    variants: list[dict[str, Any]] = []
    for variant in command_items["anyOf"]:
        command_type = _command_type_for_variant(variant)
        if command_type not in effective_types:
            continue
        if command_type == "effect.ensure_configured":
            for effect_variant in _effect_command_variants(
                variant, capability_surface
            ):
                if _prune_unavailable_identifier_schemas(
                    effect_variant, capability_surface
                ):
                    variants.append(effect_variant)
        else:
            constrained_variant = copy.deepcopy(variant)
            if command_type == "mix.apply_goal":
                _constrain_mix_goal_intents(constrained_variant, capability_surface)
                _constrain_mix_goal_targets(constrained_variant, capability_surface)
            if _constrain_typed_command_targets(
                constrained_variant,
                capability_surface,
                resource_refs_enabled=resource_refs_enabled,
            ) and _prune_unavailable_identifier_schemas(
                constrained_variant, capability_surface
            ):
                variants.append(constrained_variant)
    if not variants:
        raise _contract_error(
            "v3_command_surface_empty", "No command is available in the current capability surface."
        )
    if resource_refs_enabled:
        reachable_clip_kinds = _reachable_clip_kinds(variants, capability_surface)
        variants = [
            variant
            for variant in variants
            if _command_type_for_variant(variant) not in _MIDI_CLIP_COMMANDS
            or "midi" in reachable_clip_kinds
        ]
        variants = [
            variant
            for variant in variants
            if _command_type_for_variant(variant) not in _AUDIO_CLIP_COMMANDS
            or "audio" in reachable_clip_kinds
        ]
        if not variants:
            raise _contract_error(
                "v3_command_surface_empty",
                "No command is available in the current capability surface.",
            )
    command_items["anyOf"] = variants
    _constrain_identifier_properties(tool, capability_surface)
    if len(_canonical_json(tool).encode("utf-8")) > MAX_RUNTIME_TOOL_BYTES:
        raise _contract_error(
            "v3_capability_context_limit", "The runtime capability schema is too large."
        )
    return tool


def build_provider_request(
    request: Mapping[str, Any],
    *,
    model: str,
    reasoning_effort: str,
    max_output_tokens: int = 8192,
    prompt_cache_retention: str = "24h",
    store: bool = True,
) -> dict[str, Any]:
    bounded_output_tokens = max(1, min(int(max_output_tokens), 8192))
    resource_refs_enabled = request["resource_refs_enabled"] is True
    tool = build_submit_plan_tool(
        command_types=request["supported_command_types"],
        resource_refs_enabled=resource_refs_enabled,
        capability_surface=request["capability_surface"],
    )
    metadata = {
        "architecture": REQUEST_CONTRACT,
        "contract_version": CONTRACT_VERSION,
    }
    prompt_trace_id = str(request.get("prompt_trace_id") or "").strip()
    if prompt_trace_id:
        metadata["prompt_trace_id"] = prompt_trace_id[:MAX_TRACE_ID_CHARS]
    return {
        "model": model.strip(),
        "instructions": _RESOURCE_REF_INSTRUCTIONS if resource_refs_enabled else _INSTRUCTIONS,
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "input_text", "text": f"RECENT_CONVERSATION_JSON:\n{_canonical_json(request['conversation'])}"},
                    {"type": "input_text", "text": f"CORE_CONTEXT_V3_JSON:\n{_canonical_json(request['core_context'])}"},
                    {"type": "input_text", "text": f"ORIGINAL_REQUEST_VERBATIM:\n{request['original_request']}"},
                ],
            }
        ],
        "tools": [tool],
        "tool_choice": {"type": "function", "name": "submit_plan_v3"},
        "parallel_tool_calls": False,
        "max_output_tokens": bounded_output_tokens,
        "reasoning": {"effort": reasoning_effort},
        "prompt_cache_retention": prompt_cache_retention,
        "store": bool(store),
        "metadata": metadata,
    }


def contract_fingerprint(
    *,
    command_types: Sequence[str],
    resource_refs_enabled: bool,
    capability_surface: V3CapabilitySurface,
    max_output_tokens: int = 8192,
) -> str:
    policy = {
        "contract_version": CONTRACT_VERSION,
        "instructions": _RESOURCE_REF_INSTRUCTIONS if resource_refs_enabled else _INSTRUCTIONS,
        "capability_surface": {
            "effects": [
                {
                    "effect_id": effect.effect_id,
                    "parameters": [
                        [parameter.parameter_id, parameter.minimum, parameter.maximum]
                        for parameter in effect.parameters
                    ],
                }
                for effect in capability_surface.effects
            ],
            "instruments": [
                {
                    "instrument_id": instrument.instrument_id,
                    "playable_pitch_ranges": [
                        [item.low, item.high]
                        for item in instrument.playable_pitch_ranges
                    ],
                }
                for instrument in capability_surface.instruments
            ],
            "selectable_instrument_ids": sorted(
                capability_surface.selectable_instrument_ids
            ),
            "rows": [
                [row.row_id, row.lane_kind, row.instrument_id]
                for row in capability_surface.rows
            ],
            "clips": [
                [
                    clip.clip_id,
                    clip.row_id,
                    clip.kind,
                    clip.instrument_id,
                    clip.length_beats,
                ]
                for clip in capability_surface.clips
            ],
            "groups": [
                [group.group_id, list(group.member_row_ids)]
                for group in capability_surface.groups
            ],
            "current_rows": capability_surface.current_rows,
            "maximum_rows": capability_surface.maximum_rows,
        },
        "tool": build_submit_plan_tool(
            command_types=command_types,
            resource_refs_enabled=resource_refs_enabled,
            capability_surface=capability_surface,
        ),
        "tool_choice": {"type": "function", "name": "submit_plan_v3"},
        "parallel_tool_calls": False,
        "effect_state_policy": _EFFECT_STATE_POLICY_VERSION,
        "mix_scope_policy": _MIX_SCOPE_POLICY_VERSION,
        "phone_cleanup_conflict_policy": _PHONE_CLEANUP_CONFLICT_POLICY_VERSION,
        "typed_clip_state_policy": _TYPED_CLIP_STATE_POLICY_VERSION,
        "group_state_policy": _GROUP_STATE_POLICY_VERSION,
        "user_visible_text_policy": _USER_VISIBLE_TEXT_POLICY_VERSION,
        "max_output_tokens": max_output_tokens,
        "max_accepted_plan_bytes": MAX_ACCEPTED_PROVIDER_PLAN_BYTES,
    }
    return hashlib.sha256(_canonical_json(policy).encode("utf-8")).hexdigest()[:16]


def _matches_type(value: Any, expected: str) -> bool:
    return {
        "object": isinstance(value, dict),
        "array": isinstance(value, list),
        "string": isinstance(value, str),
        "boolean": isinstance(value, bool),
        "integer": isinstance(value, int) and not isinstance(value, bool),
        "number": isinstance(value, (int, float)) and not isinstance(value, bool),
        "null": value is None,
    }.get(expected, False)


def _normalized_visible_text(value: Any) -> str:
    return " ".join(str(value or "").split()).casefold()


def _validate_user_visible_text(
    plan: Mapping[str, Any], *, original_request: str
) -> None:
    user_message = str(plan.get("user_message") or "")
    visible_text = [user_message]
    question_options = plan.get("question_options")
    if isinstance(question_options, list):
        visible_text.extend(
            option for option in question_options if isinstance(option, str)
        )

    for text in visible_text:
        normalized = text.casefold()
        if any(marker in normalized for marker in _PRIVATE_PROMPT_MARKERS):
            raise _contract_error(
                "v3_plan_user_visible_text_unsafe",
                "Provider-visible text contains private request context.",
            )

    if (
        plan.get("outcome") == "plan"
        and _normalized_visible_text(original_request)
        and _normalized_visible_text(user_message)
        == _normalized_visible_text(original_request)
    ):
        raise _contract_error(
            "v3_plan_user_visible_text_unsafe",
            "Provider completion text repeats the original request.",
        )

def _validate_json_schema(value: Any, schema: Mapping[str, Any], path: str = "$", *, quiet: bool = False) -> None:
    def fail(message: str) -> None:
        raise _contract_error("v3_plan_schema_invalid", message if not quiet else "schema mismatch")

    any_of = schema.get("anyOf")
    if isinstance(any_of, list):
        matches = 0
        for candidate in any_of:
            try:
                _validate_json_schema(value, candidate, path, quiet=True)
                matches += 1
            except V3ContractError:
                pass
        if matches < 1:
            fail(f"{path} does not match an allowed schema.")
        return
    one_of = schema.get("oneOf")
    if isinstance(one_of, list):
        matches = 0
        for candidate in one_of:
            try:
                _validate_json_schema(value, candidate, path, quiet=True)
                matches += 1
            except V3ContractError:
                pass
        if matches != 1:
            fail(f"{path} does not match exactly one allowed schema.")
        return
    expected_type = schema.get("type")
    if isinstance(expected_type, str) and not _matches_type(value, expected_type):
        fail(f"{path} has an invalid type.")
    if "const" in schema and value != schema["const"]:
        fail(f"{path} has an invalid value.")
    if isinstance(schema.get("enum"), list) and value not in schema["enum"]:
        fail(f"{path} has an invalid value.")
    if isinstance(value, dict):
        properties = schema.get("properties", {})
        required = schema.get("required", [])
        if any(key not in value for key in required):
            fail(f"{path} is missing a required field.")
        if schema.get("additionalProperties") is False and set(value) - set(properties):
            fail(f"{path} contains an unknown field.")
        for key, child in value.items():
            if key in properties:
                _validate_json_schema(child, properties[key], f"{path}.{key}", quiet=quiet)
    elif isinstance(value, list):
        if isinstance(schema.get("minItems"), int) and len(value) < schema["minItems"]:
            fail(f"{path} has too few items.")
        if isinstance(schema.get("maxItems"), int) and len(value) > schema["maxItems"]:
            fail(f"{path} has too many items.")
        item_schema = schema.get("items")
        if isinstance(item_schema, dict):
            for index, child in enumerate(value):
                _validate_json_schema(child, item_schema, f"{path}[{index}]", quiet=quiet)
    elif isinstance(value, str):
        if isinstance(schema.get("minLength"), int) and len(value) < schema["minLength"]:
            fail(f"{path} is too short.")
        if isinstance(schema.get("maxLength"), int) and len(value) > schema["maxLength"]:
            fail(f"{path} is too long.")
    elif isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            fail(f"{path} is below its minimum.")
        if "maximum" in schema and value > schema["maximum"]:
            fail(f"{path} is above its maximum.")
        if "exclusiveMinimum" in schema and value <= schema["exclusiveMinimum"]:
            fail(f"{path} is below its exclusive minimum.")


_POSSIBLE_RESOURCE_OUTPUTS: dict[str, frozenset[str]] = {
    "row.create": frozenset({"row"}),
    "midi.create_clip": frozenset({"midi_clip"}),
    "sample.place": frozenset({"audio_clip"}),
    "clip.separate_stems": frozenset(
        {"vocals_clip", "instrumental_clip", "vocals_row", "instrumental_row"}
    ),
    "clip.split_at": frozenset({"left_clip", "right_clip"}),
    "clip.duplicate_to": frozenset({"copy_clip"}),
    "clip.convert_to_midi": frozenset({"midi_clip", "midi_row"}),
    "clip.glue": frozenset({"glued_clip"}),
    "group.create": frozenset({"group"}),
}


def _walk_plan_values(value: Any):
    yield value
    if isinstance(value, dict):
        for child in value.values():
            yield from _walk_plan_values(child)
    elif isinstance(value, list):
        for child in value:
            yield from _walk_plan_values(child)


def _direct_identifiers(arguments: Mapping[str, Any], field: str) -> set[Any]:
    values: set[Any] = set()
    plural = f"{field}s"
    for value in _walk_plan_values(arguments):
        if not isinstance(value, dict):
            continue
        if field in value:
            values.add(value[field])
        raw_plural = value.get(plural)
        if isinstance(raw_plural, list):
            values.update(raw_plural)
    return values


def _produced_outputs(command_type: str, arguments: Mapping[str, Any]) -> frozenset[str]:
    outputs = _POSSIBLE_RESOURCE_OUTPUTS.get(command_type, frozenset())
    if command_type == "sample.place":
        placements = arguments.get("placements")
        return outputs if isinstance(placements, list) and len(placements) == 1 else frozenset()
    return outputs


def _row_creation_count(command_type: str, arguments: Mapping[str, Any]) -> int:
    if command_type == "row.create" or command_type == "clip.convert_to_midi":
        return 1
    if command_type == "clip.separate_stems":
        return 2
    if command_type in {"midi.create_clip", "sample.place"}:
        destination = arguments.get("destination")
        if isinstance(destination, dict) and isinstance(destination.get("new_row"), dict):
            return 1
    return 0


@dataclass
class _V3MutableRowState:
    lane_kind: str
    instrument_id: str
    mix_processing_supported: bool


@dataclass
class _V3MutableClipState:
    row_id: int | str | None
    kind: str
    instrument_id: str
    length_beats: float | None
    midi_notes: list[V3MidiNote] | None

    def copy_to(self, row_id: int | str | None) -> "_V3MutableClipState":
        return _V3MutableClipState(
            row_id,
            self.kind,
            self.instrument_id,
            self.length_beats,
            None if self.midi_notes is None else list(self.midi_notes),
        )


@dataclass
class _V3MutableGroupState:
    members: list[int | str]
    output_key: str | None = None


def _plan_midi_notes(raw_notes: Any) -> list[V3MidiNote]:
    if not isinstance(raw_notes, list):
        raise _contract_error("v3_plan_semantic_invalid", "A MIDI note list is invalid.")
    notes: list[V3MidiNote] = []
    for raw_note in raw_notes:
        if not isinstance(raw_note, dict):
            raise _contract_error("v3_plan_semantic_invalid", "A MIDI note is invalid.")
        pitch = raw_note.get("pitch")
        start = raw_note.get("start_beat")
        length = raw_note.get("length_beats")
        velocity = raw_note.get("velocity")
        if (
            not isinstance(pitch, int)
            or isinstance(pitch, bool)
            or isinstance(start, bool)
            or not isinstance(start, (int, float))
            or isinstance(length, bool)
            or not isinstance(length, (int, float))
            or isinstance(velocity, bool)
            or not isinstance(velocity, (int, float))
        ):
            raise _contract_error("v3_plan_semantic_invalid", "A MIDI note is invalid.")
        notes.append(V3MidiNote(pitch, float(start), float(length), float(velocity)))
    return notes


def _validate_playable_notes(
    notes: Sequence[V3MidiNote],
    instrument_id: str,
    instruments: Mapping[str, V3InstrumentCapability],
    *,
    maximum_end_beat: float | None = None,
) -> None:
    instrument = instruments.get(instrument_id)
    if instrument is None:
        raise _contract_error(
            "v3_plan_capability_invalid", "A MIDI command has no available instrument."
        )
    if any(not instrument.can_play(note.pitch) for note in notes):
        raise _contract_error(
            "v3_plan_midi_pitch_unavailable",
            "The provider plan contains a note unavailable to its effective instrument.",
        )
    if maximum_end_beat is not None and any(
        note.start_beat + note.length_beats > maximum_end_beat + 0.000001
        for note in notes
    ):
        raise _contract_error(
            "v3_plan_midi_note_out_of_bounds",
            "The provider plan contains a note outside its MIDI clip.",
        )


def _validate_phone_cleanup_sound_conflicts(
    plan: Mapping[str, Any], capability_surface: V3CapabilitySurface
) -> None:
    commands = plan.get("commands", [])
    cleanup_row_ids = {
        command.get("arguments", {}).get("row_id")
        for command in commands
        if isinstance(command, dict)
        and command.get("type") == "row.apply_phone_mic_cleanup"
        and isinstance(command.get("arguments"), dict)
    }
    cleanup_row_ids = {
        row_id
        for row_id in cleanup_row_ids
        if isinstance(row_id, int) and not isinstance(row_id, bool)
    }
    if not cleanup_row_ids:
        return

    effect_row_by_instance_id = {
        effect_instance_id: row.row_id
        for row in capability_surface.rows
        for effect_instance_id in row.effect_instance_ids
    }
    group_members_by_id = {
        group.group_id: set(group.member_row_ids)
        for group in capability_surface.groups
    }
    generated_group_members_by_ref: dict[str, set[int]] = {}
    for command in commands:
        if not isinstance(command, dict) or command.get("type") != "group.create":
            continue
        command_id = str(command.get("command_id") or "").strip()
        arguments = command.get("arguments")
        if not command_id or not isinstance(arguments, dict):
            continue
        generated_group_members_by_ref[f"{command_id}.group"] = {
            row_id
            for member in arguments.get("members", [])
            if isinstance(member, dict)
            for row_id in [member.get("row_id")]
            if isinstance(row_id, int) and not isinstance(row_id, bool)
        }

    for command in commands:
        if not isinstance(command, dict):
            continue
        command_type = command.get("type")
        arguments = command.get("arguments")
        if not isinstance(arguments, dict):
            continue

        effect_mutation_row_id: int | None = None
        if command_type == "effect.ensure_configured":
            row_id = arguments.get("row_id")
            if isinstance(row_id, int) and not isinstance(row_id, bool):
                effect_mutation_row_id = row_id
        elif command_type in {"effect.remove", "effect.set_bypassed"}:
            effect_mutation_row_id = effect_row_by_instance_id.get(
                arguments.get("effect_instance_id")
            )
        if effect_mutation_row_id in cleanup_row_ids:
            raise _contract_error(
                "v3_plan_phone_cleanup_effect_conflict",
                "Phone cleanup conflicts with another sound change on the same row.",
            )

        if command_type != "mix.apply_goal":
            continue
        target = arguments.get("target")
        if not isinstance(target, dict):
            continue
        target_row_ids: set[int] = set()
        scope = target.get("scope")
        if scope == "row":
            row_id = target.get("row_id")
            if isinstance(row_id, int) and not isinstance(row_id, bool):
                target_row_ids.add(row_id)
        elif scope == "group":
            target_row_ids.update(
                group_members_by_id.get(target.get("group_id"), set())
            )
            group_ref = target.get("group_ref")
            if isinstance(group_ref, dict):
                producer_id = str(group_ref.get("command_id") or "").strip()
                output = str(group_ref.get("output") or "").strip()
                target_row_ids.update(
                    generated_group_members_by_ref.get(
                        f"{producer_id}.{output}", set()
                    )
                )
        elif scope == "all_rows":
            target_row_ids.update(row.row_id for row in capability_surface.rows)
        if target_row_ids & cleanup_row_ids:
            raise _contract_error(
                "v3_plan_phone_cleanup_effect_conflict",
                "Phone cleanup conflicts with mixing on the same row.",
            )


def validate_plan_capabilities(
    plan: Mapping[str, Any], capability_surface: V3CapabilitySurface
) -> dict[str, Any]:
    effect_by_id = capability_surface.effect_by_id
    instrument_by_id = capability_surface.instrument_by_id
    active_rows = {
        row.row_id: _V3MutableRowState(
            row.lane_kind, row.instrument_id, row.mix_processing_supported
        )
        for row in capability_surface.rows
    }
    active_clips = {
        clip.clip_id: _V3MutableClipState(
            clip.row_id,
            clip.kind,
            clip.instrument_id,
            clip.length_beats,
            list(clip.midi_notes),
        )
        for clip in capability_surface.clips
    }
    active_effect_instances = set(capability_surface.effect_instance_ids)
    available_outputs: dict[str, frozenset[str]] = {}
    command_ids: set[str] = set()
    simulated_rows = capability_surface.current_rows
    generated_rows: dict[str, _V3MutableRowState] = {}
    generated_clips: dict[str, _V3MutableClipState] = {}
    generated_material_by_stable_row: dict[int, int] = {}
    generated_row_material: dict[str, int] = {}
    unaddressed_generated_material = 0
    active_groups: dict[tuple[str, str], _V3MutableGroupState] = {
        ("id", group.group_id): _V3MutableGroupState(list(group.member_row_ids))
        for group in capability_surface.groups
    }
    group_by_row: dict[int | str, tuple[str, str]] = {
        row_id: ("id", group.group_id)
        for group in capability_surface.groups
        for row_id in group.member_row_ids
    }

    def refresh_stable_row_readiness(row_id: int) -> None:
        if row_id not in active_rows:
            return
        active_rows[row_id].mix_processing_supported = (
            any(clip.row_id == row_id for clip in active_clips.values())
            or generated_material_by_stable_row.get(row_id, 0) > 0
        )

    def add_generated_material(parent: int | str | None, count: int = 1) -> None:
        nonlocal unaddressed_generated_material
        if isinstance(parent, int):
            generated_material_by_stable_row[parent] = (
                generated_material_by_stable_row.get(parent, 0) + count
            )
            if parent in active_rows:
                active_rows[parent].mix_processing_supported = True
        elif isinstance(parent, str):
            generated_row_material[parent] = (
                generated_row_material.get(parent, 0) + count
            )
        else:
            unaddressed_generated_material += count

    def remove_generated_material(parent: int | str | None, count: int = 1) -> None:
        nonlocal unaddressed_generated_material
        if isinstance(parent, int):
            generated_material_by_stable_row[parent] = max(
                0, generated_material_by_stable_row.get(parent, 0) - count
            )
            refresh_stable_row_readiness(parent)
        elif isinstance(parent, str):
            generated_row_material[parent] = max(
                0, generated_row_material.get(parent, 0) - count
            )
        else:
            unaddressed_generated_material = max(
                0, unaddressed_generated_material - count
            )

    def consume_generated_clip(clip_key: str | None) -> int | str | None:
        if clip_key is None:
            return None
        clip = generated_clips.pop(clip_key, None)
        if clip is None:
            return None
        parent = clip.row_id
        remove_generated_material(parent)
        return parent

    def resource_key(raw_ref: Any) -> str | None:
        if not isinstance(raw_ref, dict):
            return None
        command_id = str(raw_ref.get("command_id") or "").strip()
        output = str(raw_ref.get("output") or "").strip()
        return f"{command_id}.{output}" if command_id and output else None

    def group_key(arguments: Mapping[str, Any]) -> tuple[str, str] | None:
        group_id = arguments.get("group_id")
        if isinstance(group_id, str) and group_id:
            return ("id", group_id)
        group_ref_key = resource_key(arguments.get("group_ref"))
        return ("ref", group_ref_key) if group_ref_key is not None else None

    def row_key(arguments: Mapping[str, Any]) -> int | str | None:
        row_id = arguments.get("row_id")
        if isinstance(row_id, int) and not isinstance(row_id, bool):
            return row_id
        return resource_key(arguments.get("row_ref"))

    def retire_group(group: tuple[str, str]) -> None:
        state = active_groups.pop(group, None)
        if state is None:
            return
        for member in state.members:
            if group_by_row.get(member) == group:
                group_by_row.pop(member, None)
        if state.output_key is None:
            return
        producer_id, output = state.output_key.rsplit(".", 1)
        available_outputs[producer_id] = frozenset(
            candidate
            for candidate in available_outputs.get(producer_id, frozenset())
            if candidate != output
        )

    def detach_group_members(members: Sequence[int | str]) -> None:
        moved = set(members)
        affected_groups = {
            group_by_row[member]
            for member in moved
            if member in group_by_row
        }
        for group in affected_groups:
            state = active_groups.get(group)
            if state is None:
                continue
            remaining = [member for member in state.members if member not in moved]
            if len(remaining) < 2:
                retire_group(group)
                continue
            state.members = remaining
            for member in moved:
                if group_by_row.get(member) == group:
                    group_by_row.pop(member, None)

    def remove_group_member(
        group: tuple[str, str] | None, member: int | str | None
    ) -> None:
        state = active_groups.get(group) if group is not None else None
        if (
            state is None
            or member is None
            or member not in state.members
            or group_by_row.get(member) != group
        ):
            raise _contract_error(
                "v3_plan_capability_invalid",
                "The provider plan references unavailable group membership.",
            )
        remaining = [candidate for candidate in state.members if candidate != member]
        group_by_row.pop(member, None)
        if len(remaining) < 2:
            retire_group(group)
        else:
            state.members = remaining

    def resolve_clip(arguments: Mapping[str, Any]) -> _V3MutableClipState | None:
        clip_id = arguments.get("clip_id")
        if isinstance(clip_id, str):
            return active_clips.get(clip_id)
        return generated_clips.get(resource_key(arguments.get("clip_ref")) or "")

    def referenced_clips(
        arguments: Mapping[str, Any],
    ) -> list[_V3MutableClipState | None]:
        clips: list[_V3MutableClipState | None] = [
            active_clips.get(clip_id)
            for clip_id in _direct_identifiers(arguments, "clip_id")
        ]
        for value in _walk_plan_values(arguments):
            if not isinstance(value, dict) or "clip_ref" not in value:
                continue
            clips.append(
                generated_clips.get(resource_key(value.get("clip_ref")) or "")
            )
        return clips

    def destination_row_state(
        destination: Any,
    ) -> tuple[int | str | None, _V3MutableRowState | None]:
        if not isinstance(destination, dict):
            return None, None
        row_id = destination.get("row_id")
        if isinstance(row_id, int) and not isinstance(row_id, bool):
            return row_id, active_rows.get(row_id)
        row_ref_key = resource_key(destination.get("row_ref"))
        if row_ref_key is not None:
            return row_ref_key, generated_rows.get(row_ref_key)
        new_row = destination.get("new_row")
        if isinstance(new_row, dict):
            lane_kind = str(new_row.get("kind") or "").strip()
            instrument_id = str(new_row.get("instrument_id") or "").strip()
            return None, _V3MutableRowState(
                "instrument"
                if lane_kind == "midi" or "instrument_id" in new_row
                else "audio",
                instrument_id,
                False,
            )
        return None, None

    def stable_row_is_mixable(row_id: Any) -> bool:
        row = active_rows.get(row_id)
        return row is not None and row.mix_processing_supported

    def row_key_is_mixable(row_key: int | str) -> bool:
        if isinstance(row_key, int):
            return stable_row_is_mixable(row_key)
        return generated_row_material.get(row_key, 0) > 0

    def mix_target_is_ready(target: Any) -> bool:
        if not isinstance(target, dict):
            return False
        scope = target.get("scope")
        if scope == "row":
            row_id = target.get("row_id")
            if isinstance(row_id, int) and not isinstance(row_id, bool):
                return stable_row_is_mixable(row_id)
            row_ref_key = resource_key(target.get("row_ref"))
            return row_ref_key is not None and row_key_is_mixable(row_ref_key)
        if scope == "group":
            group_id = target.get("group_id")
            if isinstance(group_id, str):
                group = active_groups.get(("id", group_id))
                return group is not None and any(
                    row_key_is_mixable(row_id) for row_id in group.members
                )
            group_ref_key = resource_key(target.get("group_ref"))
            group = (
                active_groups.get(("ref", group_ref_key))
                if group_ref_key is not None
                else None
            )
            return group is not None and any(
                row_key_is_mixable(row_key) for row_key in group.members
            )
        if scope in {"all_rows", "master"}:
            return (
                any(row.mix_processing_supported for row in active_rows.values())
                or any(count > 0 for count in generated_row_material.values())
                or unaddressed_generated_material > 0
            )
        return False

    for command in plan.get("commands", []):
        command_id = str(command.get("command_id") or "").strip()
        command_type = str(command.get("type") or "").strip()
        arguments = command.get("arguments")
        if not command_id or command_id in command_ids or not isinstance(arguments, dict):
            raise _contract_error(
                "v3_plan_semantic_invalid", "The provider plan contains an invalid command."
            )
        command_ids.add(command_id)

        for value in _walk_plan_values(arguments):
            if not isinstance(value, dict) or set(value) != {"command_id", "output"}:
                continue
            producer_id = str(value.get("command_id") or "").strip()
            output = str(value.get("output") or "").strip()
            if output not in available_outputs.get(producer_id, frozenset()):
                raise _contract_error(
                    "v3_plan_resource_ref_invalid",
                    "The provider plan contains an invalid resource reference.",
                )

        if not _direct_identifiers(arguments, "row_id").issubset(active_rows.keys()):
            raise _contract_error(
                "v3_plan_capability_invalid", "The provider plan references an unavailable row."
            )
        if not _direct_identifiers(arguments, "clip_id").issubset(active_clips.keys()):
            raise _contract_error(
                "v3_plan_capability_invalid", "The provider plan references an unavailable clip."
            )
        if not _direct_identifiers(arguments, "effect_instance_id").issubset(
            active_effect_instances
        ):
            raise _contract_error(
                "v3_plan_capability_invalid",
                "The provider plan references an unavailable effect instance.",
            )
        active_stable_group_ids = {
            identifier for kind, identifier in active_groups if kind == "id"
        }
        if not _direct_identifiers(arguments, "group_id").issubset(
            active_stable_group_ids
        ):
            raise _contract_error(
                "v3_plan_capability_invalid", "The provider plan references an unavailable group."
            )
        if not _direct_identifiers(arguments, "asset_id").issubset(
            capability_surface.library_asset_ids
        ):
            raise _contract_error(
                "v3_plan_capability_invalid", "The provider plan references an unavailable asset."
            )
        if not _direct_identifiers(arguments, "instrument_id").issubset(
            capability_surface.instrument_ids
        ):
            raise _contract_error(
                "v3_plan_capability_invalid",
                "The provider plan references an unavailable instrument.",
            )

        if command_type == "effect.ensure_configured":
            effect_id = arguments.get("effect_id")
            effect = effect_by_id.get(effect_id)
            if effect is None:
                raise _contract_error(
                    "v3_plan_capability_invalid", "The provider plan references an unavailable effect."
                )
            allowed_parameters = {parameter.parameter_id for parameter in effect.parameters}
            seen_parameters: set[str] = set()
            for parameter in arguments.get("parameters", []):
                parameter_id = parameter.get("parameter_id") if isinstance(parameter, dict) else None
                if parameter_id not in allowed_parameters:
                    raise _contract_error(
                        "v3_plan_capability_invalid",
                        "The provider plan references an unavailable effect parameter.",
                    )
                if parameter_id in seen_parameters:
                    raise _contract_error(
                        "v3_plan_parameter_duplicate",
                        "The provider plan repeats an effect parameter.",
                    )
                seen_parameters.add(parameter_id)

        if command_type == "mix.apply_goal":
            available_mix_intents = _available_mix_intent_kinds(capability_surface)
            if any(
                not isinstance(intent, dict)
                or intent.get("kind") not in available_mix_intents
                for intent in arguments.get("intents", [])
            ):
                raise _contract_error(
                    "v3_plan_capability_invalid",
                    "The provider plan requests a mix intent unavailable to this project.",
                )
            if not mix_target_is_ready(arguments.get("target")):
                raise _contract_error(
                    "v3_plan_capability_invalid",
                    "The provider plan targets material unavailable for mixing.",
                )

        if command_type == "row.set_instrument":
            row_id = arguments.get("row_id")
            instrument_id = str(arguments.get("instrument_id") or "").strip()
            row = active_rows.get(row_id)
            if row is None or row.lane_kind != "instrument":
                raise _contract_error(
                    "v3_plan_target_type_invalid",
                    "An instrument command targets a non-instrument row.",
                )
            if instrument_id not in instrument_by_id:
                raise _contract_error(
                    "v3_plan_capability_invalid", "The provider plan references an unavailable instrument."
                )
            row.instrument_id = instrument_id
            for clip in active_clips.values():
                if clip.row_id == row_id and clip.kind == "midi":
                    clip.instrument_id = instrument_id

        if command_type in _MIDI_CLIP_COMMANDS:
            clip = resolve_clip(arguments)
            if clip is None or clip.kind != "midi":
                raise _contract_error(
                    "v3_plan_target_type_invalid", "A MIDI command targets a non-MIDI clip."
                )
            if command_type in {"midi.replace_notes", "midi.append_notes"}:
                notes = _plan_midi_notes(arguments.get("notes"))
                if clip.instrument_id:
                    _validate_playable_notes(
                        notes,
                        clip.instrument_id,
                        instrument_by_id,
                        maximum_end_beat=(
                            clip.length_beats
                            if command_type == "midi.replace_notes"
                            else None
                        ),
                    )
                elif (
                    command_type == "midi.replace_notes"
                    and clip.length_beats is not None
                    and any(
                        note.start_beat + note.length_beats
                        > clip.length_beats + 0.000001
                        for note in notes
                    )
                ):
                    raise _contract_error(
                        "v3_plan_midi_note_out_of_bounds",
                        "The provider plan contains a note outside its MIDI clip.",
                    )
                if command_type == "midi.replace_notes":
                    clip.midi_notes = notes
                elif clip.length_beats is not None or clip.midi_notes is not None:
                    current_end = max(
                        [clip.length_beats or 0.0]
                        + [
                            note.start_beat + note.length_beats
                            for note in (clip.midi_notes or [])
                        ]
                    )
                    appended = [
                        V3MidiNote(
                            note.pitch,
                            note.start_beat + current_end,
                            note.length_beats,
                            note.velocity,
                        )
                        for note in notes
                    ]
                    if clip.midi_notes is not None:
                        clip.midi_notes.extend(appended)
                    clip.length_beats = max(
                        [current_end]
                        + [note.start_beat + note.length_beats for note in appended]
                    )
            elif command_type == "midi.transpose":
                semitones = arguments.get("semitones")
                if not isinstance(semitones, int) or isinstance(semitones, bool):
                    raise _contract_error(
                        "v3_plan_semantic_invalid", "A MIDI transpose command is invalid."
                    )
                if clip.midi_notes is not None:
                    transposed = [
                        V3MidiNote(
                            note.pitch + semitones,
                            note.start_beat,
                            note.length_beats,
                            note.velocity,
                        )
                        for note in clip.midi_notes
                    ]
                    if clip.instrument_id:
                        _validate_playable_notes(
                            transposed, clip.instrument_id, instrument_by_id
                        )
                    clip.midi_notes = transposed

        if command_type in _AUDIO_CLIP_COMMANDS:
            clip_targets = referenced_clips(arguments)
            if not clip_targets or any(
                clip is None or clip.kind != "audio" for clip in clip_targets
            ):
                raise _contract_error(
                    "v3_plan_target_type_invalid", "An audio command targets a non-audio clip."
                )

        if command_type == "midi.create_clip":
            notes = _plan_midi_notes(arguments.get("notes"))
            destination = arguments.get("destination")
            instrument_id = ""
            _, row = destination_row_state(destination)
            if row is None or row.lane_kind != "instrument":
                raise _contract_error(
                    "v3_plan_target_type_invalid",
                    "A MIDI clip destination is not an instrument row.",
                )
            instrument_id = row.instrument_id
            if instrument_id:
                _validate_playable_notes(notes, instrument_id, instrument_by_id)

        creation_count = _row_creation_count(command_type, arguments)
        if (
            creation_count > 0
            and simulated_rows + creation_count > capability_surface.maximum_rows
        ):
            raise _contract_error(
                "v3_plan_row_capacity_exceeded", "The provider plan exceeds row capacity."
            )
        simulated_rows += creation_count

        if command_type == "row.delete":
            row_id = arguments.get("row_id")
            row_ref_key = resource_key(arguments.get("row_ref"))
            if simulated_rows <= 1:
                raise _contract_error(
                    "v3_plan_capability_invalid", "The provider plan cannot delete that row."
                )
            if isinstance(row_id, int) and not isinstance(row_id, bool):
                if row_id not in active_rows:
                    raise _contract_error(
                        "v3_plan_capability_invalid",
                        "The provider plan cannot delete that row.",
                    )
                detach_group_members([row_id])
                active_rows.pop(row_id)
                for clip_id in [
                    clip_id
                    for clip_id, clip in active_clips.items()
                    if clip.row_id == row_id
                ]:
                    active_clips.pop(clip_id)
                for clip_key in [
                    clip_key
                    for clip_key, clip in generated_clips.items()
                    if clip.row_id == row_id
                ]:
                    generated_clips.pop(clip_key, None)
                generated_material_by_stable_row.pop(row_id, None)
            elif row_ref_key is not None and row_ref_key in generated_row_material:
                detach_group_members([row_ref_key])
                generated_row_material.pop(row_ref_key)
                generated_rows.pop(row_ref_key, None)
                for clip_key in [
                    clip_key
                    for clip_key, clip in generated_clips.items()
                    if clip.row_id == row_ref_key
                ]:
                    generated_clips.pop(clip_key, None)
            else:
                raise _contract_error(
                    "v3_plan_capability_invalid",
                    "The provider plan cannot delete that row.",
                )
            simulated_rows -= 1
        elif command_type == "clip.delete":
            removed_clip = active_clips.pop(arguments.get("clip_id"), None)
            if removed_clip is not None:
                refresh_stable_row_readiness(removed_clip.row_id)
            clip_ref_key = resource_key(arguments.get("clip_ref"))
            consume_generated_clip(clip_ref_key)
        elif command_type == "effect.remove":
            active_effect_instances.discard(arguments.get("effect_instance_id"))
        elif command_type == "group.remove_row":
            remove_group_member(group_key(arguments), row_key(arguments))
        elif command_type == "group.set_collapsed":
            if group_key(arguments) not in active_groups:
                raise _contract_error(
                    "v3_plan_capability_invalid",
                    "The provider plan references an unavailable group.",
                )

        produced_outputs = _produced_outputs(command_type, arguments)
        available_outputs[command_id] = produced_outputs
        if command_type == "row.create" and "row" in produced_outputs:
            row_key = f"{command_id}.row"
            lane = arguments.get("lane")
            lane_kind = str(lane.get("kind") or "") if isinstance(lane, dict) else ""
            instrument_id = (
                str(lane.get("instrument_id") or "").strip()
                if isinstance(lane, dict)
                else ""
            )
            generated_row_material[row_key] = 0
            generated_rows[row_key] = _V3MutableRowState(
                "instrument" if lane_kind == "midi" else "audio",
                instrument_id,
                False,
            )
        elif command_type == "clip.separate_stems":
            for row_output, clip_output in (
                ("vocals_row", "vocals_clip"),
                ("instrumental_row", "instrumental_clip"),
            ):
                row_key = f"{command_id}.{row_output}"
                clip_key = f"{command_id}.{clip_output}"
                generated_row_material[row_key] = 1
                generated_rows[row_key] = _V3MutableRowState("audio", "", True)
                generated_clips[clip_key] = _V3MutableClipState(
                    row_key, "audio", "", None, None
                )
        elif command_type == "clip.convert_to_midi":
            row_key = f"{command_id}.midi_row"
            clip_key = f"{command_id}.midi_clip"
            source = resolve_clip(arguments)
            instrument_id = str(arguments.get("instrument_id") or "").strip()
            generated_row_material[row_key] = 1
            generated_rows[row_key] = _V3MutableRowState(
                "instrument", instrument_id, True
            )
            generated_clips[clip_key] = _V3MutableClipState(
                row_key,
                "midi",
                instrument_id,
                source.length_beats if source is not None else None,
                None,
            )

        if command_type in {"midi.create_clip", "sample.place"}:
            destination = arguments.get("destination")
            material_count = (
                len(arguments.get("placements", []))
                if command_type == "sample.place"
                and isinstance(arguments.get("placements"), list)
                else 1
            )
            parent, destination_row = destination_row_state(destination)
            add_generated_material(parent, material_count)
            if len(produced_outputs) == 1:
                output = next(iter(produced_outputs))
                clip_key = f"{command_id}.{output}"
                if command_type == "midi.create_clip":
                    generated_clips[clip_key] = _V3MutableClipState(
                        parent,
                        "midi",
                        destination_row.instrument_id
                        if destination_row is not None
                        else "",
                        float(arguments["length_beats"]),
                        _plan_midi_notes(arguments.get("notes")),
                    )
                else:
                    generated_clips[clip_key] = _V3MutableClipState(
                        parent, "audio", "", None, None
                    )

        if command_type == "clip.duplicate_to" and "copy_clip" in produced_outputs:
            source = resolve_clip(arguments)
            destination_row_id = arguments.get("destination_row_id")
            if isinstance(destination_row_id, int) and not isinstance(
                destination_row_id, bool
            ):
                parent: int | str | None = destination_row_id
            else:
                source_ref_key = resource_key(arguments.get("clip_ref"))
                if source_ref_key in generated_clips:
                    parent = generated_clips[source_ref_key].row_id
                else:
                    parent = source.row_id if source is not None else None
            if source is None:
                raise _contract_error(
                    "v3_plan_target_type_invalid",
                    "A duplicate command targets an unavailable clip.",
                )
            add_generated_material(parent)
            clip_key = f"{command_id}.copy_clip"
            generated_clips[clip_key] = source.copy_to(parent)

        if command_type == "clip.split_at":
            parent: int | str | None = None
            source = active_clips.pop(arguments.get("clip_id"), None)
            if source is not None:
                parent = source.row_id
                refresh_stable_row_readiness(source.row_id)
            else:
                source_ref_key = resource_key(arguments.get("clip_ref"))
                if source_ref_key in generated_clips:
                    source = generated_clips.get(source_ref_key)
                    parent = source.row_id if source is not None else None
                    consume_generated_clip(source_ref_key)
            if source is None:
                raise _contract_error(
                    "v3_plan_target_type_invalid",
                    "A split command targets an unavailable clip.",
                )
            add_generated_material(parent, 2)
            left_key = f"{command_id}.left_clip"
            right_key = f"{command_id}.right_clip"
            split_beat = float(arguments.get("at_beat") or 0.0)
            left = source.copy_to(parent)
            right = source.copy_to(parent)
            if source.length_beats is not None:
                left.length_beats = min(source.length_beats, split_beat)
                right.length_beats = max(0.0, source.length_beats - split_beat)
            if source.kind == "midi":
                left.midi_notes = None
                right.midi_notes = None
            generated_clips[left_key] = left
            generated_clips[right_key] = right

        if command_type == "clip.glue" and "glued_clip" in produced_outputs:
            raw_sources = arguments.get("sources")
            if not isinstance(raw_sources, list):
                raw_sources = [
                    {"clip_id": clip_id}
                    for clip_id in arguments.get("clip_ids", [])
                ]
            parents: list[int | str | None] = []
            sources: list[_V3MutableClipState] = []
            for raw_source in raw_sources:
                if not isinstance(raw_source, dict):
                    continue
                source = active_clips.pop(raw_source.get("clip_id"), None)
                if source is not None:
                    sources.append(source)
                    parents.append(source.row_id)
                    refresh_stable_row_readiness(source.row_id)
                    continue
                source_ref_key = resource_key(raw_source.get("clip_ref"))
                if source_ref_key in generated_clips:
                    source = generated_clips.get(source_ref_key)
                    if source is not None:
                        sources.append(source)
                        parents.append(source.row_id)
                    consume_generated_clip(source_ref_key)
            distinct_parents = set(parents)
            if len(distinct_parents) != 1:
                raise _contract_error(
                    "v3_plan_capability_invalid",
                    "The provider plan glues clips from incompatible rows.",
                )
            parent = parents[0]
            add_generated_material(parent)
            clip_key = f"{command_id}.glued_clip"
            generated_clips[clip_key] = _V3MutableClipState(
                parent,
                "audio",
                "",
                (
                    sum(source.length_beats for source in sources)
                    if sources
                    and all(source.length_beats is not None for source in sources)
                    else None
                ),
                None,
            )

        if command_type == "group.create" and "group" in produced_outputs:
            members: list[int | str] = []
            raw_members = arguments.get("members")
            if not isinstance(raw_members, list):
                raw_members = [
                    {"row_id": row_id}
                    for row_id in arguments.get("row_ids", [])
                ]
            for member in raw_members:
                if not isinstance(member, dict):
                    continue
                row_id = member.get("row_id")
                if isinstance(row_id, int) and not isinstance(row_id, bool):
                    members.append(row_id)
                    continue
                row_ref_key = resource_key(member.get("row_ref"))
                if row_ref_key is not None:
                    members.append(row_ref_key)
            if (
                len(members) < 2
                or len(members) != len(set(members))
                or any(
                    member not in active_rows
                    if isinstance(member, int)
                    else member not in generated_rows
                    for member in members
                )
            ):
                raise _contract_error(
                    "v3_plan_capability_invalid",
                    "The provider plan contains invalid group membership.",
                )
            detach_group_members(members)
            output_key = f"{command_id}.group"
            created_group = ("ref", output_key)
            active_groups[created_group] = _V3MutableGroupState(
                members, output_key=output_key
            )
            for member in members:
                group_by_row[member] = created_group

    _validate_phone_cleanup_sound_conflicts(plan, capability_surface)

    return {
        "rows": {
            str(row_id): {
                "lane_kind": row.lane_kind,
                "instrument_id": row.instrument_id,
            }
            for row_id, row in sorted(active_rows.items())
        },
        "clips": {
            clip_id: {
                "row_id": clip.row_id,
                "kind": clip.kind,
                "instrument_id": clip.instrument_id,
                "length_beats": clip.length_beats,
                "midi_pitches": [note.pitch for note in clip.midi_notes],
            }
            for clip_id, clip in sorted(active_clips.items())
        },
        "row_count": simulated_rows,
    }


def parse_and_validate_provider_plan(
    payload: Mapping[str, Any],
    *,
    command_types: Sequence[str],
    resource_refs_enabled: bool,
    capability_surface: V3CapabilitySurface,
    original_request: str = "",
) -> dict[str, Any]:
    status = str(payload.get("status") or "").strip().lower()
    incomplete = payload.get("incomplete_details")
    incomplete_reason = (
        str(incomplete.get("reason") or "").strip().lower()
        if isinstance(incomplete, dict)
        else ""
    )
    if status == "incomplete" or incomplete_reason:
        code = (
            "v3_provider_output_truncated"
            if incomplete_reason in {"max_output_tokens", "max_tokens"}
            else "v3_provider_output_incomplete"
        )
        raise _contract_error(code, "Provider output was incomplete.")
    output = payload.get("output")
    if not isinstance(output, list):
        raise _contract_error("v3_provider_output_missing", "Provider output is missing.")
    if any(isinstance(item, dict) and item.get("type") == "refusal" for item in output):
        raise _contract_error("v3_provider_output_refusal", "Provider refused the request.")
    calls = [item for item in output if isinstance(item, dict) and item.get("type") == "function_call"]
    if len(calls) != 1 or calls[0].get("name") != "submit_plan_v3":
        raise _contract_error("v3_provider_tool_call_missing", "Provider tool call is invalid.")
    raw_arguments = calls[0].get("arguments")
    if isinstance(raw_arguments, str):
        try:
            plan = json.loads(raw_arguments)
        except json.JSONDecodeError as error:
            raise _contract_error("v3_provider_arguments_invalid_json", "Provider arguments are invalid JSON.") from error
    elif isinstance(raw_arguments, dict):
        plan = copy.deepcopy(raw_arguments)
    else:
        raise _contract_error("v3_provider_arguments_missing", "Provider arguments are invalid.")
    if not isinstance(plan, dict):
        raise _contract_error("v3_provider_plan_not_object", "Provider plan must be an object.")
    if len(_canonical_json(plan).encode("utf-8")) > MAX_ACCEPTED_PROVIDER_PLAN_BYTES:
        raise _contract_error("v3_provider_plan_too_large", "Provider plan exceeds the accepted output budget.")
    tool = build_submit_plan_tool(
        command_types=command_types,
        resource_refs_enabled=resource_refs_enabled,
        capability_surface=capability_surface,
    )
    _validate_json_schema(plan, tool["parameters"])
    _validate_user_visible_text(plan, original_request=original_request)
    effective_types = frozenset(command_types) & SERVER_COMMAND_TYPES
    for command in plan.get("commands", []):
        if not isinstance(command, dict) or command.get("type") not in effective_types:
            raise _contract_error("v3_command_outside_surface", "Provider command is outside the effective surface.")
    commands = plan.get("commands", [])
    outcome = plan.get("outcome")
    if bool(commands) != (outcome == "plan"):
        raise _contract_error("v3_plan_outcome_invalid", "Provider plan outcome does not match its commands.")
    validate_plan_capabilities(plan, capability_surface)
    return plan


def response_envelope(
    *,
    plan: Mapping[str, Any],
    prompt_trace_id: str,
    request_id: str,
    fingerprint: str,
) -> dict[str, Any]:
    trace = {
        "contract_version": CONTRACT_VERSION,
        "contract_fingerprint": fingerprint,
    }
    if prompt_trace_id:
        trace["prompt_trace_id"] = prompt_trace_id
    if request_id:
        trace["request_id"] = request_id
    return {
        "schema_version": RESPONSE_SCHEMA_VERSION,
        "plan": copy.deepcopy(dict(plan)),
        "trace": trace,
    }
