from __future__ import annotations

import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from common.llm_contract import build_llm_request_from_mixroom_payload  # noqa: E402


OPTIMIZED_CAPABILITIES = [
    "daw.project_edit.set_tempo",
    "daw.sample_insert.library",
    "daw.midi_compose.instrument_insert",
    "daw.midi_compose.transpose_notes",
    "daw.midi_compose.audio_to_midi",
    "daw.transport_control",
    "daw.row_mute",
    "daw.row_solo",
    "daw.row_rename",
    "daw.row_select",
    "daw.row_delete",
    "daw.row_create",
    "daw.row_mix",
    "daw.automation_edit",
    "daw.clip_edit.pitch_shift",
    "daw.clean_content_rows",
]


def _request_for(user_text: str) -> dict:
    return build_llm_request_from_mixroom_payload(
        {
            "conversation": [],
            "user_text": user_text,
            "project_snapshot": (
                'Project: tempo_bpm=92 row_count=4 occupied_tracks=1,2 '
                'selected_row_index=1\n'
                'Track 1: row_name="Instrumental" labels=[Backing Music] '
                "clip_count=1 roles=[instrumental]\n"
                'Track 2: row_name="Vocals" labels=[Lead Vocal] '
                "clip_count=1 roles=[vocal]"
            ),
            "selection_snapshot": (
                'selected_row_context{row_index=1,row_name="Vocals",'
                "roles=[vocal,lead]}"
            ),
            "library_snapshot": (
                "Instruments:\n"
                "- mixroom.lofi_keys: Lofi Keys\n"
                "Sample library_role_hints:\n"
                "- role:kick: [Lofi Pack/Drums/Kick.wav]"
            ),
            "client_context": {
                "ai_capabilities": OPTIMIZED_CAPABILITIES,
                "ai_context_packing_mode": "compact",
                "ai_tool_routing_mode": "intent_scoped",
                "subscription_plan": "pro",
                "max_rows": 12,
                "current_rows": 4,
                "allowed_builtin_effects": ["EQ", "Reverb", "Delay"],
                "allowed_instrument_ids": ["mixroom.lofi_keys"],
                "plugin_access": "all_plugins",
            },
        },
        default_model="gpt-5.4-mini",
    )


def _tool_names(request: dict) -> set[str]:
    return {
        str(tool.get("name") or "")
        for tool in request.get("tools", [])
        if isinstance(tool, dict)
    }


class IntentScopedRoutingTests(unittest.TestCase):
    def test_vocal_brighten_followup_keeps_mix_tool_available(self) -> None:
        request = _request_for(
            "do not split the stems anymore, only brighten the vocals"
        )
        self.assertIn("mix_model_request", _tool_names(request))
        self.assertIn("daw_assistant_actions", _tool_names(request))

    def test_vocal_width_and_warmth_keeps_mix_tool_available(self) -> None:
        request = _request_for(
            "make the vocals wider and warmer, but do not touch the drums"
        )
        self.assertIn("mix_model_request", _tool_names(request))

    def test_starter_song_still_routes_to_daw_material_creation(self) -> None:
        request = _request_for(
            "make me a small lofi starter beat from the library"
        )
        names = _tool_names(request)
        self.assertIn("daw_assistant_actions", names)
        self.assertNotIn("mix_model_request", names)

    def test_compound_remix_adds_two_tool_family_hint(self) -> None:
        request = _request_for(
            "make this a chill lofi remix: lower the instrumental pitch, "
            "add dusty drums, make it warmer and give it more space"
        )
        names = _tool_names(request)
        self.assertIn("daw_assistant_actions", names)
        self.assertIn("mix_model_request", names)
        self.assertIn(
            "combines concrete DAW edits with sonic mix goals",
            str(request.get("instructions") or ""),
        )


if __name__ == "__main__":
    unittest.main()
