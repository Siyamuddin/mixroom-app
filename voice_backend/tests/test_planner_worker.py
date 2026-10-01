"""Offline integration tests: real Python -> Node worker, mocked HTTP providers.

The test-only subprocess hook preloads a temporary fetch fixture. Production
settings and request data cannot choose scripts, provider URLs, or fetch hooks.
"""

import asyncio
from contextlib import contextmanager
import json
import os
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

from planner import bridge


SETTINGS = SimpleNamespace(openai_api_key="offline-openai-secret", typesafe_api_key="", openai_model="", typesafe_model="")


def native_input():
    return {
        "sessionId": "offline-session", "commandId": "offline-command",
        "request": {
            "request_contract": "mixroom_v3_context_v2", "original_request": "Lower the vocal by two decibels.",
            "conversation": [], "plan_schema_version": "plan_v3_prototype_2",
            "supported_command_types": ["row.adjust_gain_db", "transport.set_playing"], "resource_refs_enabled": False,
            "core_context": {
                "schema_version": "core_context_v3_prototype_1", "profile": "essential", "request_mode": "new_request", "state_digest": "offline-revision",
                "project": {"project_id": "offline-project", "bpm": 120, "beats_per_bar": 4, "beat_unit": 4, "row_capacity": {"current_rows": 1, "max_rows": 8}},
                "transport": {"playing": False, "recording": False, "metronome_enabled": False, "loop_enabled": False, "loop_start_ms": 0, "loop_end_ms": 0},
                "selection": {}, "rows": [{"row_id": 2, "name": "Vocal", "lane_kind": "audio", "gain_db": 0, "pan_signed": 0, "mix_processing_supported": True, "effects": [], "automation_targets": []}],
                "clips": [], "groups": [], "master": {}, "effects": [], "library_assets": [], "instruments": ["mixroom.warm_keys"], "instrument_catalog": [{"instrument_id": "mixroom.warm_keys"}], "runtime_capabilities": [],
            },
        },
        "sessionState": {"selectedTrackIds": [2], "comparison": {"available": True, "id": "offline-comparison"}, "notes": [{"id": "offline-note", "text": "Quieter intro", "completed": False}]},
    }


def provider_script(scenario="daw"):
    return "const scenario = " + json.dumps(scenario) + ";\n" + r"""
const blank = {duration_seconds:null,bars:null,row_id:null,hum:false,instrument_id:null,text:null,note_id:null};
const structured = value => Response.json({status:'completed',output:[{type:'message',role:'assistant',content:[{type:'output_text',text:JSON.stringify(value)}]}]});
globalThis.fetch = async (url, init) => {
  if (!['https://api.openai.com/v1/responses','https://api.typesafe.ai/v1/systemone'].includes(String(url))) throw new Error('unexpected provider');
  if (scenario === 'hang') await new Promise(resolve => setTimeout(resolve, 60000));
  if (String(url).includes('typesafe.ai')) {
    if (scenario === 'jev_down') return new Response('',{status:503});
    return Response.json({model:'jev-1.13.0',answers:{route:{type:'choice',choice:'daw',confidence:0.99,probabilities:{daw:0.99,session:0.005,mixed:0.003,uncertain:0.002}},whole_daw:{type:'noul',noul:0.99}}});
  }
  const body = JSON.parse(init.body);
  if (body.text) {
    if (['note','mixed','record_default','record_large'].includes(scenario)) {
      const recording = scenario.startsWith('record');
      return structured({route:'session_action',action_type:recording?'recording.start':'notes.add',arguments:{...blank,...(recording?{duration_seconds:scenario==='record_large'?61:null}:{text:'Try a quieter intro'})},message:'',complete_request_covered:true,includes_daw_edits:scenario==='mixed',includes_session_actions:true});
    }
    return structured({route:'daw',action_type:'none',arguments:blank,message:'',complete_request_covered:true,includes_daw_edits:true,includes_session_actions:false});
  }
  const plan = {schema_version:'plan_v3_prototype_2',outcome:'plan',user_message:'Lower the vocal by two decibels.',question_options:[],commands:[{command_id:'adjust-vocal',type:'row.adjust_gain_db',arguments:{row_id:scenario==='invalid_target'?99:2,delta_db:-2}}]};
  return Response.json({status:'completed',output:[{type:'function_call',name:'submit_plan_v3',call_id:'offline-call',arguments:JSON.stringify(plan)}],usage:{input_tokens:1,output_tokens:1}});
};
"""


@contextmanager
def mocked_worker(script):
    """Patch only the test process launcher; still run the actual Node worker."""
    real_spawn = asyncio.create_subprocess_exec
    children = []
    invocations = []
    with tempfile.TemporaryDirectory() as directory:
        fixture = Path(directory) / "offline-fetch.mjs"
        fixture.write_text(script)

        async def spawn(*args, **kwargs):
            invocations.append((args, kwargs))
            child = await real_spawn(args[0], "--import", str(fixture), *args[1:], **kwargs)
            children.append(child)
            return child

        with patch.object(asyncio, "create_subprocess_exec", side_effect=spawn):
            yield children, invocations


