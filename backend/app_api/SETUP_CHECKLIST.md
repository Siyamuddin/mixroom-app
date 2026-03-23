# Mixroom App API Setup Checklist

This is the required work outside the IDE for the main Mixroom app backend to function correctly.

## 1. AWS deployment inputs

Plain English:

- AWS is required for this in-house app backend.
- `sam deploy` creates the API, Lambdas, queues, and DynamoDB tables for you.
- DynamoDB is just the AWS database used by this backend. You do not need to model it manually for day 1.

Deploy `backend/app_api/template.yaml` with real values for:

- `CognitoUserPoolId`
- `CognitoAppClientId`
- `AppleBundleId`
- `AppleAppId`
- `AppleRootCaSecretArn`
- `AppleSharedSecretSecretArn`
- `GooglePlayPackageName`
- `GoogleServiceAccountSecretArn`
- `GooglePubSubAudience`
- `GooglePubSubServiceAccountEmail`

You can leave Paddle/Toss secret params empty if you are not using web checkout yet.

After deploy, the same backend also owns:

- the app-level user bootstrap endpoint `GET /v1/users/me`
- the app-level profile update endpoint `PATCH /v1/users/me`
- the `mixroom-users-*` DynamoDB table for minimal platform user records
- the `mixroom-user-username-claims-*` DynamoDB table for unique username ownership


## 2. Seed the catalog mapping table

Populate `mixroom-catalog-mappings-*` with one record per product ID.

You can print or apply the seed rows with:

```bash
cd backend/app_api
python3 scripts/seed_catalog_mappings.py
python3 scripts/seed_catalog_mappings.py --apply --stage staging
```

Recommended shape:

```json
{
  "provider_product_key": "apple:mixroom_pro_monthly",
  "provider": "apple",
  "product_id": "mixroom_pro_monthly",
  "tier": "pro"
}
```

```json
{
  "provider_product_key": "google:mixroom_pro_monthly",
  "provider": "google",
  "product_id": "mixroom_pro_monthly",
  "tier": "pro"
}
```

If you add Studio later, add matching `studio` rows for both stores.

## 3. App Store Connect

You need all of the following:

1. Create the subscription products with the same product IDs used by the app.
2. Enable App Store Server Notifications V2.
3. Set the notification URL to:
   `https://YOUR_API_ID.execute-api.YOUR_REGION.amazonaws.com/STAGE/v1/webhooks/apple`
4. Create an app-specific shared secret for legacy receipt verification fallback.
5. Create a Secrets Manager secret referenced by `AppleSharedSecretSecretArn`.
   Accepted formats:

```json
{
  "shared_secret": "..."
}
```

or a plain string secret.

6. Create a Secrets Manager secret referenced by `AppleRootCaSecretArn` containing the Apple root certificates used by App Store signed data verification.
   Accepted formats:

```json
{
  "certificates": [
    "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----\n",
    "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----\n"
  ]
}
```

or:

```json
{
  "pem_bundle": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----\n..."
}
```

7. Make sure the numeric App Store app ID matches `AppleAppId`.

Official references:

- App Store Server Notifications V2
- App Store Server signed data verification
- App Store receipts / verifyReceipt fallback

## 4. Google Play Console

You need all of the following:

1. Create the subscription products/base plans in Play Console.
2. Link your Play Console app to a Google Cloud project with the Android Publisher API enabled.
3. Create a service account with Android Publisher access to the app.
4. Store the full service account JSON in Secrets Manager and use that ARN for `GoogleServiceAccountSecretArn`.
5. Create a Pub/Sub topic for Real-time Developer Notifications.
6. Connect RTDN in Play Console to that Pub/Sub topic.
7. Create a push subscription that sends to:
   `https://YOUR_API_ID.execute-api.YOUR_REGION.amazonaws.com/STAGE/v1/webhooks/google`
8. Configure push authentication with OIDC.
9. Set `GooglePubSubAudience` to the exact audience configured for that push subscription.
10. Set `GooglePubSubServiceAccountEmail` to the service account email used by the Pub/Sub push subscription.

Official references:

- Google Play Developer API `purchases.subscriptionsv2.get`
- Google Play Real-time Developer Notifications
- Pub/Sub authenticated push subscriptions

## 5. Cognito

The app API now verifies Cognito JWTs in-process unless API Gateway authorizers are added in front.

Required:

1. `CognitoUserPoolId`
2. `CognitoAppClientId`
3. The app must continue sending the Cognito ID token as `Authorization: Bearer ...`

## 6. Flutter app build config

Run the app with:

```bash
flutter run \
  --dart-define=APP_API_BASE_URL=https://YOUR_API_ID.execute-api.YOUR_REGION.amazonaws.com/STAGE \
  --dart-define=SUBSCRIPTION_ENFORCE=true \
  --dart-define=SUBSCRIPTION_SHADOW_MODE=false \
  --dart-define=IAP_ENABLE_PURCHASES=true
```

Recommended rollout:

1. Deploy backend and webhooks first.
2. Seed catalog mappings.
3. Test with store sandbox/test accounts while `SUBSCRIPTION_SHADOW_MODE=true`.
4. Confirm entitlement transitions for:
   - new purchase
   - restore
   - renewal
   - cancellation with remaining access
   - expiration
   - refund/revoke
5. Only then flip:
   - `SUBSCRIPTION_ENFORCE=true`
   - `SUBSCRIPTION_SHADOW_MODE=false`
   - `IAP_ENABLE_PURCHASES=true`

## 7. Manual validation cases

Before launch, verify all of these in sandbox/test:

- iOS purchase grants Pro.
- Android purchase grants Pro.
- iOS restore on a second device restores the same Mixroom account.
- Android restore re-links the same Mixroom account.
- Renewal webhook updates entitlement revision.
- Cancel-at-period-end keeps access until expiry.
- Expiration removes access.
- Refund/revoke removes access.
- Another Mixroom account cannot claim an already-linked store subscription.

## 8. Rough KPI snapshot

Once the backend is live, you can print a rough active/cancel/churn snapshot with:

```bash
cd backend/app_api
python3 scripts/subscription_kpi_report.py --stage staging
```
