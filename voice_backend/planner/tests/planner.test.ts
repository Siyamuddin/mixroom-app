import test from 'node:test';
import assert from 'node:assert/strict';
import { buildVoiceContextRequest, planVoiceRequest, resolveMixRequest } from '../planner.ts';
import type { PlannerInput } from '../planner.ts';
import { blankArguments } from '../assets/voice-router.js';

function input(text = 'Turn the vocal down two decibels.'): PlannerInput {
  return {
    sessionId: 'offline-session', commandId: 'offline-command',
    request: {
      request_contract: 'mixroom_v3_context_v2', original_request: text,
      conversation: [], plan_schema_version: 'plan_v3_prototype_2',
      supported_command_types: ['row.adjust_gain_db', 'transport.set_playing'], resource_refs_enabled: false,
      core_context: {
        schema_version: 'core_context_v3_prototype_1', profile: 'essential', request_mode: 'new_request', state_digest: 'offline-project-revision',
        project: { project_id: 'offline-project', bpm: 120, beats_per_bar: 4, beat_unit: 4, row_capacity: { current_rows: 1, max_rows: 8 } },
        transport: { playing: false, recording: false, metronome_enabled: false, loop_enabled: false, loop_start_ms: 0, loop_end_ms: 0 },
        selection: {}, rows: [{ row_id: 2, name: 'Vocal', lane_kind: 'audio', gain_db: 0, pan_signed: 0, mix_processing_supported: true, effects: [], automation_targets: [] }],
        clips: [], groups: [], master: {}, effects: [], library_assets: [], instruments: ['mixroom.warm_keys'], instrument_catalog: [{ instrument_id: 'mixroom.warm_keys' }], runtime_capabilities: [],
      },
    },
    sessionState: { selectedTrackIds: [2], transport: { recording: false }, comparison: { available: true, id: 'offline-comparison' }, notes: [{ id: 'offline-note', text: 'Quieter intro', completed: false }] },
  };
}
function decision(type: string, args = {}, extra = {}) {
  return { route: 'session_action', action_type: type, arguments: { ...blankArguments(), ...args }, message: '', complete_request_covered: true, includes_daw_edits: false, includes_session_actions: true, ...extra };
}
const dawDecision = () => decision('none', {}, { route: 'daw', includes_daw_edits: true, includes_session_actions: false });
const structured = (value: unknown) => Response.json({ status: 'completed', output: [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: JSON.stringify(value) }] }] });
const tool = (name: string, args: unknown) => Response.json({ status: 'completed', output: [{ type: 'function_call', name, call_id: 'offline-call', arguments: JSON.stringify(args) }], usage: { input_tokens: 1, output_tokens: 1 } });
const plan = (rowId = 2) => ({ schema_version: 'plan_v3_prototype_2', outcome: 'plan', user_message: 'Lower the vocal by two decibels.', question_options: [], commands: [{ command_id: 'adjust-vocal', type: 'row.adjust_gain_db', arguments: { row_id: rowId, delta_db: -2 } }] });
const jevDaw = () => Response.json({ model: 'jev-1.13.0', answers: { route: { type: 'choice', choice: 'daw', confidence: 0.99, probabilities: { daw: 0.99, session: 0.005, mixed: 0.003, uncertain: 0.002 } }, whole_daw: { type: 'noul', noul: 0.99 } } });

test('offline: native request builds matching voice context with project identity and notes', () => {
  const request = buildVoiceContextRequest(input());
  assert.equal(request.request_contract, 'mixroom_voice_context_v1');
  assert.deepEqual(request.voice_session_context, { projectId: 'offline-project', revision: 'offline-project-revision', selectedRowId: 2, selectedClipId: null, recording: false, availableComparisonId: 'offline-comparison', notes: [{ id: 'offline-note', text: 'Quieter intro', completed: false }] });
});

test('offline: direct OpenAI routing and canonical DAW plan preserve the native V3 contract', async () => {
  const calls: { url: string; body: Record<string, any>; headers: Headers }[] = [];
  const fetcher: typeof fetch = async (url, init) => {
    const body = JSON.parse(String(init?.body)); calls.push({ url: String(url), body, headers: new Headers(init?.headers) });
    return body.text ? structured(dawDecision()) : tool('submit_plan_v3', plan());
  };
  const output = await planVoiceRequest(input(), { openAiApiKey: 'offline-openai-key', fetcher });
  assert.equal(output.httpStatus, 200, JSON.stringify(output));
  assert.equal(output.response.kind, 'daw_plan');
  assert.deepEqual((output.response.response as Record<string, any>).plan, plan());
  assert.equal(calls.length, 2);
  assert.ok(calls.every(call => call.url === 'https://api.openai.com/v1/responses'));
  assert.ok(calls.every(call => call.headers.get('Authorization') === 'Bearer offline-openai-key'));
  assert.equal(calls[1].body.tools[0].name, 'submit_plan_v3');
  assert.equal(calls[1].body.store, false);
  assert.equal((output.response.diagnostics as Record<string, unknown>).jevAttempted, false);
  assert.equal((output.response.diagnostics as Record<string, unknown>).reasoningModel, 'gpt-5.4-2026-03-05');
  assert.equal((output.response.diagnostics as Record<string, unknown>).jevModel, null);
  assert.ok(!JSON.stringify(output).includes('offline-openai-key'));
});

