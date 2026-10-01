// Port of MixRoom ai-v4 contract-6 pure planner logic. No workflow runtime or I/O.
function utf8ByteLength(value) { return new TextEncoder().encode(value).byteLength; }
'use strict';

// Pure helpers for one immutable core_context_v3_prototype_1 request snapshot.
// Pure planner request preparation: no runtime dependencies or I/O.
class SnapshotContextError extends Error {
  constructor(code, details = {}) {
    super(code);
    this.name = 'SnapshotContextError';
    this.code = code;
    this.details = details;
  }
}

const SNAPSHOT_LIMITS = Object.freeze({
  maxCoreBytes: 4000000,
  maxCompactBytes: 500000,
  maxLookupBytes: 1000000,
  maxLookupQueries: 4,
  maxLookupIds: 512,
});

function snapshotLimits(config = {}) {
  const result = {};
  for (const [key, fallback] of Object.entries(SNAPSHOT_LIMITS)) {
    const value = config[key] === undefined ? fallback : config[key];
    if (!Number.isSafeInteger(value) || value < 1 || value > fallback) {
      throw new SnapshotContextError('snapshot_config_invalid', { field: key, maximum: fallback });
    }
    result[key] = value;
  }
  return result;
}

function snapshotObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function snapshotClone(value) {
  return JSON.parse(JSON.stringify(value));
}

// Count UTF-8 bytes, including astral characters, without a Node-only import.
function snapshotByteLength(value) {
  const json = JSON.stringify(value);
  let bytes = 0;
  for (const character of json) {
    const code = character.codePointAt(0);
    bytes += code <= 0x7f ? 1 : code <= 0x7ff ? 2 : code <= 0xffff ? 3 : 4;
  }
  return bytes;
}

function snapshotBound(value, limit, code) {
  const actual = snapshotByteLength(value);
  if (actual > limit) throw new SnapshotContextError(code, { actual_bytes: actual, max_bytes: limit });
  return value;
}

function snapshotArray(object, field, required = false) {
  const value = object[field];
  if (value === undefined && !required) return [];
  if (!Array.isArray(value)) {
    throw new SnapshotContextError('snapshot_shape_invalid', { field });
  }
  return value;
}

function snapshotIndex(items, idField, numeric = false) {
  const index = new Map();
  for (const item of items) {
    const id = snapshotObject(item) ? item[idField] : undefined;
    const valid = numeric ? Number.isSafeInteger(id) && id >= 0 : typeof id === 'string' && id.trim().length > 0;
    if (!valid || index.has(id)) {
      throw new SnapshotContextError('snapshot_identity_invalid', { field: idField, duplicate: index.has(id) });
    }
    index.set(id, item);
  }
  return index;
}

function inspectSnapshot(core, limits) {
  if (!snapshotObject(core)) throw new SnapshotContextError('snapshot_shape_invalid', { field: 'core_context' });
  snapshotBound(core, limits.maxCoreBytes, 'snapshot_core_limit');
  const rows = snapshotArray(core, 'rows', true);
  const clips = snapshotArray(core, 'clips', true);
  const effects = snapshotArray(core, 'effects');
  const assets = snapshotArray(core, 'library_assets');
  const instruments = snapshotArray(core, 'instrument_catalog');
  const indexes = {
    rows: snapshotIndex(rows, 'row_id', true),
    clips: snapshotIndex(clips, 'clip_id'),
    effects: snapshotIndex(effects, 'effect_id'),
    library_assets: snapshotIndex(assets, 'asset_id'),
  };
  snapshotIndex(instruments, 'instrument_id');
  for (const clip of clips) {
    if (!indexes.rows.has(clip.row_id)) {
      throw new SnapshotContextError('snapshot_reference_invalid', { field: 'clips.row_id', clip_id: clip.clip_id });
    }
    if (Object.hasOwn(clip, 'midi_notes') && !Array.isArray(clip.midi_notes)) {
      throw new SnapshotContextError('snapshot_shape_invalid', { field: 'clips.midi_notes', clip_id: clip.clip_id });
    }
  }
  return { rows, clips, effects, assets, instruments, indexes };
}

function snapshotPick(object, fields) {
  const result = {};
  for (const field of fields) if (Object.hasOwn(object, field)) result[field] = snapshotClone(object[field]);
  return result;
}

function snapshotOmit(object, fields) {
  return Object.fromEntries(Object.entries(object).filter(([key]) => !fields.includes(key)).map(([key, value]) => [key, snapshotClone(value)]));
}

function snapshotTimelineClip(clip) {
  const result = snapshotOmit(clip, ['start_beat']);
  if (Object.hasOwn(clip, 'start_beat')) result.timeline_start_beat = clip.start_beat;
  return result;
}

