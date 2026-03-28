# Mixroom Availability, DevOps, and Security Review

Date: 2026-03-27

## Executive Summary

Mixroom's backend shape is directionally good for an early consumer app: AWS Lambda + API Gateway + DynamoDB + SQS is a strong low-ops, autoscaling baseline, and you already have several sensible controls in place such as Secrets Manager usage, auth rate limiting, CloudWatch alarms, an SQS DLQ, Cognito deletion protection, and CloudFront + private S3 for the admin site.

The main production risk is not lack of "read replicas" or multi-region failover. The main risk is recoverability. On 2026-03-27, live production DynamoDB tables sampled from the core user/billing/auth path had Point-in-Time Recovery disabled, sampled tables had deletion protection disabled, and the production CloudFormation stacks had termination protection disabled. That means an operator mistake, bad deployment, or destructive stack action is a more realistic catastrophic-loss scenario than an AWS hardware fault.

For your current stage, I would not recommend multi-region active-active or global failover yet. I would recommend, before scale, enabling DynamoDB PITR, enabling deletion/termination protection, requiring MFA on the admin pool, attaching a basic WAF to both APIs, reserving some Lambda concurrency for core auth/user paths, and confirming that alerts actually reach a human.

## What You Already Have

- Good regional availability baseline: API Gateway, Lambda, DynamoDB, SQS, S3, CloudFront, and Cognito are managed regional services and already give you multi-AZ redundancy inside `ap-northeast-2`.
- Autoscaling-friendly data path: core tables use DynamoDB `PAY_PER_REQUEST` in [backend/app_api/template.yaml](/Users/andrewhyungulee/Mixroom/mixroom-app/backend/app_api/template.yaml#L325) and [backend/llm_proxy/template.yaml](/Users/andrewhyungulee/Mixroom/mixroom-app/backend/llm_proxy/template.yaml#L131).
- Queue durability on billing projection: the projection queue has a DLQ in [backend/app_api/template.yaml](/Users/andrewhyungulee/Mixroom/mixroom-app/backend/app_api/template.yaml#L310) and [backend/app_api/template.yaml](/Users/andrewhyungulee/Mixroom/mixroom-app/backend/app_api/template.yaml#L316).
- App auth has real rate limiting in [backend/app_api/src/common/rate_limits.py](/Users/andrewhyungulee/Mixroom/mixroom-app/backend/app_api/src/common/rate_limits.py#L31) and public auth actions enforce it in [backend/app_api/src/handlers/api_auth.py](/Users/andrewhyungulee/Mixroom/mixroom-app/backend/app_api/src/handlers/api_auth.py#L25).
- Request logs are metadata-oriented rather than full-body logs in [backend/app_api/src/common/logging_utils.py](/Users/andrewhyungulee/Mixroom/mixroom-app/backend/app_api/src/common/logging_utils.py#L8) and [backend/llm_proxy/src/common/logging_utils.py](/Users/andrewhyungulee/Mixroom/mixroom-app/backend/llm_proxy/src/common/logging_utils.py#L8).
- Passwords are salted and hashed server-side in [backend/app_api/src/common/native_auth.py](/Users/andrewhyungulee/Mixroom/mixroom-app/backend/app_api/src/common/native_auth.py#L131).
- Admin site hosting is private-by-default and fronted by CloudFront with security headers in [admin_site/infrastructure/aws_static_site.template.yaml](/Users/andrewhyungulee/Mixroom/mixroom-app/admin_site/infrastructure/aws_static_site.template.yaml#L38) and [admin_site/infrastructure/aws_static_site.template.yaml](/Users/andrewhyungulee/Mixroom/mixroom-app/admin_site/infrastructure/aws_static_site.template.yaml#L63).

## Critical Findings

### F1. Production DynamoDB recovery safeguards are not in place

Severity: Critical

Location:
- Live AWS configuration on 2026-03-27
- Table definitions in [backend/app_api/template.yaml](/Users/andrewhyungulee/Mixroom/mixroom-app/backend/app_api/template.yaml#L325)
- Table definitions in [backend/llm_proxy/template.yaml](/Users/andrewhyungulee/Mixroom/mixroom-app/backend/llm_proxy/template.yaml#L131)

Evidence:
- Live `describe-continuous-backups` for `mixroom-users-prod`, `mixroom-subscriptions-prod`, `mixroom-entitlements-current-prod`, `mixroom-auth-sessions-prod`, and `mixroom-billing-events-prod` returned `PointInTimeRecoveryStatus: DISABLED`.
- Live `describe-table` for sampled core tables returned `DeletionProtectionEnabled: false`.
- Live stack inspection for `mixroom-app-api-prod`, `mixroom-llm-proxy-prod`, `mixroom-admin-site-prod`, and `mixroom-prod-alerts-topic` returned `EnableTerminationProtection: false`.
- The SAM templates define DynamoDB tables but do not set PITR, deletion protection, or a `DeletionPolicy`.

Impact:
An accidental table delete, stack delete, or destructive update is currently a realistic catastrophic data-loss event.

Fix:
- Enable DynamoDB PITR on every production table.
- Enable DynamoDB deletion protection on every production table.
- Enable CloudFormation termination protection on all production stacks.
- Add `DeletionPolicy: Retain` to stateful resources that should survive stack mistakes.
- Run one restore drill and document the restore path.

Mitigation:
- Keep frequent exports or backup plans until PITR is fully enabled.

False positive notes:
- None. This was verified against live prod on 2026-03-27.

## High Findings

### F2. Both production APIs are internet-facing without WAF, and protected routes are rejected in Lambda rather than at the edge

Severity: High

Location:
- Optional WAF attachment in [backend/app_api/template.yaml](/Users/andrewhyungulee/Mixroom/mixroom-app/backend/app_api/template.yaml#L303)
- Optional WAF attachment in [backend/llm_proxy/template.yaml](/Users/andrewhyungulee/Mixroom/mixroom-app/backend/llm_proxy/template.yaml#L219)
- Protected app API route checks auth inside handlers, for example [backend/app_api/src/handlers/api_users.py](/Users/andrewhyungulee/Mixroom/mixroom-app/backend/app_api/src/handlers/api_users.py#L109)
- LLM proxy request processing occurs in Lambda after request parsing in [backend/llm_proxy/src/handlers/api_responses.py](/Users/andrewhyungulee/Mixroom/mixroom-app/backend/llm_proxy/src/handlers/api_responses.py#L1078)

Evidence:
- Live prod stack parameters on 2026-03-27 show `WebAclArn` is empty for both `mixroom-app-api-prod` and `mixroom-llm-proxy-prod`.
- The templates only associate WAF when `WebAclArn` is provided.
- Protected requests are denied in application code, so unauthenticated traffic can still consume Lambda/API capacity before rejection.

Impact:
Bot traffic, credential stuffing, malformed body floods, and opportunistic abuse can become an availability and cost problem before auth rejects the request.

Fix:
- Attach one regional WAF WebACL to both APIs with AWS managed common rules and a basic rate-based rule.
- For the LLM proxy especially, keep Lambda-side auth, but add edge filtering so junk traffic is dropped earlier.

Mitigation:
- Current API throttles reduce blast radius, but they also create a shared choke point.

False positive notes:
- This is not saying auth is broken. It is saying the rejection point is later than ideal for an internet-facing production API.

### F3. Admin Cognito pool does not require MFA

Severity: High

Location:
- Live AWS configuration on 2026-03-27 for user pool `ap-northeast-2_WPQPElcMA`
- Admin allowlist logic in [backend/app_api/src/common/admin_access_repository.py](/Users/andrewhyungulee/Mixroom/mixroom-app/backend/app_api/src/common/admin_access_repository.py#L27)

Evidence:
- Live `describe-user-pool` returned `MfaConfiguration: OFF` for the admin pool.
- Admin access is protected by Cognito sign-in plus allowlist checks, but not MFA.

Impact:
A single compromised admin password can become a full admin-console compromise.

Fix:
- Require TOTP MFA for the admin pool.
- Keep the allowlist; MFA complements it rather than replacing it.

Mitigation:
- Keep short token validity and token revocation enabled, which you already have.

False positive notes:
- For general consumer users, MFA is optional at your stage. For admin, it is not overkill.

## Medium Findings

### F4. Current API throttle ceilings are conservative and can become a self-inflicted outage point as traffic grows

Severity: Medium

Location:
- App API throttles in [backend/app_api/template.yaml](/Users/andrewhyungulee/Mixroom/mixroom-app/backend/app_api/template.yaml#L292)
- LLM API throttles in [backend/llm_proxy/template.yaml](/Users/andrewhyungulee/Mixroom/mixroom-app/backend/llm_proxy/template.yaml#L204)

Evidence:
- Live prod stack parameters on 2026-03-27 show:
- `mixroom-app-api-prod`: `ApiThrottleRateLimit=50`, `ApiThrottleBurstLimit=100`
- `mixroom-llm-proxy-prod`: `ApiThrottleRateLimit=100`, `ApiThrottleBurstLimit=200`

Impact:
These settings are fine for early launch, but if usage spikes, API Gateway can become the first bottleneck even when Lambda and DynamoDB could have handled more.

Fix:
- Load test before launch.
- Raise the app API throttle after measuring realistic login/profile/billing traffic.
- Reserve a small amount of Lambda concurrency for auth/profile/webhook functions and optionally cap the LLM proxy so AI traffic cannot starve the core app.

Mitigation:
- You already have throttle alarms, which is the right start.

False positive notes:
- This is not an urgent change if current user volume is small.

### F5. Postmark is configured in a way that duplicates secret exposure

Severity: Medium

Location:
- Direct secret parameter and env injection in [backend/app_api/template.yaml](/Users/andrewhyungulee/Mixroom/mixroom-app/backend/app_api/template.yaml#L74) and [backend/app_api/template.yaml](/Users/andrewhyungulee/Mixroom/mixroom-app/backend/app_api/template.yaml#L250)
- Runtime preference for env var over Secrets Manager in [backend/app_api/src/common/secrets.py](/Users/andrewhyungulee/Mixroom/mixroom-app/backend/app_api/src/common/secrets.py#L179)

Evidence:
- Live prod stack parameters on 2026-03-27 show both `PostmarkServerToken` and `PostmarkServerTokenSecretArn` are set.
- Runtime code returns `POSTMARK_SERVER_TOKEN` first and only falls back to Secrets Manager if the env var is empty.

Impact:
The same secret exists in more places than necessary: deployment parameters, Lambda environment, and Secrets Manager.

Fix:
- In production, stop passing the raw `PostmarkServerToken` parameter.
- Use only `PostmarkServerTokenSecretArn`.

Mitigation:
- Keep IAM for Lambda configuration tightly scoped until this is cleaned up.

False positive notes:
- `NoEcho` hides the value from normal stack output, but it does not make this pattern preferable.

### F6. Production billing configuration is incomplete if subscriptions are intended to be live now

Severity: Medium

Location:
- Billing secret and webhook parameters in [backend/app_api/template.yaml](/Users/andrewhyungulee/Mixroom/mixroom-app/backend/app_api/template.yaml#L117)
- Production setup checklist in [backend/app_api/SETUP_CHECKLIST.md](/Users/andrewhyungulee/Mixroom/mixroom-app/backend/app_api/SETUP_CHECKLIST.md#L9)

Evidence:
- Live prod stack parameters on 2026-03-27 showed these empty:
- `AppleRootCaSecretArn`
- `AppleSharedSecretSecretArn`
- `GooglePlayPackageName`
- `GoogleServiceAccountSecretArn`
- `GooglePubSubAudience`
- `GooglePubSubServiceAccountEmail`

Impact:
If paid subscriptions are supposed to be active in prod, restore/renewal/refund handling is not production-ready.

Fix:
- If subscriptions are not live yet, no action needed now.
- If subscriptions are part of launch, complete the store verification and webhook setup before turning them on.

Mitigation:
- Keep `EnforceSubscriptions=false` until store integrations are fully wired.

False positive notes:
- This is conditional on whether billing is meant to be live in production today.

## Low Findings

### F7. Mobile token storage has an insecure fallback path

Severity: Low

Location:
- [lib/core/security/sensitive_storage.dart](/Users/andrewhyungulee/Mixroom/mixroom-app/lib/core/security/sensitive_storage.dart#L16)

Evidence:
- If `flutter_secure_storage` is unavailable or errors, reads and writes fall back to `SharedPreferences`.

Impact:
On failure paths, auth/session material can be stored less securely than intended.

Fix:
- For iOS and Android release builds, consider failing closed instead of falling back to `SharedPreferences`.
- If you keep the fallback for desktop/dev convenience, gate it by platform or build mode.

Mitigation:
- Current behavior avoids login breakage, so this is a low-priority hardening item.

False positive notes:
- On healthy mobile devices, secure storage is still the normal path.

## Availability Guidance: What You Do and Do Not Need

### You already have enough redundancy for the current stage inside one AWS region

- Lambda, API Gateway, DynamoDB, Cognito, SQS, S3, and CloudFront already give you regional managed redundancy.
- DynamoDB does not use "read replicas" in the RDS sense, so you do not need to chase read replicas for this architecture.

### You do not need yet

- Multi-region active-active
- Route 53 failover between regions
- DynamoDB Global Tables
- RDS-style read replicas
- Provisioned Concurrency everywhere
- Complex blue/green traffic shifting for every function

### You do need before meaningful consumer scale

- DynamoDB PITR
- Table deletion protection
- Stack termination protection
- Admin MFA
- Basic WAF on both APIs
- Verified alert delivery
- One restore drill
- One end-to-end synthetic health check
- Modest Lambda concurrency isolation for core app vs LLM traffic

## Residual Uncertainty

- I verified live CloudFormation stacks, live Cognito pools/clients, and live DynamoDB backup state on 2026-03-27.
- I could not verify SNS subscriptions or CloudWatch alarm state from this environment because those AWS endpoints were blocked here during inspection.
- I saw the alert topic stack deployed, but I did not see a separate CloudFormation stack for the optional Slack Chatbot integration, so alert delivery should be explicitly checked.
