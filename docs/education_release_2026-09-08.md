# Education release: 2026-09-08 (KST)

Production deployment completed for the App API, AI usage checks, and admin.mixroom.ai.

## Scope and compatibility

- Optional access deadlines preserve existing behavior for records without a deadline.
- No app binary release, data migration, database replacement, or stack parameter change.
- Release packages start from the live Lambda packages. Only the Education/access-period files changed; the unrelated live AI response handler was preserved.
- Seven App API functions and two AI functions updated. Other functions retained their deployed packages.
- Employee login configuration and OAuth scopes preserved.

## Verification

- Both CloudFormation stacks reached UPDATE_COMPLETE.
- All nine changed Lambda package hashes match the prepared artifacts.
- Live admin HTML, scripts, stylesheet, and configuration match the release. New modules serve as JavaScript.
- CloudFront invalidation IBH0YOTRH9R82GCMJGB44EWKQF completed.
- App API authentication and new invitation-route CORS checks passed.
- Targeted Education, expiry, invitation, AI, and UI logic tests passed.
- Full App API suite: 434 passed, one existing Toss legacy-renewal test failed. The same failure reproduces on unchanged HEAD.
- No student invitations sent during deployment checks. Authenticated employee provisioning, inbox delivery, and student acceptance still require the manual test.

## Rollback artifacts

- mixroom-app-api-prod: change set `education-access-20260907T180058Z`; rollback template `s3://aws-sam-cli-managed-default-samclisourcebucket-h3jgcsjuezv5/education-release/20260907T180058Z/app-rollback.json`.
- mixroom-llm-proxy-prod: change set `education-access-20260907T180058Z`; rollback template `s3://aws-sam-cli-managed-default-samclisourcebucket-h3jgcsjuezv5/education-release/20260907T180058Z/ai-rollback.json`.

The previous admin assets are backed up locally in `/tmp/mixroom-edu-deploy/admin-site-backup/`. Production stack snapshots, artifact hashes, and verification results are in `/tmp/mixroom-edu-deploy/`.

See [the employee guide](../admin_site/EDUCATION_EMPLOYEE_GUIDE.md) for provisioning and student testing.

## Email-only teacher invitations

The admin provisioning form now sends an email-bound teacher invitation without requiring an existing Mixroom account or a user ID. `invite_teacher: true` ignores a supplied user ID; omitting an ID also selects invitation mode. Legacy existing-account grants retain their previous behavior.

Teacher membership remains pending until the invited person signs up/signs in and accepts. Acceptance retains the teacher role and consumes no student seat, even at full class capacity. Resending uses the existing pending token; invalid, accepted, student, and cross-organization tokens fail validation. Delivery failures return the saved invitation so employees can retry or copy its link.

The live public website source includes invitation capture and acceptance after signup/sign-in. No website or native app release is required. A real mailbox/signup acceptance test remains for the employee; automated tests do not send production email.

Validation: 441 of 442 App API tests passed; the same pre-existing Toss legacy renewal checkout test fails. All eight admin module tests passed. Six new teacher tests cover email-only provisioning, acceptance after signup at full student capacity, email binding, token reuse, existing teacher preservation, localized email content, invalid addresses, and resend restrictions. The admin endpoint test also verifies delivery failure preserves the saved invite.

Deployment artifacts and original production package: `/tmp/mixroom-teacher-deploy`. Only three Python modules change in the production package: collaboration repository, education invite email service, and admin billing handler. Production parameters and all other source files remain as deployed before this release.

## Provisioning 500 hotfix

Production provisioning failed at `save_workspace`: the organization-owned classroom workspace included `user_id: ""`, which DynamoDB rejected because `user_id` is a secondary index key. Earlier tests mocked workspace persistence and missed this constraint. The fix omits an empty owner ID from the persisted workspace while preserving the response shape and owned-workspace behavior.

Reproduced the exact DynamoDB ValidationException with an isolated diagnostic class, then verified corrected email-only provisioning, existing-ID provisioning, retry, and JSON response serialization against the real production table. Suppressed outgoing email and removed all diagnostic records. Added a regression test asserting ownerless workspace writes omit the user index key and owned workspace writes retain it.

The dashboard restores the optional teacher user ID. A blank ID invites by email; an existing ID activates directly. New requests retain their organization ID across failures. Existing school → Use selected school resumes partially created classes without creating another class.

Hotfix artifacts: `/tmp/mixroom-teacher-hotfix`. The backend package changes only `common/collaboration_repository.py`.

## Invitation email app link and code

Teacher and student emails now put `mixroom://education/invites/<token>` first and show the existing invitation token as a selectable code in both HTML and plain text. The recipient signs in with the invited email and can paste the code into the existing app's Education invite box. The website signup/sign-in URL remains a fallback. Invitations grant class access after authentication; they do not log the recipient into an account.

Email rendering derives the code from `invite_token` or a legacy invite URL, so resends of existing invitations include the code without changing the token. Tests cover both roles, English/Korean, escaped class names, app-link ordering, token preservation, and the visible code. Existing student delivery and teacher tests pass.

macOS source lacked the `mixroom` URL scheme registration and URL-to-Flutter forwarding. Added both, with native cold-start URL storage and forwarding of unrelated URLs to Flutter's existing delegate. Swift type-checking and plist validation passed. The native change requires a new Mac app build and is not included in the backend deployment. Existing installed apps can use the code immediately. Dart analysis reports only three existing unused-helper/import warnings in the account subscription file.

