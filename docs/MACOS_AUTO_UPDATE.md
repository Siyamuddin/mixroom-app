# macOS Website Distribution And Automatic Updates

Mixroom's direct-download macOS build uses Flutter's `auto_updater` package,
which delegates the native update process to Sparkle 2. Sparkle checks the
appcast, verifies the archive's EdDSA signature and Apple code signature,
downloads the update, replaces only `Mixroom.app`, and relaunches it. User
projects and settings outside the application bundle are not replaced.

## Public URLs

Use this permanent link on the Mixroom website:

```text
https://www.mixroom.ai/downloads/Mixroom-macOS.dmg
```

The URL stays the same for every release. The website redirects this path to
the read-only download Worker, and publishing replaces the R2 object, so the
website maintainer never needs to change the download link. The redirect keeps
large files off Vercel's data-transfer bill.

Sparkle reads this permanent feed from inside the app:

```text
https://www.mixroom.ai/downloads/appcast.xml
```

Do not use the DMG in the Sparkle appcast. In-app updates use immutable,
versioned ZIPs under:

```text
https://www.mixroom.ai/downloads/releases/<version+build>/
```

Add this redirect to the Vercel website project's existing `vercel.json`
`redirects` array, then deploy the website:

```json
{
  "source": "/downloads/:path*",
  "destination": "https://downloads.mxr-downloads-prod.workers.dev/mac/:path*",
  "permanent": false
}
```

Use a redirect, not a rewrite. A rewrite proxies every DMG byte through
Vercel, while a redirect transfers the file directly from R2 through the
Worker. `mixroom.ai` already redirects to `www.mixroom.ai`, so website buttons
should use the canonical `www` URL above.

## Cloudflare R2 And Worker Setup

Use a dedicated public bucket. Never expose `mixroom-cloud-projects-prod`,
which contains private user data.

1. Create an R2 bucket named `mixroom-downloads-prod`.
2. Deploy the `downloads` Worker in `cloudflare/downloads-worker`. Its R2
   binding exposes the bucket read-only at
   `downloads.mxr-downloads-prod.workers.dev`.
   Keep the development `r2.dev` URL disabled.
3. Create R2 S3 credentials with Object Read & Write access limited to
   `mixroom-downloads-prod`. Copy the Access Key ID and Secret Access Key from
   the confirmation screen. A Cloudflare `cfat_...` token value alone is not
   accepted by S3 clients.
4. Store the access key ID in AWS SSM at
   `/mixroom/prod/r2/downloads/access-key-id` and its secret access key as a
   SecureString at `/mixroom/prod/r2/downloads/secret-access-key`. The release
   publisher loads both automatically through `AWS_PROFILE`. Run
   `tool/store_r2_download_credentials.sh` to enter both without placing them
   in shell history.
5. The publisher marks the appcast as `no-cache`. The stable DMG has a
   five-minute cache, while versioned ZIPs are immutable for one year.

Cloudflare R2 does not charge internet egress. R2 custom-domain caching has a
512 MB maximum object size on Free, Pro, and Business plans. Larger DMGs and
ZIPs still download from R2 without R2 egress charges; they simply bypass the
Cloudflare edge cache.

## One-Time Signing-Key Setup

The production EdDSA key was generated in the current macOS login Keychain.
Its public key is committed in `macos/Runner/Info.plist`. The matching private
key must never be committed to Git.

Export it once and store it in the team's password manager or CI secret store:

```bash
macos/Pods/Sparkle/bin/generate_keys \
  -x /secure/non-repository/path/mixroom-sparkle-private-key
```

On another release Mac, import that same key before publishing:

```bash
macos/Pods/Sparkle/bin/generate_keys \
  -f /secure/non-repository/path/mixroom-sparkle-private-key
```

Losing this key prevents installed builds from trusting future updates. Using
a different key also breaks the update path for every existing installation.

## Release Procedure

Every release must increment both the user-facing version and monotonically
increasing build number in `pubspec.yaml`, for example:

```yaml
version: 1.3.7+55
```

Build, sign, notarize, staple, and package the release:

```bash
MACOS_NOTARY_KEYCHAIN_PROFILE="mixroom-notary" \
script/package_macos_release.sh --build-name 1.3.7 --build-number 55
```

The packaging script automatically selects the installed Developer ID
Application identity for team `X8Y4B4222A`.

This produces:

```text
build/distribution/Mixroom-macOS.dmg
build/distribution/Mixroom-macOS.zip
```

Publish the stable website installer, signed Sparkle archive, appcast, and
macOS version policy together:

```bash
AWS_PROFILE=andrew-admin \
bash tool/publish_macos_update.sh \
  --version 1.3.7 \
  --build-number 55 \
  --min-supported-version 1.3.6 \
  --release-notes-url https://mixroom.ai/releases/1.3.7
```

Omit `--min-supported-version` for a normal optional update. Set it only when
older builds must be blocked from normal app use. Only publish after the
notarized build passes release testing. Never edit an already-published
versioned ZIP or reuse a build number.

## User Experience

`SUEnableAutomaticChecks` is enabled and checks run every six hours. Fully
silent installation is deliberately disabled. This gives Mixroom a Slack-like
flow:

1. Mixroom checks quietly at startup and on Sparkle's schedule.
2. When a newer build exists, Sparkle shows the native update prompt.
3. If the user postpones it, an orange dot remains on the top rail Mixroom
   icon. Clicking it opens the version panel and its `Update Mixroom` action.
4. The user accepts the update and chooses restart/install.
5. Sparkle verifies, replaces `Mixroom.app`, and relaunches Mixroom.

The existing Mixroom "Check for updates" and "Update Mixroom" controls invoke
the same native Sparkle flow. Mobile builds continue to use their app stores.
Users running a pre-updater build must install the new DMG once. Every release
after that can update itself.

## Website System Requirements

Publish this beside the download button:

```text
Requires macOS 14 Sonoma or later. Apple silicon Mac required.
```

The minimum is enforced by the app's `MACOSX_DEPLOYMENT_TARGET`, currently
`14.0`. The currently verified build architecture is arm64. Do not advertise
Intel support until every executable and embedded framework in the notarized
release is verified as universal. Keep this text aligned if either changes.

## Verification

Before publishing, inspect the signatures and Gatekeeper status:

```bash
codesign --verify --deep --strict --verbose=4 \
  build/macos/Build/Products/Release/Mixroom.app
xcrun stapler validate build/distribution/Mixroom-macOS.dmg
spctl -a -vv --type open --context context:primary-signature \
  build/distribution/Mixroom-macOS.dmg
```

After publishing, verify the stable URLs and appcast archive URL:

```bash
curl -fsSI https://www.mixroom.ai/downloads/Mixroom-macOS.dmg
curl -fsS https://www.mixroom.ai/downloads/appcast.xml
```

Test the updater with a lower-version signed build installed in `/Applications`
and a higher-version test appcast. A production update test is valid only when
the archive is signed with the same EdDSA key embedded in the installed app.
