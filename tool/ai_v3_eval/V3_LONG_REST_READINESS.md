# PRO-4 release and rollout checklist

This is a review checklist, not authorization to commit, PR, push, merge,
package/upload to AWS, create/execute a change set, deploy, or activate clients.
Each external step requires explicit approval. Do not use the dirty
`pro-4-ai-contract-mismatch` checkout or stage the whole `pro-4-next` worktree.

## What is already deployed

**September 8 local update:** the owner confirmed that no distributed build
depends on the unreleased 55s long path. The local replacement now uses 105s
provider, 115s Lambda, 120s REST integration, and 130s opt-in client. No deadline
negotiation was added. The original HTTP path and public opt-in defaults remain
unchanged. AWS quota approval for 120,000 ms was separately verified, but no
endpoint configuration or code was deployed. The September 6 snapshot below is
historical deployed state, not the current local candidate.

The new long-path maximum envelope at rate 1/s and burst 20 is 135 simultaneous
requests; allowing 20 slots for other work requires at least 155 available slots.
This is a conservative planning check, not a reservation or a live capacity claim.
Preserve applied throttles and review actual headroom before activation.

Local replacement verification: 340 AI-backend tests, 66 selected client
configuration/planner/action-flow tests, and the real 75-second fake-provider
loopback test passed. The loopback test now uses the normal 130-second route
configuration and unmodified handler deadline logic, not candidate overrides.
Shared-deadline tests verify 105s exhaustion, repair using only the remaining
budget, Lambda response margins, and single settlement. SAM lint and
`git diff --check` passed. Frozen original HTTP resource hashes still match.
The running manual app/bridge must be rebuilt/restarted together to use these
source changes; they are not hot-applied to an existing session.

Read-only inspection on September 6, 2026 KST confirmed the long REST API and
Lambda already exist in `mixroom-llm-proxy-prod`, `ap-northeast-2`. The stack
was last updated September 4. This is not a first dormant deployment.

- Original HTTP V3: 27-second provider default, 30-second Lambda/integration,
  and unchanged 35-second client default.
- Long REST V3: 55-second provider, 60-second Lambda, 65-second integration,
  and 70-second opted-in client. Only contract 6 is accepted on that route.
- Applied long-route throttle: 1 request/second, burst 2. The local template's
  burst default of 5 is NOT the approved applied setting for an update.
- Applied Lambda account concurrency is 1,000 and integration quota is 65,000 ms.
  These are ceilings, not capacity reservations or timeout-free guarantees.
- Historical final logs contain three successful long requests taking
  35.5–46.8 seconds, with one provider attempt each. Do not repeat a paid
  heavy-prompt matrix solely to prove the old 30-second boundary is crossed.
- The earlier unchanged-phone success was user-reported. Historical backend
  completion is not independent proof of receipt by a particular app build.

Recheck this dated snapshot before an approved rollout if production has
changed. No public-client routing inventory was established by that inspection.

## Local review package

The reviewed candidate is based on main
`93b10e21c3f726c6062c4ef2837eb1d007b3e2a7`, with 18 allowlisted files.
Keep the analyzer, local bridges, paid/native evaluation runners, their
dependent tests, and deployment-local `samconfig.toml` changes out of scope.

Passing evidence: 260 backend tests and 306 AI-client tests; frozen V1,
HTTP/REST parity, deadline/failure/settlement tests, deterministic four-profile
hash/size/count checks, SAM lint, and whitespace checks. The complete Flutter
suite has seven failures also reproduced on unmodified main and six existing
host-export skips. Record their disposition separately; do not claim the whole
app is green or suppress them to release PRO-4.

The 40-second fake-provider client check passed earlier using excluded local
tooling. It is not a dependency of the release package. Native stall diagnosis
and broad musical/language reliability are not certified by these tests.

## Gate A — code review and merge, only after approval

Review only the allowlisted diff against its pinned base. If main advances,
reconcile and rerun relevant checks in an isolated worktree; do not overwrite
new main changes. Verify both long-route build defaults remain false/empty.