Email deployment artifacts: `/tmp/mixroom-invite-email-deploy`. Only the shared education email module changes in the production Admin Billing and Collaboration API packages. No production invitation emails were sent during automated validation.

## Shared class invitation links

Added create/get/revoke actions to the existing admin and teacher invitation endpoints. A shared link encodes the organization plus a random 128-bit UUID secret; the current active token is stored in a dedicated education_link record. Generating a link sends no email and reserves no seats. The existing student acceptance endpoint recognizes shared tokens and creates an active student membership for the signed-in account. Repeat acceptance preserves the existing membership. Teacher invitations, removed members, and expired student deadlines cannot be bypassed through shared admission.

Education membership writes now transact against an organization seat_revision and a strongly consistent roster. Class capacity updates use the same revision check. Converting an email invitation deletes the pending record in the same transaction; the deletion checks pending status. Shared admission also checks the active link token transactionally, so revocation races cannot grant new seats. Failed competing admissions retry against fresh state. Existing non-Education membership writes keep their prior path.

Real production-DynamoDB diagnostic test: eight parallel joins into a three-seat temporary class resulted in exactly three memberships. Duplicate acceptance was idempotent, pending email invitation conversion succeeded at full capacity, and revoke/regenerate worked. No email was sent, and all diagnostic records were removed. Unit suite: 454/455 passed, with the unchanged Toss legacy checkout failure. Nine admin module tests passed. Dart analysis has only the existing unused-helper/import warnings.

Deployment artifacts: /tmp/mixroom-shared-link-deploy. Every production package was overlaid independently to preserve prior differences; only collaboration_repository.py, api_collaboration.py, and api_admin_billing.py change. No schema migration, new API route, or new infrastructure resource.

User explicitly chose admin deployment only for now after Vercel reported Not authorized. Teacher web controls remain unpublished in the sibling Mixroom-website/admin/index.html. Native teacher controls also require an app release. The student paste-link flow works with the existing app.

The final 60-student stress test initially exposed excessive transaction contention with the short retry policy (20 joined, 40 received retry errors; no over-allocation). Replaced linear eight-attempt retries with jittered exponential backoff bounded by a 22-second window and 32 attempts. Repeated the real-DynamoDB test: 60 joined, zero rejected, exactly 60 occupied seats. Existing pending-email conversion at full capacity, duplicate joins, and revoke/regenerate also passed. All 63 temporary records were removed. The retry adjustment changes only collaboration_repository.py; artifacts are in /tmp/mixroom-shared-link-retry-deploy.

### Shared education code in admin

Published the existing shared invitation token as **Education invite code**, with **Generate code** and **Copy code** controls. **Copy link** remains available; revocation disables both. Students paste the raw code into the app's existing Education invite input without an app update. Updated the employee guide. All 9 admin tests pass, including copying the raw token separately from the URL and clearing both on revocation. Production assets match local files; deployment log: `/tmp/mixroom-shared-code-admin-deploy.log`. This update deploys only the admin site.

### Typable shared education codes

Deployed 10-character codes grouped as five characters, a hyphen, and five characters. Codes exclude 0, 1, I, and O; lookup accepts lowercase and an omitted hyphen. The API returns `invite_code` alongside the existing long token and links. Existing active links get stable short aliases on retrieval without rotation. Conditional alias writes handle collisions; lookup checks the canonical link and membership transactions retain its token, so revocation and seat limits apply to both formats. Historical aliases cannot reactivate after regeneration.

Validation: 12 shared invitation tests and 9 admin tests passed. The full backend run passed 458/459 tests, with only the previously documented Toss legacy renewal failure. A temporary DynamoDB class verified short-code concurrent acceptance, exact capacity, pending-invite merging, idempotence, revocation, and regeneration; all eight diagnostic records were removed. Production CloudFormation reached UPDATE_COMPLETE, all seven Lambda package hashes matched, and authentication checks passed. Public admin assets matched local files. Deployment artifacts: `/tmp/mixroom-short-code-deploy`; admin log: `/tmp/mixroom-short-code-admin-deploy.log`. No native app update required.

### Employee access to education codes

Removed the Andrew-only AI-settings permission dependency from the shared education code controller. Signed-in approved employee admins can now load, generate, copy, and revoke shared codes when collaboration is configured. The backend already enforces employee authentication and the admin email allowlist for these actions. Other dashboard permissions remain unchanged. Ten admin tests and twelve admin billing tests passed, including the non-developer frontend permission regression and generation as a non-Andrew employee. Admin-only deployment log: `/tmp/mixroom-employee-code-admin-deploy.log`.

### Employee provisioning and management controls

Removed the Andrew-only AI-settings dependency from billing catalog and billing/team management permissions. Approved signed-in employees can provision education classes, send student invitations, resend teacher invitations, and edit organizations, memberships, workspaces, cloud projects, and billing catalog records. Existing configured-service checks, request-in-progress guards, form validation, and server employee allowlist remain active. Eleven admin tests and twelve admin billing tests passed, including education provisioning as a non-Andrew employee. Admin-only deployment log: `/tmp/mixroom-employee-provisioning-admin-deploy.log`.
