# Deploy `admin.mixroom.ai`

This is the shortest complete runbook for getting the Mixroom admin site live.

## Assumptions

- Admin URL: `https://admin.mixroom.ai/`
- Cognito region: `ap-northeast-2`
- Existing Cognito user pool: `ap-northeast-2_NkxXsFx8Q`
- Existing Cognito Hosted UI domain:
  `https://ap-northeast-2nkxxsfx8q.auth.ap-northeast-2.amazoncognito.com`
- Production app API stack name: `mixroom-app-api-prod`
- Production admin site stack name: `mixroom-admin-site-prod`
- Production AI usage tables:
  - `mixroom-ai-usage-metrics-prod`
  - `mixroom-ai-usage-events-prod`
- DNS for `mixroom.ai` is managed in Cloudflare

This setup stays intentionally small:

- `CloudFront + private S3` for the static site
- existing Cognito user pool for employee login
- existing app API for admin data
- DynamoDB allowlist for approved employee emails
- no Route53
- no WAF
- no extra backend service

S3 here is only the static file origin for the site. It is not where app data lives.

## 1. Request the TLS certificate

CloudFront custom domains require ACM in `us-east-1`.

```bash
aws acm request-certificate \
  --region us-east-1 \
  --domain-name admin.mixroom.ai \
  --validation-method DNS
```

Then add the ACM validation CNAME in Cloudflare for `mixroom.ai`.

Wait until the certificate is issued, then note the certificate ARN.

## 2. Create the admin Cognito app client

In user pool `ap-northeast-2_NkxXsFx8Q`, create a new app client:

- name: `mixroom-admin-site`
- callback URL: `https://admin.mixroom.ai/`
- logout URL: `https://admin.mixroom.ai/`
- scopes: `openid`, `email`, `profile`
- client type: public, no client secret

Keep using the existing Hosted UI domain:

- `https://ap-northeast-2nkxxsfx8q.auth.ap-northeast-2.amazoncognito.com`

After creation, note the new admin app client ID.

## 3. Redeploy the app API backend

Your production app API stack needs to know the admin app client ID and the AI usage tables.

If you already deploy production with saved SAM parameters, keep using that and make sure these are set:

- `StageName=prod`
- `CognitoUserPoolId=ap-northeast-2_NkxXsFx8Q`
- `AdminCognitoAppClientId=YOUR_ADMIN_APP_CLIENT_ID`
- `AiUsageStateTableName=mixroom-ai-usage-metrics-prod`
- `AiUsageEventsTableName=mixroom-ai-usage-events-prod`

If you deploy manually, the admin-specific part is:

```bash
cd backend/app_api
sam build
sam deploy \
  --stack-name mixroom-app-api-prod \
  --parameter-overrides \
    StageName=prod \
    CognitoUserPoolId=ap-northeast-2_NkxXsFx8Q \
    CognitoAppClientId=6c7nkqmrrjvkjibpjurmehpa52 \
    AdminCognitoAppClientId=YOUR_ADMIN_APP_CLIENT_ID \
    AiUsageStateTableName=mixroom-ai-usage-metrics-prod \
    AiUsageEventsTableName=mixroom-ai-usage-events-prod
```

If production already uses additional Apple, Google, Paddle, Toss, or secret parameters, keep passing them too.

After deploy, get the API base URL:

```bash
aws cloudformation describe-stacks \
  --stack-name mixroom-app-api-prod \
  --query "Stacks[0].Outputs[?OutputKey=='AppApiUrl'].OutputValue" \
  --output text
```

## 4. Deploy the admin site infrastructure

Deploy the AWS hosting stack:

```bash
aws cloudformation deploy \
  --stack-name mixroom-admin-site-prod \
  --template-file admin_site/infrastructure/aws_static_site.template.yaml \
  --parameter-overrides \
    SiteBucketName=mixroom-admin-site-prod \
    SiteDomainName=admin.mixroom.ai \
    AcmCertificateArn=arn:aws:acm:us-east-1:YOUR_ACCOUNT_ID:certificate/YOUR_CERT_ID
```

Get the CloudFront domain name:

```bash
aws cloudformation describe-stacks \
  --stack-name mixroom-admin-site-prod \
  --query "Stacks[0].Outputs[?OutputKey=='DistributionDomainName'].OutputValue" \
  --output text
```

Create this DNS record in Cloudflare:

- type: `CNAME`
- name: `admin`
- target: the CloudFront distribution domain
- proxy status: `DNS only`

## 5. Upload the website

Get the distribution ID:

```bash
aws cloudformation describe-stacks \
  --stack-name mixroom-admin-site-prod \
  --query "Stacks[0].Outputs[?OutputKey=='DistributionId'].OutputValue" \
  --output text
```

Deploy the site:

```bash
admin_site/scripts/deploy_site.sh \
  --bucket mixroom-admin-site-prod \
  --distribution-id YOUR_CLOUDFRONT_DISTRIBUTION_ID \
  --site-url https://admin.mixroom.ai/ \
  --api-base-url https://YOUR_API_ID.execute-api.ap-northeast-2.amazonaws.com/prod \
  --cognito-domain-url https://ap-northeast-2nkxxsfx8q.auth.ap-northeast-2.amazoncognito.com \
  --cognito-client-id YOUR_ADMIN_APP_CLIENT_ID
```

That command generates the live `config.js` during upload.

## 6. Invite employees

Allowlist an employee and create the Cognito account:

```bash
cd backend/app_api
python3 scripts/invite_admin_employee.py \
  --stage prod \
  --user-pool-id ap-northeast-2_NkxXsFx8Q \
  --region ap-northeast-2 \
  --email employee@mixroom.ai \
  --invited-by you@mixroom.ai
```

Disable access later:

```bash
python3 scripts/upsert_admin_allowlist.py \
  --stage prod \
  --email employee@mixroom.ai \
  --disable
```

## 7. Verify it works

Check these:

1. `https://admin.mixroom.ai/` loads over HTTPS
2. Sign In opens Cognito Hosted UI
3. An allowlisted employee can sign in and see data
4. A non-allowlisted employee gets blocked

## Ongoing deploy

For normal site updates, just rerun:

```bash
admin_site/scripts/deploy_site.sh \
  --bucket mixroom-admin-site-prod \
  --distribution-id YOUR_CLOUDFRONT_DISTRIBUTION_ID \
  --site-url https://admin.mixroom.ai/ \
  --api-base-url https://YOUR_API_ID.execute-api.ap-northeast-2.amazonaws.com/prod \
  --cognito-domain-url https://ap-northeast-2nkxxsfx8q.auth.ap-northeast-2.amazoncognito.com \
  --cognito-client-id YOUR_ADMIN_APP_CLIENT_ID
```