A review/merge approval does not authorize backend deployment or public client
activation. Existing clients must keep the original API, route, contract support,
authentication, entitlements, and usage behavior.

## Gate B — shared-backend update, separately approved

The deployed package already contains the earlier long timeout path. The current
source delta also includes the local 105/115/120/130 deadline replacement and
capability-gated 512-note support, alongside language and validation changes.
Both response Lambdas share `src/`; an ordinary stack package also
updates the mix-resolve Lambda's code artifact. Do not describe this as affecting
only an unused endpoint. Old clients already on contract 6 receive the new
server instructions too; frozen V1 files remain identical.

Before any approved packaging/upload or change-set creation:

1. Record the live stack template, applied configuration, resource identities,
   code hashes, and previous S3 artifact reference in restricted release records.
   Do not put credentials, secret values, or signed download URLs in the repo.
2. Preserve ALL applied stack parameters, including long throttle rate 1/burst 2,
   HTTP throttles, models, reasoning, cache configuration, auth, quota, billing,
   and telemetry. The candidate samconfig's explicit
   `AiChatExtendedPromptCacheRetentionModels` differs from production; do not
   use it to overwrite production incidentally.
3. For an approved CloudFormation UPDATE change set, explicitly use
   `UsePreviousValue: true` for existing parameters. Do not also provide
   `ParameterValue` for them. Reconcile every added/removed parameter explicitly;
   never silently fall back to template defaults. This is a parameter-preservation
   policy, not permission to run the command.
4. Inspect the actual packaged change set and effective parameter values.
   Stop for resource creation/deletion/replacement, existing HTTP route changes,
   altered auth/IAM/data resources, parameter drift, or unexplained configuration
   changes. A code artifact update can legitimately affect all three Lambdas;
   template constraint/packaging changes must be understood, not blanket-approved.
5. Obtain separate execution approval. Code review approval alone is insufficient.

CloudFormation documents explicit previous-value preservation in its
[change-set API](https://docs.aws.amazon.com/cli/latest/reference/cloudformation/create-change-set.html).
The local template has no new/removed original resource IDs versus the inspected
stack, but a static comparison is not a substitute for the actual change set.

After an approved update, use a bounded test-account smoke check for the original
route and long route. Confirm correct responses, authenticated access, one
reservation followed by one finalization/release, and unchanged old-client
routing. Use offline tests for forced failure/repair cases; do not repeatedly
spend on heavy requests unless a new runtime change warrants it. Observe both
functions explicitly: the inspected alarms cover the original HTTP path, not
a complete long-route monitoring policy.

## Gate C — client activation, separately approved

Keep public builds at `AI_V3_LONG_PATH_ENABLED=false` and an empty
`AI_V3_LONG_API_BASE_URL` until activation is approved. Backend deployment
does not activate clients.

A non-public approved build needs BOTH the enabled flag and the distinct HTTPS
long API URL. Invalid settings fall back to the original route. Submitted
requests must not be retried through another route. Internal success is not
permission for public rollout. Review current capacity/traffic before enabling
released clients; preserve the applied throttles unless explicitly changed.
Existing installations retain their original route/deadline until intentionally
updated; PRO-4 does not remove the old route's limit for them.

## Stop and rollback

Stop new canary submissions for auth bypass, duplicate settlement, partial
project mutation, new old-client failures, or unexplained errors/throttling.

- Internal client: stop the build or rebuild with the long flag disabled.
  This does not instantly reconfigure an already distributed public binary.
- Shared backend: restore the recorded previous artifact AND configuration via
  a separately approved update. The September 6 inspection verified that the
  retained S3 artifact matches all three running Lambda ZIP hashes.
- These Lambdas have only `$LATEST`, with no version aliases. Do not promise an
  instant alias rollback or claim that disabling the client flag reverts shared
  server code.
- Preserve both APIs, old-client support, and retained data. Removing the already
  deployed long resources is not the default rollback. Rehearse the rollback
  procedure on paper before execution; no live rollback has been tested here.
