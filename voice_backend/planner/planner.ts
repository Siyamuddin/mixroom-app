import { createDawState } from './assets/daw-config.js';
import { prepareRequest as prepareDawRequest } from './assets/daw-prepare.js';
import { readProviderResponse } from './assets/daw-read.js';
import { prepareContinuation } from './assets/daw-lookup.js';
import { finalizePlan } from './assets/daw-validate.js';
import { prepareRequest as prepareVoiceRequest, routeJev, routeOpenAi, wrapDawResponse } from './assets/voice-router.js';

type JsonObject = Record<string, unknown>;
// The generated JavaScript modules preserve the existing native planner's full
// schema and validators. This module is their typed edge I/O boundary.
type Stage = Record<string, any>;
export type PlannerInput = {
  sessionId: string;
  commandId: string;
  request: JsonObject;
  sessionState: JsonObject;
};
export type PlannerConfig = {
  openAiApiKey?: string;
  jevApiKey?: string;
  lovableApiKey?: string;
  openAiModel?: string;
  jevModel?: string;
  fetcher?: typeof fetch;
};
export type PlannerResult = { httpStatus: number; response: JsonObject };

const OPENAI_URL = 'https://api.openai.com/v1/responses';
const TYPESAFE_URL = 'https://api.typesafe.ai/v1/systemone';
const MAX_BYTES = 4_500_000;
const MAX_PROVIDER_BYTES = 1_000_000;
const REQUEST_TIMEOUT_MS = 70_000;
const encoder = new TextEncoder();

function object(value: unknown): value is JsonObject {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}
function error(code: string, message: string, httpStatus = 502): PlannerResult {
  return { httpStatus, response: { error: { code, message } } };
}
function bytes(value: unknown): number { return encoder.encode(JSON.stringify(value)).byteLength; }

/** Native ownership/revocation/revision checks remain in the authenticated relay. */
export function buildVoiceContextRequest(input: PlannerInput): JsonObject {
  const request = input.request;
  if (request.request_contract === 'mixroom_voice_context_v1') return request;
  if (request.request_contract !== 'mixroom_v3_context_v2') throw new Error('unsupported_native_contract');
  const core = object(request.core_context) ? request.core_context : {};
  const project = object(core.project) ? core.project : {};
  const transport = object(core.transport) ? core.transport : {};
  const state = input.sessionState;
  const comparison = object(state.comparison) ? state.comparison : {};
  const selection = Array.isArray(state.selectedTrackIds) ? state.selectedTrackIds : [];
  const selectedRow = selection.length === 1 && Number.isSafeInteger(selection[0]) ? selection[0] : null;
  return {
    request_contract: 'mixroom_voice_context_v1',
    original_request: request.original_request,
    core_context: core,
    conversation: request.conversation,
    supported_command_types: request.supported_command_types,
    resource_refs_enabled: request.resource_refs_enabled === true,
    ...(typeof request.prompt_trace_id === 'string' ? { prompt_trace_id: request.prompt_trace_id } : {}),
    voice_session_context: {
      projectId: project.project_id,
      revision: core.state_digest,
      selectedRowId: selectedRow,
      selectedClipId: null,
      recording: transport.recording === true,
      availableComparisonId: comparison.available === true && typeof comparison.id === 'string' ? comparison.id : null,
      notes: Array.isArray(state.notes) ? state.notes.slice(0, 200) : [],
    },
  };
}

async function readBoundedJson(response: Response): Promise<unknown> {
  const reader = response.body?.getReader();
  if (!reader) return null;
  const decoder = new TextDecoder(); let text = ''; let length = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > MAX_PROVIDER_BYTES) { await reader.cancel(); throw new Error('provider_response_limit'); }
    text += decoder.decode(value, { stream: true });
  }
  text += decoder.decode();
  return JSON.parse(text);
}

