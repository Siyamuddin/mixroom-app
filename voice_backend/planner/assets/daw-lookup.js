// Port of MixRoom ai-v4 contract-6 pure planner logic. No workflow runtime or I/O.
function utf8ByteLength(value) { return new TextEncoder().encode(value).byteLength; }
'use strict';

// Pure helpers for one immutable core_context_v3_prototype_1 request snapshot.
// Pure snapshot lookup: no runtime dependencies or I/O.
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


function errorResult(code, status = 502, state = {}) {
  return { ...state, stage: 'respond', httpStatus: status, response: { error: { code } }, errorCode: code };
}


function prepareContinuation(state) {
  try {
    if (!state.lookupArguments || Object.keys(state.lookupArguments).join(',') !== 'queries') return errorResult('v3_context_lookup_invalid', 502, state);
    const details = readSnapshot(state.request.core_context, state.lookupArguments.queries, state.config);
    const remaining = state.deadline - Date.now() - state.config.responseReserveMs;
    if (remaining < 1000) return errorResult('v3_upstream_timeout', 504, state);
    const openaiBody = { ...state.openaiBody,
      input: [...state.openaiBody.input, ...state.providerOutput,
        { type: 'function_call_output', call_id: state.lookupCallId, output: JSON.stringify(details) }],
      tools: [state.planTool], tool_choice: { type: 'function', name: 'submit_plan_v3' }
    };
    return { ...state, openaiBody, timeoutMs: remaining, stage: 'model', lookupUsed: true };
  } catch (error) {
    const capacity = String(error.code || '').includes('limit');
    return errorResult(capacity ? 'v3_context_request_limit' : 'v3_context_lookup_invalid', capacity ? 413 : 502, state);
  }
}



export { prepareContinuation };
