# Beta SSO Setup Checklist

Last updated: 2026-03-10

This is the shortest path to getting Mixroom social sign-in working for beta.

Use this in order:

1. Google client setup
2. Apple capability check
3. Kakao app key wiring
4. AWS app API social-auth deploy
5. Rebuild the app and test on a real device

## 1. App IDs Used By This Repo

- iOS bundle ID: `com.mixroom.mixroomapp`
- Android package name: `com.mixroom.mixroomapp`

## 2. Google Values For This App

- Web client ID:
  `105509343723-lufnthv351v328td07s89j53mf242pl5.apps.googleusercontent.com`
- iOS client ID:
  `105509343723-eatcl74aibc5pdqrnuvrc52n3f4m3mt3.apps.googleusercontent.com`
- iOS URL scheme:
  `com.googleusercontent.apps.105509343723-eatcl74aibc5pdqrnuvrc52n3f4m3mt3`
- Android client ID:
  `105509343723-3aqmviam9ne4nrqid9fq03m7o06tccu7.apps.googleusercontent.com`

For the Google `Web application` OAuth client used as the server client ID:

- leave `Authorized JavaScript origins` blank
- leave `Authorized redirect URIs` blank

## 3. Kakao Values For This App

- Native app key:
  `a70f53b706f3290cd916615b82b3feea`
- REST API key:
  Required for macOS desktop Kakao login. Set it with `KAKAO_REST_API_KEY`.

Already wired locally in this repo:

- [Info.plist](../ios/Runner/Info.plist)
- [AppSecrets.xcconfig](../ios/Flutter/AppSecrets.xcconfig)
- [local.properties](../android/local.properties)

## 4. Apple Setup

Before Apple sign-in can work:

- enable `Sign In with Apple` for the App ID `com.mixroom.mixroomapp`
- make sure the active provisioning profile includes that capability

## 5. AWS App API Social Auth

The app buttons will not complete sign-in until the backend endpoint is live:

- `POST /v1/auth/social/sign-in`

Backend code:

- [api_auth.py](../backend/app_api/src/handlers/api_auth.py)
- [social_auth.py](../backend/app_api/src/common/social_auth.py)

### Required deploy parameters

Deploy or redeploy [template.yaml](../backend/app_api/template.yaml) with:

- `CognitoUserPoolId`
- `CognitoAppClientId`
- `SocialAuthSecretParameterName`
- `GoogleOauthClientIds`
- `AppleBundleId`

Use these values:

- `GoogleOauthClientIds`:
  `105509343723-lufnthv351v328td07s89j53mf242pl5.apps.googleusercontent.com,105509343723-eatcl74aibc5pdqrnuvrc52n3f4m3mt3.apps.googleusercontent.com,105509343723-3aqmviam9ne4nrqid9fq03m7o06tccu7.apps.googleusercontent.com`
- `AppleBundleId`:
  `com.mixroom.mixroomapp`

### Required AWS secret

Create an SSM Parameter Store `SecureString` for `SocialAuthSecretParameterName`.

Accepted format:

```json
{
  "secret": "LONG_RANDOM_STRING"
}
```

Do not put this secret in Flutter or source control.

### CloudShell deploy shape

From [backend/app_api](../backend/app_api):

```bash
sam build
sam deploy --guided
```

Important social-auth parameters during deploy:

- `CognitoUserPoolId`: your real Cognito user pool id
- `CognitoAppClientId`: your real Cognito app client id
- `SocialAuthSecretParameterName`: name of the SSM `SecureString` parameter above
- `GoogleOauthClientIds`: `105509343723-lufnthv351v328td07s89j53mf242pl5.apps.googleusercontent.com,105509343723-eatcl74aibc5pdqrnuvrc52n3f4m3mt3.apps.googleusercontent.com,105509343723-3aqmviam9ne4nrqid9fq03m7o06tccu7.apps.googleusercontent.com`
- `AppleBundleId`: `com.mixroom.mixroomapp`

After deploy, copy the output API base URL.

## 6. Flutter Run Command For Testing

Use a real backend base URL after the AWS deploy finishes:

```bash
flutter run \
  --dart-define=APP_API_BASE_URL=https://YOUR_API_ID.execute-api.YOUR_REGION.amazonaws.com/STAGE \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=105509343723-lufnthv351v328td07s89j53mf242pl5.apps.googleusercontent.com \
  --dart-define=KAKAO_NATIVE_APP_KEY=a70f53b706f3290cd916615b82b3feea \
  --dart-define=KAKAO_REST_API_KEY=YOUR_KAKAO_REST_API_KEY
```

## 7. Test Order

1. Test `Google`
2. Test `Apple`
3. Test `Kakao`

If a button still fails:

- confirm the app was rebuilt after config changes
- confirm `APP_API_BASE_URL` is not empty
- confirm the backend was redeployed with social-auth parameters
- confirm Apple capability is enabled
- confirm Google OAuth clients match the real app IDs

## 8. What To Send Back If It Still Fails

Send these exact items:

- the `APP_API_BASE_URL` you are running with
- whether AWS deploy included `SocialAuthSecretParameterName`
- whether AWS deploy included `GoogleOauthClientIds`
- whether Apple `Sign In with Apple` is enabled for `com.mixroom.mixroomapp`
- which provider button fails: `Google`, `Apple`, or `Kakao`
- what inline error message the app now shows
