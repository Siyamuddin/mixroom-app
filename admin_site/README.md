# Admin Site

This is the standalone employee-facing admin website for Mixroom.

It is not part of the Flutter app.

For the concrete production rollout on `admin.mixroom.ai`, see:

- `admin_site/DEPLOY_ADMIN_MIXROOM_AI.md`

## Access model

- Employees sign in through Cognito Hosted UI.
- The admin API verifies the Cognito ID token.
- The admin API then checks a DynamoDB allowlist keyed by exact email address.
- If the email is not allowlisted, the employee can sign in but will get `403`.

That gives you both layers:

- real employee accounts
- explicit whitelist approval by email

## What gets deployed

Recommended production shape:

- `admin.yourcompany.com` -> CloudFront
- CloudFront -> private S3 bucket
- browser -> Cognito Hosted UI for employee login
- browser -> `GET /v1/internal/admin/overview`
- backend -> Cognito JWT verification + admin allowlist check

The site itself is plain HTML, CSS, and JS. No build step is required.

S3 is only the static origin for the website files. It is not where your admin data lives, and it is unrelated to future large blob storage in Cloudflare R2.

## Files

- `index.html`
- `styles.css`
- `config.js`
- `app.js`
- `infrastructure/aws_static_site.template.yaml`
- `scripts/deploy_site.sh`

## Backend requirements

The app API backend needs the admin overview route and allowlist table.

Relevant backend parameters:

- `CognitoUserPoolId`
- `CognitoAppClientId`
- `AdminCognitoAppClientId`
- `AiUsageStateTableName`
- `AiUsageEventsTableName`

Relevant backend output/resource:

- `GET /v1/internal/admin/overview`
- `mixroom-admin-allowlist-<stage>`

## 1. Deploy the backend

Deploy the app API stack first so the admin API and allowlist table exist:

```bash
cd backend/app_api
sam build
sam deploy --guided
```

Important admin-specific values during deploy:

- `CognitoUserPoolId`: your existing user pool
- `CognitoAppClientId`: your existing mobile/web app client if you already have one
- `AdminCognitoAppClientId`: create a separate app client for the admin website
- `AiUsageStateTableName`: optional, but needed for AI usage counters
- `AiUsageEventsTableName`: optional, but needed for AI-active project tracking

After deploy, note the `AppApiUrl` output.

## 2. Create the admin website host

Deploy the static-site stack:

```bash
aws cloudformation deploy \
  --stack-name mixroom-admin-site-prod \
  --template-file admin_site/infrastructure/aws_static_site.template.yaml \
  --parameter-overrides \
    SiteBucketName=mixroom-admin-site-prod \
    SiteDomainName=admin.yourcompany.com \
    AcmCertificateArn=arn:aws:acm:us-east-1:YOUR_ACCOUNT_ID:certificate/YOUR_CERT_ID \
    HostedZoneId=YOUR_ROUTE53_HOSTED_ZONE_ID
```

Notes:

- `AcmCertificateArn` must be in `us-east-1` for CloudFront custom domains.
- If you skip `SiteDomainName` and `AcmCertificateArn`, the stack still works and gives you a raw CloudFront URL.
- If `HostedZoneId` is provided, the template creates Route53 alias records automatically.

After deploy, collect these outputs:

- `SiteBucketName`
- `DistributionId`
- `SiteUrl`

## 3. Configure Cognito for employees

Use the same Cognito user pool as the app, but create a separate app client for the admin website.

Recommended admin app client settings:

- callback URL: your deployed admin site URL, for example `https://admin.yourcompany.com/`
- logout URL: same as callback URL
- scopes: `openid`, `email`, `profile`
- Hosted UI domain: enabled
- usernames: employee email addresses

This keeps employee admin access separate from the mobile app client.

## 4. Upload the site

The deploy script generates the live `config.js` during upload, so you do not need to hand-edit the checked-in file.

```bash
admin_site/scripts/deploy_site.sh \
  --bucket mixroom-admin-site-prod \
  --distribution-id YOUR_CLOUDFRONT_DISTRIBUTION_ID \
  --site-url https://admin.yourcompany.com/ \
  --api-base-url https://YOUR_API_ID.execute-api.YOUR_REGION.amazonaws.com/prod \
  --cognito-domain-url https://YOUR_DOMAIN.auth.YOUR_REGION.amazoncognito.com \
  --cognito-client-id YOUR_ADMIN_COGNITO_APP_CLIENT_ID
```

Optional:

- `--redirect-uri`: override callback URL if needed
- `--logout-uri`: override logout URL if needed
- `--scopes`: comma-separated scope list, default is `openid,email,profile`

## 5. Invite or allowlist employees

Recommended operator flow:

1. Add the employee to the admin allowlist.
2. Create or resend the Cognito employee account invite.

The helper script now does both in one command:

```bash
cd backend/app_api
python3 scripts/invite_admin_employee.py \
  --stage prod \
  --user-pool-id YOUR_USER_POOL_ID \
  --email employee@yourcompany.com \
  --invited-by you@yourcompany.com \
  --note "Support team"
```

If the employee already exists in Cognito and you want to resend the invitation email:

```bash
python3 scripts/invite_admin_employee.py \
  --stage prod \
  --user-pool-id YOUR_USER_POOL_ID \
  --email employee@yourcompany.com \
  --resend
```

If you only want to allowlist or disable access without touching Cognito:

```bash
python3 scripts/upsert_admin_allowlist.py \
  --stage prod \
  --email employee@yourcompany.com \
  --invited-by you@yourcompany.com
```

Disable later:

```bash
python3 scripts/upsert_admin_allowlist.py \
  --stage prod \
  --email employee@yourcompany.com \
  --disable
```

If you want the employee to stop being able to sign in at all, also disable the Cognito user in the console or with `aws cognito-idp admin-disable-user`.

## Day-to-day deploys

After the first setup, website updates are usually just:

```bash
admin_site/scripts/deploy_site.sh \
  --bucket mixroom-admin-site-prod \
  --distribution-id YOUR_CLOUDFRONT_DISTRIBUTION_ID \
  --site-url https://admin.yourcompany.com/ \
  --api-base-url https://YOUR_API_ID.execute-api.YOUR_REGION.amazonaws.com/prod \
  --cognito-domain-url https://YOUR_DOMAIN.auth.YOUR_REGION.amazoncognito.com \
  --cognito-client-id YOUR_ADMIN_COGNITO_APP_CLIENT_ID
```

Employees can then access the site at the same URL at any time.

## Local smoke test

For local UI checks:

```bash
cd admin_site
python3 -m http.server 4173
```

Then open:

```text
http://localhost:4173
```

For local sign-in testing, set the Cognito callback/logout URL to `http://localhost:4173/` and fill `admin_site/config.js` with local values.
