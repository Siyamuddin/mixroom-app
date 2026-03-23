# Beta Auth QA Checklist

This is the minimum auth/login QA pass before beta launch.

## Build configuration checks

- `COGNITO_REGION`
- `COGNITO_USER_POOL_ID`
- `COGNITO_APP_CLIENT_ID`
- `COGNITO_DOMAIN_URL`
- `COGNITO_REDIRECT_URI_ANDROID`
- `COGNITO_REDIRECT_URI_IOS`
- `COGNITO_PROVIDER_GOOGLE`
- `COGNITO_PROVIDER_APPLE`
- `COGNITO_PROVIDER_KAKAO`
- `COGNITO_ENABLE_GOOGLE_SIGN_IN`
- `COGNITO_ENABLE_APPLE_SIGN_IN`
- `COGNITO_ENABLE_KAKAO_SIGN_IN`

## App behavior checks

### Email auth

- Register with a new email.
- Confirm the email verification code flow works.
- Sign in with the verified account.
- Request password reset.
- Complete password reset and sign in with the new password.
- Sign out and confirm reopening the app does not restore a signed-out session.

### Social auth

Run on physical iOS and Android devices.

- Google sign-in succeeds.
- Apple sign-in succeeds on iOS.
- Kakao sign-in succeeds where intended.
- Cancelling the hosted login sheet returns to the app without a stuck loading state.
- Misconfiguration cases show a useful error instead of a fake “cancelled” message.

### Session handling

- Relaunch the app while signed in and confirm the session restores.
- Leave the app idle long enough for token refresh to be exercised.
- Delete account and confirm local session is cleared.
- Sign out on a flaky network and confirm the app still clears local state.

### Platform gating

- Social buttons are hidden on unsupported platforms.
- Disabled providers are hidden when the related `COGNITO_ENABLE_*` flag is false.
- Dev login button is not visible in release builds.

## Regression checks

- Auth gate still routes signed-out users to login and signed-in users to the shell.
- Subscription entitlement refresh still works after sign-in.
- Chat requests still obtain a valid Cognito ID token after sign-in.
