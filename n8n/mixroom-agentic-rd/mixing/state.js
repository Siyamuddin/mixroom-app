'use strict';

const MixState = (() => {
  const object = v => v !== null && typeof v === 'object' && !Array.isArray(v);
  const number = v => typeof v === 'number' && Number.isFinite(v);
  const clone = v => JSON.parse(JSON.stringify(v));
  function tick(s) {
    if (Date.now() - s.startedAt >= s.mixConfig.deadlineMs) throw Error('mix_refinement_timeout');
  }
  function error(s, code, status = 400) {
    s.done = true; s.httpStatus = status; s.errorCode = code;
    s.response = {error: {code}};
    return s;
  }
  function fallback(s, reason) {
    s.done = true; s.fallbackReason = reason;
    s.candidateActions = clone(s.body.actions);
    s.debugEntries = s.body.actions.map((a, i) => ({action_index: i, action_type: a.type,
      before: clone(a), after: clone(a), final_scale: 1, decision: reason, dropped: false}));
    return s;
  }
  function finiteTree(value, depth = 0) {
    if (depth > 48) return false;
    if (typeof value === 'number') return Number.isFinite(value);
    if (Array.isArray(value)) return value.every(v => finiteTree(v, depth + 1));
    if (object(value)) return Object.entries(value).every(([k, v]) =>
      !['__proto__', 'prototype', 'constructor'].includes(k) && finiteTree(v, depth + 1));
    return true;
  }
  const actionTypes = new Set(['set_row_gain', 'set_row_pan', 'ensure_effect', 'delete_effect',
    'adjust_effect_param_by_name', 'hard_reset_row_fx', 'set_master_gain', 'set_master_pan',
    'ensure_master_effect', 'delete_master_effect', 'adjust_master_effect_param_by_name', 'hard_reset_master_fx']);
  function validate(s) {
    const b = s.body;
    if (!object(b) || !finiteTree(b)) return error(s, 'mix_request_invalid');
    if (Buffer.byteLength(JSON.stringify(b), 'utf8') > s.mixConfig.maxRequestBytes) return error(s, 'mix_request_limit', 413);
    if (!object(b.project_state) || !Array.isArray(b.project_state.rows) || !object(b.goal) ||
        !Array.isArray(b.actions) || typeof b.strict !== 'boolean' || b.mix_feature_contract_version !== 'mix_refine_v1')
      return error(s, 'mix_request_contract_invalid');
    const p = b.project_state, g = b.goal;
    if (!object(g.target) || !Array.isArray(g.intents) || g.intents.some(i => !object(i) || typeof i.kind !== 'string') ||
        (g.style_tags !== undefined && (!Array.isArray(g.style_tags) || g.style_tags.some(t => typeof t !== 'string'))) ||
        (g.intensity !== undefined && (!number(g.intensity) || g.intensity < 0 || g.intensity > 1)))
      return error(s, 'mix_goal_invalid');
    const rows = new Set();
    const validEffects = es => es === undefined || (Array.isArray(es) && es.every(e => object(e) &&
      (e.parameters === undefined || (Array.isArray(e.parameters) && e.parameters.every(object)))));
    for (const row of p.rows) {
      if (!object(row) || !Number.isSafeInteger(row.row) || row.row < 0 || rows.has(row.row) ||
          !validEffects(row.effects) || (row.mix !== undefined && !object(row.mix)) ||
          (row.features !== undefined && !object(row.features)) || (row.audio_stats !== undefined && !object(row.audio_stats)) ||
          (row.role_probs !== undefined && !object(row.role_probs))) return error(s, 'mix_rows_invalid');
      rows.add(row.row);
    }
    if (!validEffects(p.master_effects) || (p.group_buses !== undefined &&
        (!Array.isArray(p.group_buses) || p.group_buses.some(x => !object(x) || !Array.isArray(x.row_indices)))))
      return error(s, 'mix_project_invalid');
    if (g.target.scope === 'row' && (!Number.isSafeInteger(g.target.row_index) || !rows.has(g.target.row_index)))
      return error(s, 'mix_goal_target_invalid');
    for (const a of b.actions) {
      if (!object(a) || !actionTypes.has(a.type) || !object(a.data)) return error(s, 'mix_action_invalid');
      const d = a.data, master = a.type.includes('master');
      if (!master && (!Number.isSafeInteger(d.row) || !rows.has(d.row))) return error(s, 'mix_action_target_invalid');
      if (g.target.scope === 'master' && !master) return error(s, 'mix_action_target_invalid');
      if (g.target.scope === 'row' && (master || d.row !== g.target.row_index)) return error(s, 'mix_action_target_invalid');
      if (d.mode !== undefined && !['set', 'delta'].includes(d.mode)) return error(s, 'mix_action_mode_invalid');
      for (const k of ['value', 'delta', 'value_norm', 'delta_norm', 'clamp_min', 'clamp_max', 'refinement_scale'])
        if (d[k] !== undefined && !number(d[k])) return error(s, 'mix_action_number_invalid');
      if (a.type.startsWith('set_') || a.type.startsWith('adjust_')) {
        const set = d.mode === 'set';
        const keys = a.type.startsWith('set_') ? [set ? 'value' : 'delta'] : set ? ['value', 'value_norm'] : ['delta', 'delta_norm'];
        if (keys.filter(k => number(d[k])).length !== 1) return error(s, 'mix_action_amount_invalid');
      }
      if (a.type.includes('effect') && (typeof d.effect_name_contains !== 'string' || !d.effect_name_contains.trim()))
        return error(s, 'mix_effect_selector_invalid');
      if (d.param_name !== undefined && typeof d.param_name !== 'string') return error(s, 'mix_parameter_selector_invalid');
      if (d.param_name_contains_any !== undefined && (!Array.isArray(d.param_name_contains_any) ||
          d.param_name_contains_any.some(x => typeof x !== 'string'))) return error(s, 'mix_parameter_selector_invalid');
    }
    s.validatedRequest = true;
    if (!['passthrough', 'shadow', 'candidate'].includes(s.mixConfig.mode) ||
        !number(s.mixConfig.minScale) || !number(s.mixConfig.maxScale) || s.mixConfig.minScale < .5 ||
        s.mixConfig.maxScale > 1 || s.mixConfig.minScale > s.mixConfig.maxScale ||
        !Array.isArray(s.mixConfig.candidateProjectIds)) return fallback(s, 'mix_configuration_invalid');
    if (!b.actions.length) return fallback(s, 'mix_empty_actions');
    if (b.actions.length > s.mixConfig.maxActions) return fallback(s, 'mix_action_capacity');
    if (s.mixConfig.mode === 'passthrough') return fallback(s, 'n8n_rd_passthrough');
    if (g.reference_target != null) return fallback(s, 'reference_match_bypass');
    if ((g.execution_profile || 'producer_safe') !== 'producer_safe' ||
        !['subtle', 'noticeable'].includes(g.audibility || 'noticeable') || (g.style_tags || []).length ||
        g.destructive_ok === true || g.reset_fx === true) return fallback(s, 'mix_profile_bypass');
    return s;
  }
  function finish(s) {
    if (s.response?.error) return s;
    const config = s.mixConfig, projectId = s.body.project_id;
    const allowed = typeof projectId === 'string' && projectId.trim() && config.candidateProjectIds.includes(projectId);
    const mode = config.mode === 'candidate' && !allowed ? 'shadow' : config.mode;
    const enabled = mode === 'candidate' && !s.fallbackReason;
    const reason = s.fallbackReason || (mode === 'shadow' ? 'n8n_mix_shadow' : '');
    const actual = enabled ? s.candidateActions : s.body.actions;
    // debug_entries describe returned actions. Shadow candidates live only in
    // execution data, not the app's producer-training trace.
    const entries = (s.debugEntries || []).map(d => enabled ? d : ({...d, after: clone(d.before), final_scale: 1,
      decision: reason || 'n8n_rd_passthrough', dropped: false}));
    const duration = Math.max(0, Date.now() - s.startedAt);
    s.httpStatus = 200; s.hybridRoute = `mix_${mode}`;
    s.response = {actions: actual, debug_entries: entries, fallback_used: !enabled, fallback_reason: reason,
      observability: {mix_magnitude_model_source: 'n8n_embedded_v1', mix_feature_contract_version: 'mix_refine_v1',
        mix_magnitude_model_bundle_version: config.bundleVersion, mix_refinement_mode: mode,
        mix_candidate_changed_count: s.debugEntries?.filter(d => d.decision === 'bounded_refine').length || 0,
        mix_refine_elapsed_ms: duration}, request_duration_ms: duration};
    s.shadowComparison = {mode, candidate_actions: s.candidateActions, candidate_debug_entries: s.debugEntries,
      model_hashes: config.modelHashes, fallback_reason: s.fallbackReason || null};
    delete s.modelBundle; delete s.featureVectors; delete s.predictions;
    return s;
  }
  return {object, number, clone, tick, error, fallback, validate, finish, finiteTree};
})();
if (typeof module !== 'undefined') module.exports = MixState;
