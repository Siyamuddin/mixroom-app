# AI V3 server-owned planner

> Implementation snapshot only. The canonical architecture is
> [ADR 0002](engineering/adr/0002-ai-v3-architecture.md), and the executable
> capability inventory is the
> [AI V3 Capability Matrix](engineering/ai_v3_capability_matrix.md).

Updated clients use the authenticated context-only contract:

```text
original request + recent conversation + deterministic CoreContextV3 facts
                    -> backend contract v2 semantic planner
                    -> validated PlanV3 envelope
                    -> Flutter preparation, transaction, readback, and undo
```

Flutter sends `request_contract: mixroom_v3_context_v1`, the PlanV3 schema
version, its sorted command capability allowlist, and the resource-reference
capability. It does not ship or send V3 system instructions, tool definitions,
model or reasoning policy, provider input, cache/storage settings, or request
overrides.

Backend contract v2 owns all V3 semantics and provider policy. This includes
the language, MIDI, mixing, and resource-reference instructions; the canonical
`submit_plan_v3` provider schema; the request-independent musical-dimension
compiler introduced for generalized compound requests; and the single
align-only `production_goal` retry. The retry is server-side, so an updated
client makes exactly one authenticated request per user prompt.

## Client boundary

Flutter remains authoritative only for deterministic application facts and
safe execution:

- project context collection and bounded recent conversation;
- PlanV3 wire types, command allowlist, and strict argument validation;
- resource binding and factual preparation;
- local analysis and mixing materialization;
- atomic execution, readback, rollback, undo, and UI handoff.

The client accepts only `v3_plan_response_server_v1`. It revalidates every
command against its own supported surface and retains only the plan plus
allowlisted trace and prompt-rate-limit metadata. It never falls back to legacy
V3, V1, or direct OpenAI after an individual V3 failure. One token refresh is
allowed for `401` or `403`.

## Routing and compatibility

`AI_V3_PRIMARY_ENABLED=false` is the build-time client kill switch. Updated
clients otherwise use `/v1/llm/v3/responses` through the configured
authenticated proxy. The server keeps both
`AI_V3_SERVER_CONTRACT_ENABLED=true` and
`AI_V3_LEGACY_CLIENT_CONTRACT_ENABLED=true` while already-released clients
still need the legacy client-authored contract. New clients never select that
legacy route.

Context size limits remain deterministic: 32 rows, 128 clips, 512 MIDI notes,
and 250 indexed library assets. Oversized projects fail without semantic
fallback.

Every current command is reversible `auto_apply`. Flutter prepares the full
plan, rechecks state, executes one transaction, reads the result back, and only
then shows a verified receipt with Undo available. Clarifications, unsupported
requests, blocked prerequisites, no-ops, and failures do not mutate the project.

## Release gate

Run the repository-owned source and artifact scanner before distribution:

```bash
dart run tool/check_ai_ip_boundary.dart --static
dart run tool/check_ai_ip_boundary.dart --artifact <release-output>
```

The reviewed marker manifest is `tool/ai_ip_boundary_manifest.json`. V3 prompt,
tool, retry, provider-policy, and removed-experiment markers are forbidden in
shipped source and release artifacts. The artifact scan also reports V1, video,
or other AI prompt/provider markers as blocking follow-up migrations.

Adaptive, compact, retrieval, capture, and music-generation planner prototypes
are historical designs only. They are not compiled into the application; any
future experiment belongs behind a server-owned contract.
