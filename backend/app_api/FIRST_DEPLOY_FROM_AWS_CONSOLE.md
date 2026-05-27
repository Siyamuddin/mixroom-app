# First Deploy From AWS Console

This is the lowest-friction first deploy path for the Mixroom app API if you prefer the AWS website over local terminal setup.

## Before you start

- Have an AWS account with billing enabled.
- Pick one AWS Region and stay in it for this backend.
- Make sure your Cognito user pool is in the same Region, or be very deliberate if it is not.
- Keep payments off in the app until the backend is deployed and tested.

Recommended first Region for Mixroom:

- `ap-northeast-2` if you want Seoul-first ops
- `us-east-1` if most of your tooling and examples will be US-first

## What will happen

You will use AWS CloudShell from inside the AWS Console.

- No local AWS CLI setup required.
- No local credential setup required.
- SAM is already available in CloudShell.

## 1. Open the right AWS pages

1. Sign into AWS Console.
2. Set the top-right Region selector to the Region you want to use.
3. Open:
   - CloudShell
   - CloudFormation
   - Lambda
   - API Gateway
   - DynamoDB
   - Systems Manager Parameter Store

## 2. Put the code into CloudShell

Use one of these:

- Easiest: compress `backend/app_api` on your Mac and upload that zip in CloudShell.
- Or: upload the whole repo to a place CloudShell can reach, then clone it.

After upload in CloudShell:

```bash
mkdir -p ~/mixroom
cd ~/mixroom
unzip ~/app_api.zip
cd app_api
```

If your zip extracts into a nested folder, just `cd` into the folder that contains `template.yaml`.

Check you are in the right place:

```bash
pwd
ls
```

You should see:

- `template.yaml`
- `src/`
- `requirements.txt`

## 3. First deploy commands

Run these in CloudShell:

```bash
cd ~/mixroom/app_api
sam build
sam deploy --guided
```

For the guided answers, use this baseline:

- Stack Name: `mixroom-app-api-prod`
- AWS Region: keep the console Region you already selected
- Confirm changes before deploy: `Y`
- Allow SAM CLI IAM role creation: `Y`
- Disable rollback: `N`
- Save arguments to configuration file: `Y`
- SAM configuration file: press Enter
- SAM configuration environment: `default`

Parameter values for the first deploy:

- `StageName`: `prod`
- `CognitoUserPoolId`: your Cognito user pool id
- `CognitoAppClientId`: your Cognito app client id
- `AllowStudioTier`: `false`
- `AppleBundleId`: leave blank if not ready
- `AppleAppId`: `0` if not ready
- `AppleRootCaParameterName`: leave blank if not ready
- `AppleSharedSecretParameterName`: leave blank if not ready
- `GooglePlayPackageName`: leave blank if not ready
- `GoogleServiceAccountParameterName`: leave blank if not ready
- `GooglePubSubAudience`: leave blank if not ready
- `GooglePubSubServiceAccountEmail`: leave blank if not ready
- `PaddleWebhookSecretParameterName`: leave blank
- `TossWebhookSecretParameterName`: leave blank

This first deploy is allowed to be partial. It creates the backend infrastructure even before Apple and Google are fully configured.

## 4. Get the important outputs

After deploy finishes, run:

```bash
aws cloudformation describe-stacks \
  --stack-name mixroom-app-api-prod \
  --query "Stacks[0].Outputs"
```

Write down these output values:

- `AppApiUrl`
- `AppleWebhookUrl`
- `GoogleWebhookUrl`
- `CatalogMappingsTableName`

You can also see the same outputs in:

- CloudFormation
- Stacks
- `mixroom-app-api-prod`
- Outputs tab

## 5. Seed the minimum product mapping rows

Still in CloudShell:

```bash
cd ~/mixroom/app_api
python3 scripts/seed_catalog_mappings.py
```

That prints the 2 default rows for:

- `apple:mixroom_producer_monthly`
- `google:mixroom_producer_monthly`

When you are ready to write them into DynamoDB:

```bash
python3 scripts/seed_catalog_mappings.py --apply --stage prod
```

You can confirm them in:

- DynamoDB
- Tables
- `mixroom-catalog-mappings-prod`
- Explore table items

## 6. Minimal app hookup after deploy

Do not enable payments yet. First, point the app at the backend:

```bash
flutter run \
  --dart-define=APP_API_BASE_URL=https://YOUR_API_ID.execute-api.YOUR_REGION.amazonaws.com/prod \
  --dart-define=SUBSCRIPTION_ENFORCE=false \
  --dart-define=IAP_ENABLE_PURCHASES=false
```

That lets the app talk to the backend without actually charging anyone.

## 7. What to do next in AWS Console

After the first deploy, the next AWS-only tasks are:

1. Create the Apple and Google values in SSM Parameter Store.
2. Re-deploy the same stack with the real parameter names and package names.
3. Verify the webhook URLs are reachable.
4. Later, if you add Paddle or Toss, store their webhook secrets as SSM
   `SecureString` parameters and re-deploy.

## 8. If you get stuck

The most common first-deploy issues are:

- wrong AWS Region selected
- CloudShell not opened in the Region you want
- wrong Cognito IDs
- uploading the wrong folder level
- forgetting to stay in the folder that contains `template.yaml`

If `sam deploy --guided` succeeds once, the next deploys are usually just:

```bash
cd ~/mixroom/app_api
sam build
sam deploy
```
