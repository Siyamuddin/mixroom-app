'use strict';

// Port of mix_resolve.py's mix_refine_v1 feature contract. Deliberately retain
// historical defaults/units. Tests compare every value with the Python builder.
const MixFeatures = (() => {
  const clamp = (v, lo = 0, hi = 1) => Math.max(lo, Math.min(hi, v));
  const num = (v, fallback = 0) => {
    if (typeof v === 'boolean') return Number(v);
    if (v === null || v === undefined || (typeof v === 'string' && !v.trim())) return fallback;
    const n = Number(v); return Number.isNaN(n) ? fallback : n;
  };
  const lower = v => String(v ?? '').trim().toLowerCase();
  const stat = (r, k) => num(r.audio_stats?.[k]);
  const rms = r => num(r.features?.approx_rms);
  const quantile = (xs, q) => {
    if (!xs.length) return 0;
    const pos = clamp(q) * (xs.length - 1), lo = Math.floor(pos), hi = Math.ceil(pos);
    return lo === hi ? xs[lo] : xs[lo] * (1 - (pos - lo)) + xs[hi] * (pos - lo);
  };
  const sorted = xs => xs.sort((a, b) => a - b);
  const median = xs => quantile(xs, .5);
  const db = v => clamp((v + 80) / 80);
  const matrix = (m, a, b) => typeof m?.[a]?.[b] === 'number' ? m[a][b] : 0;
  function overlap(project, rows, tick = () => {}) {
    const sums = new Array(10).fill(0);
    const role = r => {
      let best = 'other', score = -Infinity;
      for (const [k, v] of Object.entries(r.role_probs || {})) {
        if ((typeof v === 'number' || typeof v === 'boolean') && Number(v) > score) {
          best = lower(k) || 'other'; score = Number(v);
        }
      }
      return best;
    };
    const share = (r, k) => clamp(Math.max(0, stat(r, k)) / Math.max(1e-9,
      ['low', 'lowmid', 'mid', 'high'].reduce((s, key) => s + Math.max(0, stat(r, key)), 0)));
    for (let i = 0; i < rows.length; i++) {
      tick();
      for (let j = i + 1; j < rows.length; j++) {
        const a = rows[i], b = rows[j], ai = a.row, bi = b.row;
        let weight = Math.max(0, matrix(project.overlap_ratio_matrix, ai, bi), matrix(project.overlap_ratio_matrix, bi, ai));
        weight = weight > 0 ? clamp(weight) :
          (matrix(project.overlap_matrix, ai, bi) === 1 || matrix(project.overlap_matrix, bi, ai) === 1 ? 1 : 0);
        if (weight <= 1e-6) continue;
        const gap = clamp(Math.abs(stat(a, 'centroid_hz') - stat(b, 'centroid_hz')) / 8000);
        const ar = Math.max(1e-6, rms(a)), br = Math.max(1e-6, rms(b));
        const ratio = Math.max(ar, br) / Math.min(ar, br);
        sums[0] += weight;
        sums[1] += ratio > 1.4 && gap < .20 ? weight : 0;
        sums[2] += gap < .12 ? weight : 0;
        sums[3] += gap * weight;
        sums[4] += clamp((ratio - 1) / 3) * weight;
        const ra = role(a), rb = role(b);
        sums[5] += ra !== rb && ra !== 'other' && rb !== 'other' ? weight : 0;
        ['low', 'lowmid', 'mid', 'high'].forEach((k, ix) => {
          const sa = share(a, k), sb = share(b, k);
          sums[6 + ix] += clamp(clamp(1 - Math.abs(sa - sb)) * clamp(2 * Math.min(sa, sb))) * weight;
        });
      }
    }
    if (sums[0] <= 1e-6) return new Array(10).fill(0);
    return [clamp(sums[0] / (rows.length * (rows.length - 1) / 2)), ...sums.slice(1).map(v => clamp(v / sums[0]))];
  }
  function context(project, goal, actions, strict, tick = () => {}) {
    const rows = project.rows.filter(r => r.hasAudio === true);
    const med = fn => median(sorted(rows.map(fn)));
    const ms = (k, fn = clamp) => med(r => fn(stat(r, k)));
    const levels = sorted(rows.map(rms));
    const scope = ['auto', 'row', 'group', 'master'].includes(lower(goal.target?.scope)) ? lower(goal.target.scope) : 'auto';
    const kind = (goal.intents || []).map(x => lower(x.kind)).find(Boolean) || 'balance';
    const ov = overlap(project, rows, tick);
    const maxRows = typeof project.max_rows === 'number' ? Math.trunc(project.max_rows) : Math.max(1, project.rows.length);
    const result = [
      clamp(num(goal.intensity, .5)), strict ? 1 : 0, clamp(num(project.bpm) / 240),
      clamp(rows.length / Math.max(1, maxRows)), median(levels),
      actions.filter(a => a.type === 'set_row_gain').length / 12,
      actions.filter(a => a.type === 'set_row_pan').length / 12,
      actions.filter(a => a.type.includes('effect')).length / 20,
      actions.filter(a => a.type.includes('master')).length / 12,
      ...['auto', 'row', 'master'].map(s => Number(scope === s)),
      ...['balance', 'gain', 'pan', 'eq', 'compressor', 'limiter', 'clipper', 'reverb', 'delay', 'deesser', 'distortion'].map(k => Number(kind === k)),
      med(r => clamp(num(r.features?.approx_crest) / 20)), clamp(quantile(levels, .75) - quantile(levels, .25)),
      ms('centroid_hz', v => clamp(v / 8000)), ms('zcr'), ms('sibilance', v => clamp(v / 5)),
      ms('bassiness', v => clamp(v / 5)), ms('hf_rms'), ms('st_rms_mean'), ms('st_rms_p95'),
      ms('st_rms_std'), ms('transient_density'), ...ov.slice(0, 6),
      clamp(ms('st_rms_p95') - ms('st_rms_mean')), ms('true_peak_dbfs', db),
      ms('integrated_lufs_est', db), ms('short_lufs_mean', db), ms('short_lufs_p95', db),
      ms('lra_est', v => clamp(v / 40)), ms('clip_ratio'), ms('spectral_flatness'),
      ms('spectral_rolloff_hz', v => clamp(v / 8000)), ms('spectral_slope', v => clamp((v + 2) / 4)),
      ms('spectral_flux'), ms('phase_corr', v => clamp((v + 1) / 2)), ms('side_ratio', v => clamp(v / 2)),
      ms('stereo_imbalance'), ms('silence_ratio'), ms('onset_rate_hz', v => clamp(v / 20)),
      ms('noise_floor_dbfs', db), ms('spectral_bandwidth_hz', v => clamp(v / 8000)), ...ov.slice(6),
    ];
    if (result.length !== 62 || result.some(v => !Number.isFinite(v))) throw Error('feature_contract_mismatch');
    return result;
  }
  const actionTypes = ['set_row_gain', 'set_row_pan', 'set_master_gain', 'set_master_pan',
    'adjust_effect_param_by_name', 'adjust_master_effect_param_by_name', 'ensure_effect', 'ensure_master_effect',
    'delete_effect', 'delete_master_effect', 'hard_reset_row_fx', 'hard_reset_master_fx'];
  // Historical positional lookup is retained ONLY for model features/parity.
  // The policy resolves execution targets by their explicit row field instead.
  function legacyRow(project, ix) {
    return project.rows[ix] || project.rows.find(r => r.row === ix);
  }
  function legacyParameter(project, a) {
    const d = a.data, token = lower(d.effect_name_contains);
    const chain = a.type.includes('master') ? project.master_effects : legacyRow(project, d.row)?.effects;
    const effect = (chain || []).find(e => token && lower(e.name).includes(token));
    const exact = lower(d.param_name), fuzzy = (d.param_name_contains_any || []).map(lower).filter(Boolean);
    return effect?.parameters?.find(p => (exact && lower(p.name) === exact) || fuzzy.some(t => lower(p.name).includes(t)));
  }
  function magnitude(project, a) {
    const d = a.data;
    if (lower(d.mode || 'delta') !== 'set') {
      return Math.abs(typeof d.delta === 'number' ? d.delta : typeof d.delta_norm === 'number' ? d.delta_norm : 1);
    }
    if (typeof d.value !== 'number') return 1;
    if (a.type === 'set_row_gain' || a.type === 'set_row_pan') {
      const r = legacyRow(project, d.row);
      if (!r) return 1;
      return Math.abs(d.value - num(r.mix?.[a.type.endsWith('gain') ? 'gain_0to3' : 'pan_0to1'], a.type.endsWith('gain') ? 0 : .5));
    }
    if (a.type === 'set_master_gain') return Math.abs(d.value - num(project.master_gain_0to3, 1));
    if (a.type === 'set_master_pan') return Math.abs(d.value - num(project.master_pan_0to1, .5));
    if (a.type.startsWith('adjust_')) {
      const p = legacyParameter(project, a);
      if (typeof p?.value === 'number' || typeof p?.value === 'boolean') return Math.abs(d.value - Number(p.value));
    }
    return 1;
  }
  function action(project, a) {
    return [clamp(magnitude(project, a), 0, 3), Number(a.type.includes('master')),
      ...actionTypes.map(t => Number(a.type === t)), Number(!actionTypes.includes(a.type))];
  }
  return {context, action, magnitude, overlap};
})();
if (typeof module !== 'undefined') module.exports = MixFeatures;
