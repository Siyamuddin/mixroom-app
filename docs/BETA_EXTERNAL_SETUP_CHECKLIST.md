# Beta External Setup Checklist

This is the outside-the-IDE work required to make the current beta code path function in production.

## OpenAI Dashboard

- Create a new OpenAI API key for the beta environment.
- Confirm the OpenAI project has access to the model you want to use.
  - The production model is owned by the proxy deployment config via `OpenAiModel`.
- Put the new key into SSM Parameter Store as a `SecureString`.
- After the AWS proxy is using the new key successfully, revoke the old exposed key.
- No special OpenAI-side "rotation setting" is required beyond create -> update AWS secret -> verify -> revoke old key.

## AWS Architecture To Use

Use:

- API Gateway HTTP API
- Lambda
- Cognito User Pool
- SSM Parameter Store
- CloudWatch

Do not use EC2 for the beta LLM proxy path unless you have another unrelated reason.

## AWS SSM Parameter Store

- Create a `SecureString` parameter that stores the OpenAI API key.
- Accepted by the current Lambda:
  - plain text secret containing `sk-...`
  - or JSON containing `OPENAI_API_KEY`

## AWS Cognito

- Verify the correct User Pool is being used for beta.
- Verify the app client ID matches your app build config.
- Confirm `USER_PASSWORD_AUTH` is enabled on the app client.
- Configure the hosted UI domain.
- Add callback URLs:
  - `com.mixroom.mixroomapp://oauthredirect` for Android
  - `com.mixroom.mixroom://oauthredirect` for iOS
- Add matching logout URLs.
- Confirm allowed OAuth scopes include:
  - `openid`
  - `email`
  - `profile`
  - `aws.cognito.signin.user.admin`
- Enable and attach the providers you want for beta:
  - Google
  - Apple
  - Kakao

## Google / Apple / Kakao Provider Consoles

- Add the Cognito hosted UI callback URL to each provider console.
- Verify each provider is enabled against the same Cognito app client used by the app.
- Re-check any app bundle ID / package name / team ID values for Apple and Kakao.

## AWS LLM Proxy Deployment

- Deploy [template.yaml](../backend/llm_proxy/template.yaml).
- Pass the required deploy parameters:
  - Cognito user pool ID
  - Cognito app client ID
  - OpenAI secret ARN
- Save the deployed API base URL.
- Enable CloudWatch logs for the Lambda and API.
- Review the template defaults for API Gateway throttling / rate limiting.
  - `ApiThrottleBurstLimit`
  - `ApiThrottleRateLimit`
- If you want edge abuse filtering, attach a regional WAF WebACL by passing
  `WebAclArn` during deploy.

## App Build Configuration

- Build/run the app with:
  - `LLM_PROXY_API_BASE_URL=https://...`
- Supply the Cognito config values expected by the app.
- Release builds are proxy-only. Direct provider access is restricted to local
  debug builds and cannot be enabled with a release build flag.

## Auth / Chat QA On Real Devices

- Test email sign up
- Test verification
- Test password reset
- Test sign in restore after app relaunch
- Test sign out
- Test Google sign in
- Test Apple sign in
- Test Kakao sign in
- Test authenticated chat through the AWS proxy
- Test expired-session behavior for chat
- Test language switching from login/account and verify it propagates across auth screens

See:

- [BETA_AUTH_QA_CHECKLIST.md](BETA_AUTH_QA_CHECKLIST.md)
- [BETA_AWS_OPENAI_SETUP_CHECKLIST.md](BETA_AWS_OPENAI_SETUP_CHECKLIST.md)

## Learned Mixing Model External Steps

These are still required later if you want the learned model enabled for beta:

- Collect producer sessions / training data
- Train and export the ONNX models
- Place the exported model assets into the app assets location
- Enable the assets in `pubspec.yaml`
- Run validation on representative projects
- Enable the learned path with the appropriate build flag

## Release Safety Checks

- Make sure the previously exposed OpenAI key is revoked.
- Make sure the app no longer ships a release build that depends on a client-side OpenAI key.
- Verify CloudWatch logging is present but does not log secrets or full sensitive payloads.
- Verify abuse controls are active:
  - JWT auth
  - request size limits
  - rate limiting
