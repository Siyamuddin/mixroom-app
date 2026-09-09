# V3 production measurement runbook

This runbook prepares a later, explicitly approved read-only measurement. It
does not authorize a deployment, production-log query, provider request, or
code change.

## Preconditions

1. Deploy the reviewed observability build only after separate approval and
   the normal test and change-set review. The deployment must not change the
   prompt, schema, model, retry, timeout, response, quota, billing, or HTTP API.
2. Confirm the deployed final request log includes the contract-6 metrics and
   contains no prompt, conversation, context, plan, resource, user, project,
   provider-response, or raw request data in the selected export fields.
3. Identify the CloudWatch log group for the physical Lambda created from the
   `ProxyResponsesFunction` resource. Do not guess a log-group name.

## Safe export

Use [`cloudwatch_v3_measurement.query`](cloudwatch_v3_measurement.query) with
CloudWatch Logs Insights. Export only the query result columns. Do not export
`@message`, full log events, users, projects, project hashes, request IDs,
provider response IDs, prompts, conversations, context, plans, resources, or
tool schemas.

Run non-overlapping time windows when a cohort would exceed the 10,000-row
query limit, then repeat `--cloudwatch-results` once per export. Keep the
exported JSON outside the repository, preferably under `/tmp`. Before
collecting a full cohort, inspect 10–20 selected rows for metric completeness
and field-level privacy. The analyzer fails closed on unknown or forbidden
columns.

The optional PostHog CSV must be privacy-filtered before export. Its only
permitted columns are:

- `timestamp`, `event`, `prompt_trace_id`, `ai_feature`
- `prompt_cycle_total_ms`, `error_code`, `success`
- `app_version`, `platform`

Do not include `project_id`, `user_id`, distinct IDs, event payloads, or any
other columns. `prompt_trace_id` is used only for an in-memory join and never
appears in generated reports.

## Offline analysis

Run the standard-library-only analyzer without AWS or network credentials:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tool/ai_v3_eval/analyze_v3_production_measurement.py \
  --cloudwatch-results /tmp/mixroom-v3-cloudwatch.json \
  --posthog-csv /tmp/mixroom-v3-posthog.csv \
  --output-json /tmp/mixroom-v3-measurement.json \
  --output-markdown /tmp/mixroom-v3-measurement.md
```

Omit `--posthog-csv` when client data is unavailable. Do not commit exports or
generated reports. The analyzer never modifies code or infrastructure.

## Evidence requirements

- Backend decisions require at least 300 eligible provider-bound requests over
  at least seven UTC calendar days.
- Each compared request-size segment requires at least 30 observations.
- User-perceived latency conclusions require at least 100 uniquely matched
  client prompt-cycle events.
- The historical one-timeout-in-seven sample is context only and cannot satisfy
  a decision gate.

Missing values and reported zeros are intentionally different. Review the
field-presence and malformed-field sections before interpreting percentiles.
If evidence is insufficient or mixed, retain the current behavior and collect
more passive data.

## Decision boundary

The report applies fixed, conservative gates for no change, schema/context
investigation, request-construction work, first-pass reliability work, and a
longer-running architecture canary. It cannot edit code or recommend changing
a constant automatically.

The current API is an API Gateway HTTP API capped at 30 seconds under the
[AWS HTTP API quotas](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-quotas.html).
A 60-second provider path therefore requires a separately reviewed architecture
canary; it is not a safe timeout-constant change. If passive evidence cannot
answer the question, plan a sealed, automated canary with fixed expected
outcomes and a test account, then obtain separate approval before any live
request.
