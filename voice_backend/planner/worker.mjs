// One JSON request and one JSON response per worker. No long-lived HTTP service.
import { planVoiceRequest, resolveMixRequest } from './planner.ts';

const INPUT_LIMIT = 4_600_000;
const OUTPUT_LIMIT = 2_000_000;
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const failure = (code, message, httpStatus = 502) => ({ httpStatus, response: { error: { code, message } } });
let result;
try {
  const chunks = []; let size = 0;
  for await (const chunk of process.stdin) {
    size += chunk.length;
    if (size > INPUT_LIMIT) throw new Error('input_limit');
    chunks.push(chunk);
  }
  const input = JSON.parse(Buffer.concat(chunks).toString('utf8'));
  if (!object(input) || Object.keys(input).some(key => !['mode', 'payload'].includes(key)) || !object(input.payload)) {
    result = failure('planner_request_invalid', 'A bounded planner request is required.', 400);
  } else {
    // Environment comes from the Python server's validated settings. Neither the
    // request nor the command line can choose provider URLs or inject a fetcher.
    const config = {
      openAiApiKey: process.env.OPENAI_API_KEY || undefined,
      jevApiKey: process.env.TYPESAFE_API_KEY || undefined,
      openAiModel: process.env.OPENAI_MODEL || undefined,
      jevModel: process.env.TYPESAFE_MODEL || undefined,
    };
    if (input.mode === 'plan') result = await planVoiceRequest(input.payload, config);
    else if (input.mode === 'mix') result = await resolveMixRequest(input.payload, config);
    else result = failure('planner_mode_unsupported', 'Unsupported planner operation.', 400);
  }
} catch {
  // Never emit exceptions, input, environment values, or raw provider responses.
  result = failure('planner_worker_failed', 'The planner could not complete this request.');
}
let output = JSON.stringify(result);
if (Buffer.byteLength(output, 'utf8') > OUTPUT_LIMIT) output = JSON.stringify(failure('planner_output_limit', 'The planner response exceeded its size limit.'));
process.stdout.write(output + '\n');
