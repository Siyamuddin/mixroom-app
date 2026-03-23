# Release TODO

Last updated: 2026-03-09

This is the general production-release checklist for Mixroom.

Use this for the obvious-but-easy-to-forget work that is not tied to one
feature, one cloud provider, or one launch surface.

For deeper feature-specific details, use the other docs in `docs/`.

## 1. Core Legal

- Publish a real Privacy Policy.
- Publish a real Terms of Service.
- Keep a dated change log for policy revisions.
- Track accepted policy versions and timestamps per account.
- Keep a clear support / legal contact email live.
- Keep copyright / trademark ownership clear for the Mixroom name, branding,
  logo, and shipped assets.
- Keep records for third-party licenses, notices, and commercial-use rights.

## 2. Store Readiness

- App Store and Play listing text must match the real product.
- Privacy disclosures in App Store and Play Console must match actual SDKs and
  data flows.
- If accounts can be created, account deletion must exist where store policy
  requires it.
- If subscriptions or trials exist, pricing and renewal terms must be clearly
  disclosed near purchase.
- Review/demo credentials and review notes must be ready before submission.
- Support URL, privacy URL, and any required website links must be live.
- Export compliance / encryption questions must be answered correctly.

## 3. Privacy and Data Handling

- Collect only data you can justify keeping.
- Define retention rules for account data, logs, analytics, backups, and
  deleted users.
- Document what data is deleted immediately, what is delayed, and what is kept
  for legal, fraud, billing, or security reasons.
- Keep newsletter / marketing consent separate from account / legal consent.
- Do not bundle marketing opt-in with signup acceptance.
- Have a clear policy for minors / under-13 handling before public release.

## 4. Security

- MFA on every admin account.
- Least-privilege access for staff, services, and automation.
- Secrets must not live in the app binary, source control, logs, or screenshots.
- Rotation owners and rotation dates must be defined for critical secrets.
- Auth tokens and sensitive local data must stay in OS-protected storage.
- Rate limiting, abuse throttling, and brute-force protection must exist for
  auth and sensitive endpoints.
- Error reporting must avoid leaking secrets, tokens, passwords, or PII.
- Have a process for vulnerability reporting and urgent patch release.

## 5. Trust and Safety

- Users need a way to report abuse, impersonation, spam, and harmful content.
- Staff need a minimal moderation and account-action workflow.
- Suspensions, bans, appeals, and takedown actions should be auditable.
- Public-facing products need blocking / reporting / abuse contact paths.
- If user-generated content is public, define moderation standards before launch.

## 6. Operations

- Production error monitoring must be live.
- Basic product analytics must be live and trusted.
- Alerts must exist for outages, auth failures, payment failures, and abnormal
  error spikes.
- Backups must exist and at least one restore drill should be completed.
- Incident owner, rollback owner, and release owner must be named.
- Staging and production should be operationally separated.
- Time-sensitive systems must use UTC consistently in storage and logs.

## 7. Support and Communication

- User-facing support contact must be monitored.
- Password reset, account recovery, and deletion support paths must be tested.
- Known limitations should be documented internally before launch.
- Prepare canned responses for common release issues:
  - login problems
  - purchase / restore issues
  - deletion requests
  - abuse reports
  - data/privacy questions

## 8. Business Health

- Legal entity, banking, and tax setup must be complete before monetization.
- Ownership of domains, app-store accounts, cloud accounts, and analytics
  accounts should be documented.
- At least two trusted people should have access to critical production systems.
- Vendor list should be known: auth, analytics, crash reporting, payments,
  email, storage, AI, support.
- Know which services are business-critical and what happens if each one fails.

## 9. Product Health

- Crash-free sign-in, onboarding, and primary workflow must be tested on real
  devices.
- Empty, error, offline, expired-session, and retry states must exist.
- Logging and analytics names should be stable before scale.
- Major destructive actions should have confirmation and audit trails.
- User-visible copy should be reviewed for clarity, not only correctness.

## 10. Before Public Release

- Freeze the release owner list.
- Freeze launch blockers and non-blockers.
- Do one final pass on:
  - privacy disclosures
  - support links
  - deletion flow
  - auth flow
  - subscription disclosure
  - crash reporting
  - analytics
  - legal document links
- Keep a day-1 rollback plan ready.
- Keep a day-1 monitoring plan ready.
