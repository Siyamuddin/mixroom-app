# Beta AWS / OpenAI Setup Checklist

This is the beta backend stack for Mixroom chat and auth.

Use:

- Amazon Cognito User Pool for user auth
- API Gateway HTTP API for the chat endpoint
- AWS Lambda for server-side prompt/tool/model ownership
- AWS Secrets Manager for the OpenAI API key
- CloudWatch Logs for operational logs

Do not use EC2 for this beta path unless you later need a persistent platform backend.

## 1. OpenAI dashboard

- Create a new OpenAI API key for beta server use.
- Confirm the OpenAI project has access to the model you want to use.
  - The production model is owned by the proxy deployment config via `OpenAiModel`.
- Do not put this key in the app.
- After AWS is confirmed working, revoke any previously exposed key.

No special OpenAI-side rotation setting is required.
Rotation is:

1. Create new key.
2. Update AWS secret.
3. Verify traffic uses the new key.
4. Revoke old key.

## 2. AWS Secrets Manager

- Create a secret for the OpenAI key.
- Secret name can be anything stable, for example `mixroom/beta/openai`.
- Supported secret formats:

Plain string:

```text
sk-...
```

JSON:

```json
{
  "OPENAI_API_KEY": "sk-..."
}
```

## 3. Cognito User Pool

- Create or reuse the beta user pool.
- Create an app client for the mobile app.
- Enable `USER_PASSWORD_AUTH`.
- Configure the hosted UI domain.
- Add callback URLs:
  - `com.mixroom.mixroom://oauthredirect` for iOS
  - `com.mixroom.mixroomapp://oauthredirect` for Android
- Add the same values as logout URLs.
- Add allowed scopes:
  - `openid`
  - `email`
  - `profile`
  - `aws.cognito.signin.user.admin`
- Enable the social providers you want for beta:
  - Google
  - Apple
  - Kakao
- Attach those providers to the same app client.

## 4. Provider consoles

For each enabled social provider:

- Register the exact Cognito hosted UI callback URL in that provider console.
- Confirm bundle/package IDs match the mobile apps.
- Confirm the Cognito client ID / secret configured in AWS matches the provider console.

This is required for:

- Google Cloud Console
- Apple Developer / App Store Connect
- Kakao Developers

## 5. Deploy the LLM proxy

From this repo:

```bash
cd backend/llm_proxy
sam build
sam deploy --guided
```

Provide:

- `CognitoUserPoolId`
- `CognitoAppClientId`
- `OpenAiApiKeySecretArn`
- `OpenAiModel` to choose the production model used by the proxy

After deploy, note the `ApiBaseUrl` output. It should include the API stage path.

## 6. App build configuration

Run the app with the deployed proxy:

```bash
flutter run \
  --dart-define=LLM_PROXY_API_BASE_URL=https://YOUR_API_ID.execute-api.YOUR_REGION.amazonaws.com/YOUR_STAGE
```

Set the Cognito values your app already expects:

- hosted UI domain / base URL
- user pool ID
- app client ID
- redirect schemes
- provider enable flags

Relevant client config files:

- [cognito_config.dart](../lib/config/cognito_config.dart)
- [llm_config.dart](../lib/config/llm_config.dart)

For release, do not set `OPENAI_API_KEY` in the app.

## 7. Smoke test on real devices

Run:

- email sign up
- email verification
- password reset
- Google sign in
- Apple sign in
- Kakao sign in
- app restart and session restore
- sign out
- authenticated chat request through the AWS proxy

Also run the auth checklist:

- [BETA_AUTH_QA_CHECKLIST.md](BETA_AUTH_QA_CHECKLIST.md)

## 8. Log hygiene

- Keep CloudWatch logs metadata-only.
- Do not log full prompts, project snapshots, or API keys.
- Log user ID, request size, status code, latency, and model name only.

## 9. Beta launch gate for chat/security

Before beta:

- Proxy deployed and used by production builds
- OpenAI key only in Secrets Manager
- Old exposed key revoked
- Cognito sign-in / sign-out validated on iOS and Android
- Chat request succeeds with authenticated bearer token
- Rate limits configured in API Gateway
