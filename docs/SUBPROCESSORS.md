# Mixroom Subprocessors

Last updated: 2026-06-05

This page lists the main third-party processors and service providers that may
process personal data on behalf of (주)믹스룸 (Mixroom), depending on the
feature you use.

## Core infrastructure

- Amazon Web Services (AWS)
  - Purpose: hosting, authentication, API delivery, serverless compute, data
    storage, secret management, logging, and operational monitoring
  - Services used in the current stack may include Cognito, API Gateway,
    Lambda, DynamoDB, Secrets Manager, and CloudWatch

## Analytics and diagnostics

- PostHog
  - Purpose: product analytics and usage event measurement
- Sentry
  - Purpose: crash reporting and error diagnostics

## Identity and authentication

- Google
  - Purpose: Google sign-in and related identity verification flows
- Apple
  - Purpose: Sign in with Apple and App Store account-related flows
- Kakao
  - Purpose: Kakao sign-in flows

## Billing and app distribution

- Apple
  - Purpose: App Store distribution, in-app purchases, subscription management,
    purchase verification, and restore flows
- Google
  - Purpose: Google Play distribution, in-app purchases, subscription
    management, purchase verification, and restore flows

## AI providers

Mixroom currently uses OpenAI as the active cloud AI model provider for
production AI requests. Mixroom may support additional AI providers, such as
Google or Anthropic, in the future, and will update this list before routing
production AI requests to a new provider. Mixroom sends cloud AI request data
only when you use a cloud AI feature.

- OpenAI
  - Purpose: cloud AI model processing for prompts, limited chat history, and
    structured project context Mixroom sends when you use cloud AI features

## Optional third-party content platforms

- YouTube / Google
  - Purpose: user-initiated video upload flows and related OAuth permissions

## Notes

- Not every provider processes data for every user. Processing depends on the
  features you use and the Mixroom deployment configuration.
- This list may change as Mixroom's infrastructure evolves. Mixroom will update
  this page when material processor changes occur.

For privacy questions, contact `privacy@mixroom.ai`.
