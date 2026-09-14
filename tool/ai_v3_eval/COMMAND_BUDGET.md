# Local 32-command support

Updated clients advertise `project.plan_command_policy: "commands_32_v1"` and
accept at most 32 commands. Contract 6 resolves that marker to a server-owned
limit of 32; missing, unknown or malformed markers retain 16. The existing
`notes_512_v1` marker alone still selects only the note/output budgets, not 32
commands. No arbitrary client-supplied numerical command limit is accepted.

Only the runtime tool's top-level commands `maxItems` changes. Both direct-ID
and resource-reference variants use the same policy. Semantic validation and
pitch-repair analysis enforce it too. The effective policy is included in the
capability fingerprint only when enabled, preserving old-client fingerprints.
Frozen tool assets and legacy contracts are unchanged.

No instructions, note budgets, plan-byte budgets, output-token budgets, model,
repair allowances, input limits, entitlements or deadlines were changed. A larger
command ceiling does not guarantee faster generation or that every 32-command
plan fits the unchanged byte/token limits. One command can expand into several
editor actions; command count is not a fixed execution-cost measure.

Verification (offline, no live provider requests):

- Shared 16/17/32/33 boundaries; 33 rejected before application.
- Realistic 18-command six-row and 24-command eight-row rebuilds pass backend
  validation and client preparation. Old clients remain limited to 16.
- Existing full-plan and targeted pitch repairs preserve valid 32-command
  results under the same two-attempt/shared-deadline rule and settlement logic.
- Isolated native execution/readback of 32 commands passes undo, redo and
  injected-failure rollback in private synthetic storage.
- Complete backend suite: 363 passed, including frozen legacy checks.
- Client/context/editor/persistence regression suite: 239 passed.
- Existing no-command-marker request hashes match all five historical scenarios.
- Both profiler runs agree. Capability metadata adds 39 canonical context bytes
  and 43 provider-body bytes. Only expected component sizes/request hashes change;
  instruction sizes, catalog/command variant counts and other budgets do not.
- `git diff --check` passes; no Python bytecode artifacts generated.

Evidence is under `/tmp/pro4-command32-*`. The manual app and bridge were not
reloaded; local acceptance of this new policy requires a separate relaunch.
No commit, push, PR update, deployment, production mutation or live model call.
