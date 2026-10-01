# MixRoom voice protocol v1

The local Python service exposes `/api/voice`. The browser obtains a bearer token from `POST /api/auth/login {password}`. A native instance obtains a different, session-scoped bearer token by claiming a one-use pairing code. Credentials never appear in URLs. Every authenticated request uses `Authorization: Bearer …`.

| Method / path | Caller | Purpose |
| --- | --- | --- |
| `POST /pairing {}` | Browser | Return `sessionId`, formatted `pairingCode`, `expiresAt`. |
| `POST /pairing/claim {pairingCode,deviceName?}` | Unpaired Mac | Return `sessionId`, `deviceToken`, `expiresAt`. |
| `GET /sessions/:id/state` | Either | Native snapshot and connection timestamps. |
| `PUT /sessions/:id/state` | Mac | Publish `{projectSessionId,projectRevision,state}`. |
| `POST /sessions/:id/presence {}` | Browser | Heartbeat. |
| `POST /sessions/:id/commands` | Browser | Submit versioned command. |
| `GET /sessions/:id/poll` | Mac | Claim one command, plus readiness/stop flags. |
| `POST /sessions/:id/results` | Mac | Publish verified terminal outcome. |
| `GET /sessions/:id/commands/:commandId` | Either | Read existing status, including lost-response recovery. |
| `POST /sessions/:id/planner` | Mac | Plan the currently claimed command from fresh context. |
| `POST /sessions/:id/mix-resolve` | Mac | Resolve the existing deterministic mixing proposal. |
| `POST /sessions/:id/capture-ready {captureId}` | Browser | Confirm speech and microphone have stopped. |
| `POST /sessions/:id/emergency-stop {captureId}` | Browser | Bypass the queue and stop the current capture. |
| `DELETE /sessions/:id` | Browser | Revoke session. |
| `POST /speech/token {sessionId}` | Browser | Issue short-lived ElevenLabs Scribe token. |
| `POST /speech/tts {sessionId,text}` | Browser | Stream ElevenLabs MP3 response. |

Command:

```json
{
  "version": 1,
  "commandId": "UUID",
  "sessionId": "UUID",
  "projectSessionId": "native-project-session",
  "expectedProjectRevision": 42,
  "kind": "utterance",
  "args": {"text": "Lower the vocal by two decibels"},
  "expiresAt": "ISO-8601 timestamp, at most five minutes ahead"
}
```

For `kind: "session_action"`, `args` is `{type,arguments}`. Supported types: `recording.start`, `recording.stop`, `comparison.before`, `comparison.after`, `comparison.keep_before`, `comparison.keep_after`, `history.undo`, `history.redo`, `notes.add`, `notes.list`, `notes.complete`.

`recording.start` accepts `duration_seconds` or `bars`, optional `row_id`, `hum`, and `instrument_id`. No duration defaults to ten seconds. Native validation enforces a sixty-second limit after converting bars from tempo/time signature. Notes accept `text`, or `note_id` for completion. Read/list/history/comparison actions require no arguments.

Planner input is `{commandId,request,sessionState}`. `request` retains the existing `mixroom_v3_context_v2` contract. Responses are exactly one of:

```ts
{ kind: 'daw_plan', response: ExistingV3Response }
{ kind: 'session_action', action: { type: string, arguments: object } }
{ kind: 'clarify' | 'respond' | 'unsupported', message: string }
```

Transport success does not mean an edit succeeded. The Mac validates, applies, verifies, and returns `{commandId,status,message,state?,details?}`. Terminal transport status is `succeeded`, `failed`, or `rejected`; `details.nativeStatus` distinguishes verified edits, clarification, replies, unsupported requests, and unknown execution. The companion speaks completion only after receiving this result.

New commands use a new UUID. Retries retain the original UUID and full payload. A changed payload under an existing ID is a conflict. A lost response triggers status lookup, never another relative edit. An authoritative `command_not_found` response allows clearing a pending request only after its original expiry, using the exposed server `Date` header. Interrupted native journal entries become unknown and are not replayed.

State is allowlisted: project label/readiness, stable track IDs and display values, selected IDs, transport, capture state, comparison, and notes. Raw audio, local paths, and secrets are excluded. Context is built on the Mac for every request; the browser track list is never the planning snapshot.

Poll approximately once per second. After fifteen seconds without browser presence, do not claim new work. The Mac completes an active bounded recording locally and preserves its clip. A/B cancellation restores the committed state. Session replacement must not move an old pending result into a new session.