function compactSnapshotRow(row) {
  const result = snapshotOmit(row, ['audio_analysis', 'files', 'effects', 'automation_targets']);
  result.effects = snapshotArray(row, 'effects').map((effect) => {
    if (!snapshotObject(effect)) throw new SnapshotContextError('snapshot_shape_invalid', { field: 'rows.effects' });
    const compact = snapshotOmit(effect, ['parameters']);
    compact.parameters = snapshotArray(effect, 'parameters').map((parameter) => {
      if (!snapshotObject(parameter)) throw new SnapshotContextError('snapshot_shape_invalid', { field: 'rows.effects.parameters' });
      return snapshotPick(parameter, ['id', 'parameter_id', 'name', 'type', 'value', 'valueNormalized']);
    });
    return compact;
  });
  result.automation_targets = snapshotArray(row, 'automation_targets').map((target) => {
    if (!snapshotObject(target)) throw new SnapshotContextError('snapshot_shape_invalid', { field: 'rows.automation_targets' });
    return snapshotPick(target, ['id', 'label', 'isOrphan', 'uiVisible']);
  });
  result.detail_fields = ['effects', 'automation_targets', 'audio_analysis', 'files'].filter((field) => Object.hasOwn(row, field));
  return result;
}

function compactSnapshotClip(clip) {
  const result = snapshotTimelineClip(snapshotOmit(clip, ['midi_notes']));
  result.detail_fields = Object.hasOwn(clip, 'midi_notes') ? ['midi_notes'] : [];
  // The Dart builder omits midi_notes when its list is empty.
  if (clip.kind === 'midi' || Object.hasOwn(clip, 'midi_notes')) {
    result.midi_note_count = snapshotArray(clip, 'midi_notes').length;
  }
  return result;
}

function buildCompactContext(core, config = {}) {
  const limits = snapshotLimits(config);
  const { rows, clips, effects, assets, instruments } = inspectSnapshot(core, limits);
  const result = snapshotPick(core, [
    'schema_version', 'profile', 'state_digest', 'request_mode', 'project', 'transport',
    'selection', 'groups', 'master', 'instruments', 'capabilities', 'runtime_capabilities', 'pending_plan',
  ]);
  result.rows = rows.map(compactSnapshotRow);
  result.clips = clips.map(compactSnapshotClip);
  // Instrument facts are already small and include playable MIDI ranges.
  result.instrument_catalog = snapshotClone(instruments);
  result.effects = effects.map((effect) => ({
    ...snapshotOmit(effect, ['parameters']),
    parameter_ids: snapshotArray(effect, 'parameters').map((parameter) => {
      if (!snapshotObject(parameter) || typeof parameter.parameter_id !== 'string') {
        throw new SnapshotContextError('snapshot_shape_invalid', { field: 'effects.parameters.parameter_id' });
      }
      return parameter.parameter_id;
    }),
    detail_fields: Object.hasOwn(effect, 'parameters') ? ['parameters'] : [],
  }));
  result.library_assets = assets.map((asset) => ({
    ...snapshotPick(asset, ['asset_id', 'path', 'name', 'role', 'bpm']),
    detail_fields: Object.keys(asset).filter((field) => !['asset_id', 'path', 'name', 'role', 'bpm'].includes(field)),
  }));
  result.snapshot_details = {
    source: 'immutable_request_snapshot',
    complete_indexes: true,
    rows: rows.length,
    clips: clips.length,
    effects: effects.length,
    library_assets: assets.length,
    lookup: {
      tool: 'get_project_details',
      kinds: ['rows', 'clips', 'effects', 'library_assets'],
      max_queries: limits.maxLookupQueries,
      max_ids_per_query: limits.maxLookupIds,
      max_response_bytes: limits.maxLookupBytes,
      description: 'Batch all required details in one lookup. Rows include supplied analysis, full effect parameters and automation targets; clips include all supplied MIDI notes; effects include parameter definitions; library_assets include all supplied metadata. Omitted profile fields cannot be fetched from the app.',
    },
    timebase: {
      clip_placement: 'timeline_start_beat is an absolute project beat.',
      midi_notes: 'MIDI note start_beat is relative to its clip; do not subtract clip placement.',
    },
  };
  return snapshotBound(result, limits.maxCompactBytes, 'snapshot_compact_limit');
}

