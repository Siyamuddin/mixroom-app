"""Offline evaluation facade; all repair instructions/logic live in the backend."""
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend/llm_proxy/src"))
from common import v3_server_contract as contract
from common.llm_contract import build_openai_responses_request
from common.v3_pitch_repair import (
    INSTRUCTIONS, TOOL_NAME, RepairCase, RepairRejected, canonical, size,
    validation_args, plan_payload, prepare, reconstruct,
)


def comparison_metrics(case, full_plan_repair_body, patch_payload):
    """Metadata only. Passing this check is not evidence of live musical quality."""
    repaired = reconstruct(case, patch_payload)
    patch_arguments = patch_payload["output"][0]["arguments"]
    patch = json.loads(patch_arguments) if isinstance(patch_arguments, str) else patch_arguments
    full_upstream = build_openai_responses_request(full_plan_repair_body)
    targeted_upstream = build_openai_responses_request(case.body)
    return {
        "affected_commands": len({v["command_index"] for v in case.violations}),
        "corrected_pitches": len(case.violations),
        "plan_commands": len(repaired["commands"]),
        "full_repair_request_bytes": size(full_plan_repair_body),
        "targeted_repair_request_bytes": size(case.body),
        "full_repair_upstream_bytes": size(full_upstream),
        "targeted_repair_upstream_bytes": size(targeted_upstream),
        "full_repair_wire_bytes": len(json.dumps(full_upstream).encode("utf-8")),
        "targeted_repair_wire_bytes": len(json.dumps(targeted_upstream).encode("utf-8")),
        "full_plan_output_bytes": size(repaired),
        "patch_output_bytes": size(patch),
        "plan_preserved": True,
    }