test('offline: optional Jev fast routing skips extraction but keeps canonical DAW validation', async () => {
  const urls: string[] = [];
  const output = await planVoiceRequest(input(), { openAiApiKey: 'offline-openai-key', jevApiKey: 'offline-jev-key', fetcher: async (url, init) => {
    urls.push(String(url));
    if (String(url).includes('typesafe.ai')) {
      assert.equal(new Headers(init?.headers).get('Authorization'), 'Bearer offline-jev-key');
      return jevDaw();
    }
    assert.equal(JSON.parse(String(init?.body)).text, undefined);
    return tool('submit_plan_v3', plan());
  } });
  assert.equal(output.httpStatus, 200, JSON.stringify(output));
  assert.deepEqual(urls, ['https://api.typesafe.ai/v1/systemone', 'https://api.openai.com/v1/responses']);
  assert.equal((output.response.diagnostics as Record<string, unknown>).jevRoute, 'daw');
  assert.equal((output.response.diagnostics as Record<string, unknown>).jevModel, 'jev-1.13.0');
});

test('offline: missing or unavailable Jev falls back honestly to structured OpenAI', async () => {
  const output = await planVoiceRequest(input('Add a note: quieter intro'), { openAiApiKey: 'offline-key', jevApiKey: 'offline-jev-key', fetcher: async url => String(url).includes('typesafe.ai') ? new Response('', { status: 503 }) : structured(decision('notes.add', { text: 'Quieter intro' })) });
  assert.equal(output.response.kind, 'session_action');
  assert.equal((output.response.diagnostics as Record<string, unknown>).jevRoute, 'provider_unavailable_fallback');
});

test('offline: a note about an edit is a note, while mixed notes and edits return clarification', async () => {
  for (const mixed of [false, true]) {
    const output = await planVoiceRequest(input(), { openAiApiKey: 'offline-key', fetcher: async () => structured(decision('notes.add', { text: 'Turn up the chorus later' }, { includes_daw_edits: mixed })) });
    assert.equal(output.response.kind, mixed ? 'clarify' : 'session_action');
    if (mixed) assert.equal(output.response.action, undefined);
  }
});

test('offline: recording uses bounded duration or the native default and a known target', async () => {
  for (const [args, kind] of [[{ duration_seconds: 8, hum: true }, 'session_action'], [{ duration_seconds: 0.5 }, 'clarify'], [{ duration_seconds: 61 }, 'clarify'], [{}, 'session_action'], [{ bars: 40 }, 'clarify'], [{ duration_seconds: 8, row_id: 99 }, 'clarify']] as const) {
    const output = await planVoiceRequest(input(), { openAiApiKey: 'offline-key', fetcher: async () => structured(decision('recording.start', args)) });
    assert.equal(output.response.kind, kind, JSON.stringify(output));
  }
});

test('offline: canonical validator rejects nonexistent DAW target before native execution', async () => {
  const output = await planVoiceRequest(input(), { openAiApiKey: 'offline-key', fetcher: async (_url, init) => JSON.parse(String(init?.body)).text ? structured(dawDecision()) : tool('submit_plan_v3', plan(99)) });
  assert.equal(output.httpStatus, 502);
  assert.equal((output.response.error as Record<string, unknown>).code, 'v3_planner_contract_invalid');
  assert.equal(output.response.kind, undefined);
});

test('offline: one immutable snapshot lookup is supported, a second lookup is rejected', async () => {
  for (const extraLookup of [false, true]) {
    let call = 0;
    const output = await planVoiceRequest(input(), { openAiApiKey: 'offline-key', fetcher: async (_url, init) => {
      const body = JSON.parse(String(init?.body));
      if (body.text) return structured(dawDecision());
      call++;
      if (call === 1 || extraLookup) return tool('get_project_details', { queries: [{ kind: 'rows', row_ids: [2] }] });
      assert.ok(body.input.some((item: Record<string, unknown>) => item.type === 'function_call_output'));
      assert.equal(body.tool_choice.name, 'submit_plan_v3');
      return tool('submit_plan_v3', plan());
    } });
    assert.equal(output.httpStatus, extraLookup ? 502 : 200, JSON.stringify(output));
    assert.equal(call, 2);
  }
});

test('offline: unavailable keys and malformed provider output return explicit failures', async () => {
  let calls = 0;
  const missing = await planVoiceRequest(input(), { fetcher: async () => { calls++; return new Response(); } });
  assert.equal(missing.httpStatus, 503); assert.equal(calls, 0);
  const malformed = await planVoiceRequest(input(), { openAiApiKey: 'offline-key', fetcher: async () => Response.json({ status: 'incomplete', output: [] }) });
  assert.equal(malformed.httpStatus, 502); assert.equal(malformed.response.action, undefined);
  const unknown = await planVoiceRequest(input(), { openAiApiKey: 'offline-key', fetcher: async () => structured(decision('native.exec')) });
  assert.equal(unknown.httpStatus, 502);
});

test('offline: mix compatibility preserves proposed local actions without claiming a learned model', async () => {
  const actions = [{ type: 'gain', row: 0, delta_db: -1 }];
  const output = await resolveMixRequest({ actions }, {});
  assert.equal(output.httpStatus, 200);
  assert.deepEqual(output.response.actions, actions);
  assert.equal(output.response.fallback_reason, 'local_heuristic_passthrough');
  assert.equal((await resolveMixRequest({ actions: ['invalid'] }, {})).httpStatus, 400);
});