function readSnapshot(core, queries, config = {}) {
  const limits = snapshotLimits(config);
  const { indexes } = inspectSnapshot(core, limits);
  if (!Array.isArray(queries) || queries.length < 1 || queries.length > limits.maxLookupQueries) {
    throw new SnapshotContextError('snapshot_queries_limit', { min_queries: 1, max_queries: limits.maxLookupQueries });
  }
  const fields = { rows: 'row_ids', clips: 'clip_ids', effects: 'effect_ids', library_assets: 'asset_ids' };
  const results = queries.map((query, queryIndex) => {
    if (!snapshotObject(query) || !Object.hasOwn(fields, query.kind)) {
      throw new SnapshotContextError('snapshot_query_invalid', { query_index: queryIndex });
    }
    const field = fields[query.kind];
    if (Object.keys(query).length !== 2 || !Object.hasOwn(query, field)) {
      throw new SnapshotContextError('snapshot_query_invalid', { query_index: queryIndex, expected_fields: ['kind', field] });
    }
    const ids = query[field];
    if (!Array.isArray(ids) || ids.length < 1 || ids.length > limits.maxLookupIds) {
      throw new SnapshotContextError('snapshot_query_ids_limit', { query_index: queryIndex, min_ids: 1, max_ids: limits.maxLookupIds });
    }
    if (new Set(ids).size !== ids.length) {
      throw new SnapshotContextError('snapshot_query_ids_duplicate', { query_index: queryIndex });
    }
    for (const id of ids) {
      const valid = query.kind === 'rows' ? Number.isSafeInteger(id) && id >= 0 : typeof id === 'string' && id.trim().length > 0;
      if (!valid) throw new SnapshotContextError('snapshot_query_id_invalid', { query_index: queryIndex, field });
    }
    const missing = ids.filter((id) => !indexes[query.kind].has(id));
    if (missing.length) {
      throw new SnapshotContextError('snapshot_target_missing', { query_index: queryIndex, kind: query.kind, missing_ids: missing });
    }
    const items = ids.map((id) => {
      const item = indexes[query.kind].get(id);
      if (query.kind !== 'clips') return snapshotClone(item);
      const clip = snapshotTimelineClip(item);
      if (clip.kind === 'midi' && !Object.hasOwn(clip, 'midi_notes')) clip.midi_notes = [];
      return clip;
    });
    return { kind: query.kind, items };
  });
  return snapshotBound({ state_digest: core.state_digest ?? null, results }, limits.maxLookupBytes, 'snapshot_lookup_limit');
}