async function postProvider(
  url: string, apiKey: string, body: unknown, timeoutMs: number, fetcher: typeof fetch,
): Promise<Stage> {
  try {
    const response = await fetcher(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${apiKey}` },
      body: JSON.stringify(body),
      redirect: 'error',
      signal: AbortSignal.timeout(Math.max(1, Math.floor(timeoutMs))),
    });
    if (!response.ok) {
      await response.body?.cancel();
      // Provider payloads may include request content. Never surface them.
      return { statusCode: response.status, body: {} };
    }
    return { statusCode: response.status, body: await readBoundedJson(response) };
  } catch (cause) {
    const timeout = cause instanceof Error && ['TimeoutError', 'AbortError'].includes(cause.name);
    return { statusCode: timeout ? 504 : 502, body: {} };
  }
}

function finish(stage: Stage, diagnostics: JsonObject): PlannerResult {
  const httpStatus = Number.isInteger(stage.httpStatus) ? stage.httpStatus : 502;
  const response = object(stage.response) ? stage.response : { error: { code: 'voice_planner_invalid_state', message: 'Planning did not complete.' } };
  return { httpStatus, response: { ...response, diagnostics } };
}

/** One bounded orchestration path: optional Jev routing, then the existing V3
 * planner or a typed voice-session action. There are no workflow webhooks. */
export async function planVoiceRequest(input: PlannerInput, config: PlannerConfig): Promise<PlannerResult> {
  const startedAt = Date.now();
  const deadline = startedAt + REQUEST_TIMEOUT_MS;
  const remaining = (cap: number) => Math.max(1, Math.min(cap, deadline - Date.now()));
  const fetcher = config.fetcher ?? fetch;
  const diagnostics: JsonObject = {
    backend: 'local_python', reasoningProvider: 'openai',
    reasoningModel: config.openAiModel || 'gpt-5.4-2026-03-05',
    jevModel: config.jevApiKey ? config.jevModel || 'jev-1.13.0' : null,
    jevConfigured: Boolean(config.jevApiKey), jevAttempted: false,
    jevRoute: config.jevApiKey ? 'not_called' : 'not_configured',
  };
  if (!object(input) || !object(input.request) || !object(input.sessionState) || bytes(input.request) > MAX_BYTES) return error('voice_request_invalid', 'A bounded native project request is required.', 400);
  let normalized: JsonObject;
  try { normalized = buildVoiceContextRequest(input); }
  catch { return error('voice_request_contract_unsupported', 'Unsupported native planning contract.', 400); }
  let voice: Stage = prepareVoiceRequest(normalized, { openAiModel: config.openAiModel, jevModel: config.jevModel });
  if (voice.stage === 'respond') return finish(voice, diagnostics);
  if (!config.openAiApiKey) return error('planner_not_configured', 'The server-side OpenAI planner is not configured.', 503);
  if (voice.stage === 'classify') {
    if (config.jevApiKey) {
      diagnostics.jevAttempted = true;
      const classified = await postProvider(TYPESAFE_URL, config.jevApiKey, voice.jevRequest, remaining(3500), fetcher);
      voice = routeJev(classified, voice);
      diagnostics.jevRoute = voice.stage === 'daw' ? 'daw' : classified.statusCode >= 200 && classified.statusCode < 300 ? 'structured_fallback' : 'provider_unavailable_fallback';
    } else {
      voice = routeJev({ statusCode: 503 }, voice);
    }
  }
  if (voice.stage === 'extract') {
    if (Date.now() >= deadline) return error('voice_planner_timeout', 'Planning timed out before any edit was applied.', 504);
    const structured = await postProvider(OPENAI_URL, config.openAiApiKey, voice.openAiRequest, remaining(20000), fetcher);
    voice = routeOpenAi(structured, voice);
  }
  if (voice.stage === 'respond') return finish(voice, diagnostics);
  if (voice.stage !== 'daw') return error('voice_router_invalid_state', 'The voice request could not be routed.', 502);
  if (Date.now() >= deadline - 2000) return error('voice_planner_timeout', 'Planning timed out before any edit was applied.', 504);

  let daw: Stage = prepareDawRequest(createDawState(voice.dawRequest, {
    model: config.openAiModel,
    deadlineMs: remaining(60000),
    requestId: input.commandId,
  }));
  if (daw.stage === 'model') {
    const first = await postProvider(OPENAI_URL, config.openAiApiKey, daw.openaiBody, remaining(daw.timeoutMs), fetcher);
    daw = readProviderResponse(first, daw, false);
  }
  if (daw.stage === 'lookup') {
    daw = prepareContinuation(daw);
    if (daw.stage === 'model') {
      const final = await postProvider(OPENAI_URL, config.openAiApiKey, daw.openaiBody, remaining(daw.timeoutMs), fetcher);
      daw = readProviderResponse(final, daw, true);
    }
  }
  if (daw.stage === 'validate') daw = finalizePlan(daw);
  diagnostics.dawModelCalls = daw.modelCalls ?? 0;
  diagnostics.snapshotLookupUsed = daw.lookupUsed === true;
  diagnostics.elapsedMs = Date.now() - startedAt;
  if (daw.stage !== 'respond') return error('voice_daw_invalid_state', 'The DAW plan did not complete.', 502);
  if (daw.httpStatus !== 200) return finish(daw, diagnostics);
  return finish(wrapDawResponse({ statusCode: 200, body: daw.response }, voice), diagnostics);
}

/** Preserve the existing deterministic local mixing proposals. This route does
 * not pretend to be a trained magnitude model or an audio render/measure loop. */
export async function resolveMixRequest(payload: JsonObject, _config: PlannerConfig): Promise<PlannerResult> {
  if (!object(payload) || !Array.isArray(payload.actions) || payload.actions.length > 512 || payload.actions.some(action => !object(action)) || bytes(payload) > MAX_BYTES) return error('mix_request_invalid', 'A bounded list of proposed mix actions is required.', 400);
  return {
    httpStatus: 200,
    response: {
      actions: payload.actions,
      debug_entries: [],
      fallback_used: true,
      fallback_reason: 'local_heuristic_passthrough',
      observability: { mix_magnitude_model_source: 'local_heuristic_passthrough' },
      request_duration_ms: 0,
    },
  };
}