class PlannerWorkerTests(unittest.IsolatedAsyncioTestCase):
    async def test_real_worker_preserves_canonical_plan_without_exposing_credentials(self):
        with patch.dict(os.environ, {"NODE_OPTIONS": "--inspect", "DATABASE_SECRET": "unrelated-secret"}):
            with mocked_worker(provider_script()) as (children, invocations):
                result = await bridge.plan_voice_request(native_input(), SETTINGS)
        self.assertEqual(result["httpStatus"], 200, result)
        self.assertEqual(result["response"]["kind"], "daw_plan")
        self.assertEqual(result["response"]["response"]["plan"]["commands"][0]["arguments"], {"row_id": 2, "delta_db": -2})
        self.assertEqual(result["response"]["diagnostics"]["backend"], "local_python")
        self.assertNotIn(SETTINGS.openai_api_key, json.dumps(result))
        args, kwargs = invocations[0]
        self.assertNotIn(SETTINGS.openai_api_key, " ".join(args))
        self.assertEqual(kwargs["env"]["OPENAI_API_KEY"], SETTINGS.openai_api_key)
        self.assertNotIn("NODE_OPTIONS", kwargs["env"])
        self.assertNotIn("DATABASE_SECRET", kwargs["env"])
        self.assertEqual(children[0].returncode, 0)

    async def test_worker_enforces_typed_actions_mixed_requests_and_recording_limit(self):
        for scenario, kind in [("note", "session_action"), ("mixed", "clarify"), ("record_default", "session_action"), ("record_large", "clarify")]:
            with self.subTest(scenario=scenario), mocked_worker(provider_script(scenario)):
                result = await bridge.plan_voice_request(native_input(), SETTINGS)
                self.assertEqual(result["httpStatus"], 200, result)
                self.assertEqual(result["response"]["kind"], kind)
                if scenario == "record_default":
                    self.assertEqual(result["response"]["action"]["arguments"]["duration_seconds"], 10)

    async def test_unknown_daw_target_is_rejected_by_canonical_validator(self):
        with mocked_worker(provider_script("invalid_target")):
            result = await bridge.plan_voice_request(native_input(), SETTINGS)
        self.assertEqual(result["httpStatus"], 502)
        self.assertEqual(result["response"]["error"]["code"], "v3_planner_contract_invalid")

    async def test_optional_jev_fast_route_and_provider_failure_are_disclosed(self):
        settings = SimpleNamespace(**{**vars(SETTINGS), "typesafe_api_key": "offline-jev-secret"})
        for scenario, expected in [("daw", "daw"), ("jev_down", "provider_unavailable_fallback")]:
            with self.subTest(scenario=scenario), mocked_worker(provider_script(scenario)):
                result = await bridge.plan_voice_request(native_input(), settings)
                self.assertEqual(result["httpStatus"], 200, result)
                self.assertEqual(result["response"]["diagnostics"]["jevRoute"], expected)

    async def test_mix_passthrough_uses_real_worker_without_a_provider_key(self):
        actions = [{"type": "gain", "row": 2, "delta_db": -1}]
        result = await bridge.resolve_mix_request({"actions": actions}, SimpleNamespace())
        self.assertEqual(result["httpStatus"], 200, result)
        self.assertEqual(result["response"]["actions"], actions)
        self.assertEqual(result["response"]["fallback_reason"], "local_heuristic_passthrough")

    async def test_missing_keys_invalid_json_and_oversize_input_do_not_spawn(self):
        with patch.object(asyncio, "create_subprocess_exec") as spawn:
            self.assertEqual((await bridge.plan_voice_request(native_input(), SimpleNamespace()))["httpStatus"], 503)
            self.assertEqual((await bridge.resolve_mix_request({"actions": [], "invalid": float("nan")}, SETTINGS))["httpStatus"], 400)
            self.assertEqual((await bridge.resolve_mix_request({"actions": [], "huge": "x" * 4_600_000}, SETTINGS))["httpStatus"], 413)
            spawn.assert_not_called()

    async def test_timeout_reaps_the_real_worker_and_releases_capacity(self):
        with mocked_worker(provider_script("hang")) as (children, _), patch.object(bridge, "_TIMEOUT_SECONDS", 0.3):
            result = await bridge.plan_voice_request(native_input(), SETTINGS)
        self.assertEqual(result["httpStatus"], 504)
        self.assertIsNotNone(children[0].returncode)
        self.assertEqual((await bridge.resolve_mix_request({"actions": []}, SETTINGS))["httpStatus"], 200)

    async def test_stdout_and_stderr_caps_kill_worker_without_returning_raw_output(self):
        for stream, size in [("stdout", 2_100_000), ("stderr", 70_000)]:
            script = f"process.{stream}.write('s'.repeat({size})); setInterval(() => {{}}, 1000);"
            with self.subTest(stream=stream), mocked_worker(script) as (children, _):
                result = await bridge.resolve_mix_request({"actions": []}, SETTINGS)
            self.assertEqual(result["response"]["error"]["code"], "planner_output_limit")
            self.assertIsNotNone(children[0].returncode)
            self.assertLess(len(json.dumps(result)), 1000)

    async def test_cancellation_reaps_workers_and_third_concurrent_job_is_rejected(self):
        with mocked_worker(provider_script("hang")) as (children, _):
            tasks = [asyncio.create_task(bridge.plan_voice_request(native_input(), SETTINGS)) for _ in range(2)]
            for _ in range(100):
                if len(children) == 2:
                    break
                await asyncio.sleep(0.01)
            self.assertEqual(len(children), 2)
            busy = await bridge.plan_voice_request(native_input(), SETTINGS)
            self.assertEqual(busy["response"]["error"]["code"], "planner_busy")
            for task in tasks:
                task.cancel()
            results = await asyncio.gather(*tasks, return_exceptions=True)
            self.assertTrue(all(isinstance(result, asyncio.CancelledError) for result in results))
            self.assertTrue(all(child.returncode is not None for child in children))


if __name__ == "__main__":
    unittest.main()