// Canonical schema helpers. Embedded before plan-validator.js; no modules or I/O.
function mrClone(value) { return JSON.parse(JSON.stringify(value)); }
function mrObject(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
function mrWalk(value, visit, path = '$') {
  visit(value, path);
  if (Array.isArray(value)) value.forEach((v, i) => mrWalk(v, visit, `${path}[${i}]`));
  else if (mrObject(value)) Object.entries(value).forEach(([k, v]) => mrWalk(v, visit, `${path}.${k}`));
}
const mrRuntimeGates = Object.freeze({
  'row.apply_phone_mic_cleanup': 'daw.audio_enhance',
  'clip.separate_stems': 'daw.stem_separate',
  'clip.convert_to_midi': 'daw.midi_compose.audio_to_midi',
});
const mrMidiCommands = new Set(['midi.transpose', 'midi.replace_notes', 'midi.append_notes', 'midi.chop_notes']);
const mrAudioCommands = new Set([
  'clip.trim_to_range', 'clip.glue', 'clip.separate_stems', 'clip.convert_to_midi',
  'clip.set_pitch_semitones', 'clip.adjust_pitch_semitones', 'clip.set_timeline_length_beats',
  'clip.scale_timeline_length', 'clip.set_source_tempo_bpm', 'clip.set_tempo_follow_mode',
  'clip.align_tempo_to_project', 'clip.trim_silence', 'clip.align_first_sound',
  'sample.replace', 'project.set_tempo_from_clip',
]);
const mrMixEffects = Object.freeze({balance:['EQ 3-Band','Compressor','Limiter'],clipper:['Clipper'],compressor:['Compressor'],deesser:['De-Esser'],delay:['Delay'],distortion:['Distortion'],eq:['EQ 3-Band','EQ Parametric'],gain:[],limiter:['Limiter'],pan:[],reverb:['Reverb']});
function mrCommandType(variant) { return variant.properties.type.enum[0]; }
function mrAllowedTypes(request, contracts) {
  const supported = new Set(request.supported_command_types || []);
  const runtime = new Set((request.core_context || {}).runtime_capabilities || []);
  return new Set(contracts.metadata.command_types.filter(type => supported.has(type) && (!mrRuntimeGates[type] || runtime.has(mrRuntimeGates[type]))));
}
function buildPlanTool(request, contracts) {
  const tool = mrClone(request.resource_refs_enabled === true ? contracts.refs : contracts.base);
  const allowed = mrAllowedTypes(request, contracts);
  tool.parameters.properties.commands.maxItems = 32;
  tool.parameters.properties.question_options.maxItems = 4;
  tool.parameters.properties.commands.items.anyOf = tool.parameters.properties.commands.items.anyOf.filter(v => allowed.has(mrCommandType(v)));
  if (!tool.parameters.properties.commands.items.anyOf.length) throw new Error('v3_command_surface_empty');
  for (const variant of tool.parameters.properties.commands.items.anyOf) {
    const type = mrCommandType(variant);
    if (['midi.create_clip','midi.replace_notes','midi.append_notes'].includes(type)) {
      mrWalk(variant, value => { if (mrObject(value) && value.properties && value.properties.notes) value.properties.notes.maxItems = 512; });
    }
  }
  tool.strict = true;
  return tool;
}

function errorResult(code, status = 502, state = {}) {
  return { ...state, stage: 'respond', httpStatus: status, response: { error: { code } }, errorCode: code };
}


function jsonBytes(value) {
  return utf8ByteLength(JSON.stringify(value), 'utf8');
}


function prepareRequest(state) {
  const request = state.request;
  const config = state.config;
  if (!request || typeof request !== 'object' || Array.isArray(request)) return errorResult('v3_request_invalid', 400, state);
  if (request.request_contract !== 'mixroom_v3_context_v2' || request.plan_schema_version !== 'plan_v3_prototype_2') return errorResult('v3_request_contract_unsupported', 400, state);
  if (typeof request.original_request !== 'string' || !request.original_request.trim()) return errorResult('v3_request_invalid', 400, state);
  if (!request.core_context || typeof request.core_context !== 'object' || Array.isArray(request.core_context)) return errorResult('v3_request_invalid', 400, state);
  const core = request.core_context;
  if (core.schema_version !== 'core_context_v3_prototype_1' || !['new_request', 'modify_pending_plan'].includes(core.request_mode)) return errorResult('v3_request_invalid', 400, state);
  if (core.request_mode === 'modify_pending_plan' && (!mrObject(core.pending_plan) || typeof core.modification_request !== 'string' || !core.modification_request.trim())) return errorResult('v3_request_invalid', 400, state);
  if (!Array.isArray(request.supported_command_types) || !request.supported_command_types.length || request.supported_command_types.some(x => typeof x !== 'string')) return errorResult('v3_request_invalid', 400, state);
  if (typeof request.resource_refs_enabled !== 'boolean' || !Array.isArray(request.conversation) || request.conversation.length > 12 || request.conversation.some(t => !t || !['user', 'assistant'].includes(t.role) || typeof t.content !== 'string')) return errorResult('v3_request_invalid', 400, state);
  if (jsonBytes(request) > config.maxRequestBytes || jsonBytes(request.core_context) > config.maxCoreBytes) return errorResult('v3_context_request_limit', 413, state);
  try {
    const compact = buildCompactContext(request.core_context, config);
    const planTool = buildPlanTool(request, state.contracts);
    const instructions = state.instructions + '\n\n' + config.plannerPolicy;
    const openaiBody = {
      model: config.model,
      instructions,
      input: [{ role: 'user', content: [
        { type: 'input_text', text: 'PROJECT_SNAPSHOT_JSON:\n' + JSON.stringify(compact) },
        { type: 'input_text', text: 'RECENT_CONVERSATION_JSON:\n' + JSON.stringify(request.conversation) },
        { type: 'input_text', text: 'ORIGINAL_REQUEST_VERBATIM:\n' + request.original_request },
        ...(core.request_mode === 'modify_pending_plan' ? [{ type: 'input_text', text: 'MODIFICATION_REQUEST_VERBATIM:\n' + core.modification_request }] : [])
      ] }],
      tools: [planTool, state.lookupTool],
      tool_choice: 'required', parallel_tool_calls: false,
      max_output_tokens: config.maxOutputTokens,
      store: false, truncation: 'disabled'
    };
    if (config.reasoningEffort) {
      openaiBody.reasoning = { effort: config.reasoningEffort };
      openaiBody.include = ['reasoning.encrypted_content'];
    }
    const deadline = state.startedAt + config.deadlineMs;
    const remaining = deadline - Date.now() - config.responseReserveMs;
    if (remaining < 1000) return errorResult('v3_upstream_timeout', 504, state);
    return { ...state, compact, planTool, openaiBody, deadline, timeoutMs: Math.min(config.firstCallTimeoutMs, remaining), stage: 'model', modelCalls: 0, usage: { input_tokens: 0, output_tokens: 0 } };
  } catch (error) {
    const capacity = String(error.code || '').includes('limit');
    return errorResult(capacity ? 'v3_context_request_limit' : 'v3_request_invalid', capacity ? 413 : 400, state);
  }
}



export { prepareRequest };
