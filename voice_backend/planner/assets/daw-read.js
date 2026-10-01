// Port of MixRoom ai-v4 contract-6 pure planner logic. No workflow runtime or I/O.
function utf8ByteLength(value) { return new TextEncoder().encode(value).byteLength; }
function errorResult(code, status = 502, state = {}) {
  return { ...state, stage: 'respond', httpStatus: status, response: { error: { code } }, errorCode: code };
}


function readProviderResponse(raw, state, finalCall) {
  const isObject = value => value !== null && typeof value === 'object' && !Array.isArray(value);
  const next = { ...state, usage: { ...state.usage }, modelCalls: (state.modelCalls || 0) + 1 };
  if (Date.now() >= state.deadline) return errorResult('v3_upstream_timeout', 504, next);
  if (!isObject(raw)) return errorResult('v3_planner_response_invalid', 502, next);
  if (raw.error && !raw.statusCode) {
    const code = String(raw.error.code || raw.error.name || '');
    const message = typeof raw.error === 'string' ? raw.error : String(raw.error.message || '');
    const timeout = /timeout|timed out|ETIMEDOUT|ECONNABORTED/i.test(code + ' ' + message);
    return errorResult(timeout ? 'v3_upstream_timeout' : 'v3_upstream_unavailable', timeout ? 504 : 502, next);
  }
  const status = Number(raw.statusCode || 200);
  const body = raw.body || raw;
  if (!Number.isInteger(status)) return errorResult('v3_planner_response_invalid', 502, next);
  if (status < 200 || status >= 300) return errorResult(status === 408 || status === 504 ? 'v3_upstream_timeout' : status === 429 ? 'v3_upstream_rate_limited' : 'v3_upstream_unavailable', status === 408 || status === 504 ? 504 : status === 429 ? 503 : 502, next);
  if (!body || typeof body !== 'object' || body.error || body.status !== 'completed') return errorResult(body?.status === 'incomplete' ? 'v3_planner_output_incomplete' : 'v3_planner_response_invalid', 502, next);
  for (const k of ['input_tokens', 'output_tokens']) {
    const amount = Number(body.usage?.[k]);
    next.usage[k] = (state.usage?.[k] || 0) + (Number.isFinite(amount) && amount >= 0 ? amount : 0);
  }
  if (!Array.isArray(body.output) || body.output.some(x => !isObject(x) || typeof x.type !== 'string' || (Array.isArray(x.content) && x.content.some(p => !isObject(p))))) return errorResult('v3_planner_response_invalid', 502, next);
  const output = body.output;
  const refused = output.some(x => Array.isArray(x.content) && x.content.some(p => p.type === 'refusal'));
  if (refused) return errorResult('v3_planner_refused', 422, next);
  const calls = output.filter(x => x.type === 'function_call');
  if (calls.length !== 1) return errorResult('v3_planner_tool_contract_invalid', 502, next);
  const call = calls[0];
  let args;
  if (typeof call.arguments !== 'string') return errorResult('v3_planner_response_invalid', 502, next);
  try { args = JSON.parse(call.arguments); } catch (_) { return errorResult('v3_planner_response_invalid', 502, next); }
  if (call.name === 'submit_plan_v3') return { ...next, stage: 'validate', draft: args };
  if (call.name !== 'get_project_details' || finalCall || state.lookupUsed || typeof call.call_id !== 'string' || !call.call_id.trim()) return errorResult('v3_planner_tool_contract_invalid', 502, next);
  return { ...next, stage: 'lookup', lookupArguments: args, providerOutput: output, lookupCallId: call.call_id };
}



export { readProviderResponse };
