"""Shared plugin target and feature contract for capture conversion and inference.

Native parameter values are engine coordinates. For hosted plugins these can be
normalized coordinates, even when display text is in Hz/dB. Never parse display
text or substitute a linear Hz mapping for the engine's parameter mapping.
"""
from __future__ import annotations

import hashlib
import math
import re
from typing import Any

CONTRACT = "mix_refine_plugins_v2"
EXTRA_FEATURE_COUNT = 64
FEATURE_COUNT = 77 + EXTRA_FEATURE_COUNT
PARAM_ACTIONS = {"adjust_effect_param_by_name", "adjust_master_effect_param_by_name"}
STRUCTURAL_ACTIONS = {"ensure_effect", "ensure_master_effect", "delete_effect",
                      "delete_master_effect", "hard_reset_row_fx", "hard_reset_master_fx"}


def number(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return float(value) if math.isfinite(value) else None


def bus_target(project: dict, action: dict) -> dict | None:
    data = action["data"]
    if "master" in action["type"] or data.get("force_individual_row") is True:
        return None
    buses = [b for b in project.get("group_buses", []) if data.get("row") in b.get("row_indices", [])]
    return buses[0] if len(buses) == 1 else None


def chain(project: dict, action: dict) -> list[dict] | None:
    if "master" in action["type"]:
        effects = project.get("master_effects")
    else:
        bus = bus_target(project, action)
        if bus is not None:
            return bus.get("effects")
        rows = [r for r in project.get("rows", []) if r.get("row") == action["data"].get("row")]
        effects = rows[0].get("effects") if len(rows) == 1 else None
    return effects if isinstance(effects, list) and all(isinstance(e, dict) for e in effects) else None


def effect_target(project: dict, action: dict) -> dict | None:
    data = action["data"]
    effects = chain(project, action)
    if effects is None:
        return None
    token = str(data.get("effect_name_contains") or "").strip().lower()
    # Match the application's name selector. Multiple matches cannot safely
    # become labels for an individual instance.
    matches = [e for e in effects if token and token in str(e.get("name", "")).lower()]
    return matches[0] if len(matches) == 1 else None


def parameter_target(project: dict, action: dict) -> tuple[dict, dict] | None:
    effect = effect_target(project, action)
    if effect is None:
        return None
    data = action["data"]
    exact = str(data.get("param_name") or "").strip().lower()
    fuzzy = [str(t).lower() for t in data.get("param_name_contains_any", []) if str(t)]
    parameters = effect.get("parameters", [])
    matches = [p for p in parameters if exact and str(p.get("name", "")).lower() == exact]
    if not matches:
        matches = [p for p in parameters if any(t in str(p.get("name", "")).lower() for t in fuzzy)]
    return (effect, matches[0]) if len(matches) == 1 else None


def is_continuous(parameter: dict) -> bool:
    return parameter.get("type") == "float"


def parameter_recreated(actions: list[dict], index: int) -> bool:
    """A reset/delete earlier in this batch invalidates pre-inference values."""
    action = actions[index]
    if action["type"] not in PARAM_ACTIONS:
        return False
    data = action["data"]
    for previous in actions[:index]:
        if ("master" in previous["type"]) != ("master" in action["type"]):
            continue
        if any(previous["data"].get(k) != data.get(k) for k in ("row", "force_individual_row")):
            continue
        if previous["type"].startswith("hard_reset"):
            return True
        if previous["type"].startswith("delete") and str(previous["data"].get("effect_name_contains", "")).lower() == str(data.get("effect_name_contains", "")).lower():
            return True
    return False


def proposed_value(parameter: dict, data: dict) -> Any:
    if parameter.get("type") in {"bool", "choice"}:
        current = (1.0 if parameter.get("value") else 0.0) if parameter["type"] == "bool" else number(parameter.get("valueNormalized"))
        normalized = number(data.get("value_norm" if data.get("mode", "delta") == "set" else "delta_norm"))
        if normalized is None:
            normalized = number(data.get("value" if data.get("mode", "delta") == "set" else "delta"))
        if normalized is None or current is None:
            return None
        if data.get("mode", "delta") != "set":
            normalized += current
        normalized = max(0.0, min(1.0, normalized))
        if parameter["type"] == "bool":
            return normalized >= 0.5
        choices = [parameter[k] for k in sorted((k for k in parameter if k.startswith("choice_")), key=lambda k: int(k[7:]))]
        if not choices:
            return None
        return choices[int(math.floor(normalized * (len(choices) - 1) + 0.5))]
    if not is_continuous(parameter):
        return None
    initial = number(parameter.get("value"))
    low, high = number(parameter.get("min")), number(parameter.get("max"))
    if initial is None or low is None or high is None or high <= low:
        return None
    if data.get("mode", "delta") == "set":
        normalized = number(data.get("value_norm"))
        result = low + (high - low) * max(0.0, min(1.0, normalized)) if normalized is not None else number(data.get("value"))
    else:
        normalized = number(data.get("delta_norm"))
        delta = normalized * (high - low) if normalized is not None else number(data.get("delta"))
        result = initial + delta if delta is not None else None
    if result is None:
        return None
    hard_low, hard_high = number(data.get("clamp_min")), number(data.get("clamp_max"))
    if hard_low is not None:
        result = max(hard_low, result)
    if hard_high is not None:
        result = min(hard_high, result)
    result = max(low, min(high, result))
    interval = number(parameter.get("interval"))
    if interval is not None and interval > 0:
        result = max(low, min(high, low + math.floor((result - low) / interval + 0.5) * interval))
    scale = number(data.get("refinement_scale"))
    if scale is not None:
        result = max(low, min(high, initial + (result - initial) * max(0.0, min(3.0, scale))))
        if hard_low is not None:
            result = max(hard_low, result)
        if hard_high is not None:
            result = min(hard_high, result)
        result = max(low, min(high, result))
        if interval is not None and interval > 0:
            result = max(low, min(high, low + math.floor((result - low) / interval + 0.5) * interval))
    return result


def plugin_supervision(before: dict, after: dict, action: dict) -> tuple[dict | None, list[str]]:
    """Return an auditable final target, rejecting replacement/ambiguous instances."""
    kind = action["type"]
    if kind not in PARAM_ACTIONS | STRUCTURAL_ACTIONS:
        return None, []
    initial_chain, final_chain = chain(before, action), chain(after, action)
    if initial_chain is None or final_chain is None:
        return None, ["missing_plugin_chain"]
    if kind in PARAM_ACTIONS:
        match = parameter_target(before, action)
        if match is None:
            return None, ["ambiguous_or_missing_plugin_parameter"]
        effect, parameter = match
        instance = effect.get("instanceId")
        if not instance or not effect.get("effectId") or not parameter.get("id"):
            return None, ["missing_plugin_identity"]
        finals = [e for e in final_chain if e.get("instanceId") == instance]
        if len(finals) != 1 or finals[0].get("effectId") != effect["effectId"]:
            return None, ["plugin_instance_removed_or_replaced"]
        final_effect = finals[0]
        final_params = [p for p in final_effect.get("parameters", []) if p.get("id") == parameter["id"]]
        if len(final_params) != 1:
            return None, ["missing_final_plugin_parameter"]
        final = final_params[0]
        if any(parameter.get(k) != final.get(k) for k in ("type", "min", "max", "unit", "interval", "choices", *[k for k in parameter if k.startswith("choice_")])):
            return None, ["plugin_parameter_contract_changed"]
        proposal = proposed_value(parameter, action["data"])
        target = {
            "kind": "continuous_parameter" if is_continuous(parameter) else "discrete_parameter",
            "plugin_id": effect["effectId"], "instance_id": instance,
            "parameter_id": parameter["id"], "parameter_name": parameter.get("name"),
            "unit": parameter.get("unit", ""), "min": parameter.get("min"), "max": parameter.get("max"),
            "before": parameter.get("value"), "proposal": proposal, "final": final.get("value"),
            "chain_index_before": initial_chain.index(effect), "chain_index_after": final_chain.index(final_effect),
            "preserved": False, "magnitude_scale": None,
        }
        if proposal is None:
            return target, ["unsupported_plugin_value_encoding"]
        if effect.get("isBypassed") or final_effect.get("isBypassed"):
            return target, ["plugin_bypassed"]
        if target["kind"] == "discrete_parameter":
            target["preserved"] = type(proposal) is type(final.get("value")) and proposal == final.get("value")
        else:
            start, end = number(parameter.get("value")), number(final.get("value"))
            if start is None or end is None or not parameter["min"] <= end <= parameter["max"]:
                return target, ["invalid_final_plugin_value"]
            delta = proposal - start
            if abs(delta) > 1e-9:
                ratio = (end - start) / delta
                target["preserved"] = ratio > 0.05
                target["direction_ratio"] = ratio
                if 0 <= ratio <= 3:
                    target["magnitude_scale"] = ratio
        return target, []
    if kind.startswith("hard_reset"):
        if final_chain and any(not e.get("instanceId") for e in [*initial_chain, *final_chain]):
            return None, ["missing_plugin_identity"]
        surviving = {e.get("instanceId") for e in initial_chain} & {e.get("instanceId") for e in final_chain}
        return {"kind": "chain_reset", "preserved": bool(initial_chain) and not surviving}, []
    initial, final = effect_target(before, action), effect_target(after, action)
    if kind.startswith("ensure"):
        token = str(action["data"].get("effect_name_contains") or "").strip().lower()
        matches = [e for e in final_chain if token and token in str(e.get("name", "")).lower()]
        if token and not matches:
            return {"kind": "plugin_insert", "preserved": False}, []
        if final is None or not final.get("instanceId") or not final.get("effectId"):
            return None, ["missing_or_ambiguous_final_plugin"]
        return {"kind": "plugin_insert", "plugin_id": final["effectId"],
                "instance_id": final["instanceId"], "preserved": not final.get("isBypassed", False)}, []
    if initial is None or not initial.get("instanceId"):
        return None, ["missing_plugin_identity"]
    return {"kind": "plugin_remove", "instance_id": initial["instanceId"],
            "preserved": not any(str(action["data"].get("effect_name_contains", "")).lower() in str(e.get("name", "")).lower() for e in final_chain)}, []


def _hash_tokens(text: str, count: int) -> list[float]:
    vector = [0.0] * count
    for token in sorted(set(re.findall(r"[a-z0-9]+", text.lower()))):
        digest = hashlib.sha256(token.encode()).digest()
        vector[int.from_bytes(digest[:4], "big") % count] += 1.0 if digest[4] & 1 else -1.0
    norm = math.sqrt(sum(x * x for x in vector)) or 1.0
    return [x / norm for x in vector]


def extra_features(project: dict, action: dict) -> list[float]:
    """64 deterministic pre-action features. No identities/outcomes/final state."""
    effect = effect_target(project, action) or {}
    match = parameter_target(project, action) if action["type"] in PARAM_ACTIONS else None
    parameter = match[1] if match else {}
    data = action["data"]
    plugin = str(effect.get("name") or data.get("effect_name_contains") or "")
    bus = bus_target(project, action)
    if bus is not None:
        plugin += " group_bus"
    parameter_text = " ".join(str(parameter.get(k, "")) for k in ("id", "name", "unit")).strip() or str(data.get("param_name", ""))
    low, high = number(parameter.get("min")), number(parameter.get("max"))
    current, proposal = number(parameter.get("value")), number(proposed_value(parameter, data))
    if parameter.get("type") == "bool":
        low, high = 0.0, 1.0
        current = float(bool(parameter.get("value")))
        discrete = proposed_value(parameter, data)
        proposal = float(discrete) if isinstance(discrete, bool) else None
    elif parameter.get("type") == "choice":
        choices = [parameter[k] for k in sorted((k for k in parameter if k.startswith("choice_")), key=lambda k: int(k[7:]))]
        discrete = proposed_value(parameter, data)
        if len(choices) > 1 and parameter.get("value") in choices and discrete in choices:
            low, high = 0.0, 1.0
            current = choices.index(parameter["value"]) / (len(choices) - 1)
            proposal = choices.index(discrete) / (len(choices) - 1)
            parameter_text += " " + str(discrete)
    valid_range = low is not None and high is not None and high > low
    width = high - low if valid_range else 1.0
    current_norm = (current - low) / width if valid_range and current is not None else 0.0
    proposal_norm = (proposal - low) / width if valid_range and proposal is not None else 0.0
    effects = chain(project, action) or []
    numeric = [float(bool(match)), float(valid_range), float(is_continuous(parameter)),
               float(parameter.get("type") == "bool"), float(parameter.get("type") == "choice"),
               float(bool(parameter.get("interval"))), current_norm, proposal_norm,
               proposal_norm - current_norm, float(bool(effect.get("isBypassed"))),
               min(len(effects), 32) / 32, min(effects.index(effect), 31) / 31 if effect in effects else 0,
               float("master" in action["type"]), float(action["type"].startswith("ensure")),
               float(action["type"].startswith("delete")), float(action["type"].startswith("hard_reset"))]
    values = _hash_tokens(plugin, 32) + _hash_tokens(parameter_text, 16) + numeric
    if len(values) != EXTRA_FEATURE_COUNT or not all(math.isfinite(x) for x in values):
        raise ValueError("Invalid plugin feature vector")
    return values
