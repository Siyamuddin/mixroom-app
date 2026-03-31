# Remote Operations

This is the operator runbook for the parts of Mixroom that can be adjusted
without shipping a new app binary.

Use this doc when you need to:

- change AI chat runtime behavior
- change free prompt limits
- publish new corrective magnitude ONNX models
- show a welcome onboarding experience to new users
- show an announcement banner or modal to signed-in users

This doc is intentionally concise. It is the source of truth for runtime-safe
remote changes.

## What Is Remotely Adjustable

### 1. Admin AI Runtime Overrides

Surface:

- Admin API / admin dashboard

What you can change:

- `model_override`
- `system_prompt_override`
- `max_output_tokens_override`
- `temperature_override`
- `reasoning_effort_override`
- `prompt_cache_retention_override`

Supported features:

- `ai_chat`
- `video_editor_chat`

Notes:

- These are server-side only.
- They affect the LLM proxy path, not local ONNX models.
- They are reflected in prompt observability via
  `runtime_config_fingerprint` and `has_system_prompt_override`.

Relevant API:

- `GET /v1/internal/admin/settings/ai-runtime`
- `PUT /v1/internal/admin/settings/ai-runtime`

### 2. Admin Free Prompt Limits

Surface:

- Admin API / admin dashboard

What you can change:

- `free_daily_prompt_limit`
- `free_weekly_prompt_limit`

Notes:

- These apply only to free-tier prompt quotas.
- The proxy caches them briefly, so changes are not necessarily instant to the
  second, but they do not require a redeploy.

Relevant API:

- `GET /v1/internal/admin/settings/ai-prompt-limits`
- `PUT /v1/internal/admin/settings/ai-prompt-limits`

### 3. Remote Magnitude Models

Purpose:

- OTA updates for the non-YAMNet ONNX models:
  - `mix_apply_classifier*.onnx`
  - `mix_magnitude_regressor*.onnx`

Current manifest URL:

```text
https://d22u50embnfa6f.cloudfront.net/magnitude/manifest.json
```

Important behavior:

- Bundled models remain the permanent fallback.
- Remote updates are background-only and do not block prompt submission.
- Bad or disabled remote bundles revert to bundled assets.

### 4. Remote Welcome Onboarding

Purpose:

- First signed-in welcome screen for newly created accounts

Current manifest URL:

```text
https://d22u50embnfa6f.cloudfront.net/welcome/manifest.json
```

Important behavior:

- Only applies to users who have not yet reached `welcome_seen`.
- Safe fallback if manifest, media, or rendering fails.
- Disabled manifest removes the installed remote campaign.

### 5. Remote Announcements

Purpose:

- Signed-in app-open banner and/or modal without a new app submission

Current manifest URL:

```text
https://d22u50embnfa6f.cloudfront.net/announcements/manifest.json
```

Important behavior:

- Supports `banner`, `modal`, or `both`
- Modal shows once per announcement version per device
- Banner stays until dismissed for that version
- Disabled manifest removes the installed remote announcement

## What Is Not Remotely Adjustable

- YAMNet model weights
- native JUCE prompt-analysis logic
- tutorial step content / DAW tutorial flow
- local mixing execution code
- app-shell structure itself

Those still require an app release.

## Safe Operating Principles

For every remote surface above:

- keep the app functional with no remote config present
- keep remote content optional, never required for core app operation
- change version identifiers every time you publish a new bundle/campaign
- use rollout percentages for risky changes
- gate by app version if compatibility is uncertain
- keep URLs on the trusted AWS CDN origin
- prefer rollback by manifest first, not by deleting app assets

## Standard Change Flow

Use this sequence for any remote update.

1. Prepare the content or settings.
2. Test on an internal build or your own account/device first.
3. Start with a low rollout if the change is risky.
4. Confirm telemetry shows expected version + success statuses.
5. Increase rollout only after validation.
6. If something goes wrong, disable or revert at the manifest/admin layer first.

## SOP: AI Runtime Changes

Use for:

- prompt tweaks
- model swaps
- token / reasoning tuning

How to change:

1. Open admin AI runtime settings.
2. Change only the feature you intend to modify.
3. Save the override.
4. Send a real prompt.
5. Check:
   - admin prompt observability
   - `runtime_config_fingerprint`
   - `effective_model`
   - prompt success/failure rate

Rollback:

- Clear the override fields in admin.

Failure signs:

- prompt failures spike
- latency jumps unexpectedly
- `runtime_config_fingerprint` changed but behavior is clearly wrong

## SOP: Prompt Limit Changes

Use for:

- beta quota tuning
- temporary support / promo quota changes

How to change:

1. Update free daily / weekly prompt limits in admin.
2. Verify on a free-tier account.
3. Confirm the app quota dialog shows the new window/remaining values after
   cache refresh.

Rollback:

- restore previous limit values in admin

## SOP: Remote Magnitude Models

Use for:

- better producer-trained corrective models without an app-store resubmission

Before publishing:

- validate the model pair locally
- keep input/output schema compatible with the app
- keep the bundled pair untouched as fallback

Publish command:

```bash
bash tool/publish_magnitude_models.sh \
  --apply-model /absolute/path/to/mix_apply_classifier_v1.onnx \
  --magnitude-model /absolute/path/to/mix_magnitude_regressor_v1.onnx \
  --bundle-version 2026-03-29-mag-v1 \
  --bucket mixroom-magnitude-models-prod \
  --region ap-northeast-2 \
  --public-base-url https://d22u50embnfa6f.cloudfront.net/magnitude \
  --distribution-id E9GVRRNS9G2HJ \
  --min-app-version 1.0.9+15
```

How to test before broad release:

1. Publish with a new `bundle_version`.
2. Use a device on the new app build.
3. Open the audio editor.
4. Wait for background refresh.
5. Send a corrective mix prompt.
6. Confirm telemetry shows:
   - `ai_magnitude_model_update`
   - `mix_magnitude_model_source=remote`
   - expected bundle/model versions

Rollback:

- publish a disabled or incompatible manifest
- or publish the prior known-good bundle as the current manifest target

Failure signs:

- `activation_failed`
- `download_failed`
- `mix_magnitude_model_source` stays `bundled`
- prompt flow falls back unexpectedly

## SOP: Remote Welcome Onboarding

Use for:

- first-run welcome visuals/messages for newly created accounts

Publish command:

```bash
bash tool/publish_remote_welcome_campaign.sh \
  --campaign-version 2026-03-29-welcome-v1 \
  --bucket mixroom-magnitude-models-prod \
  --region ap-northeast-2 \
  --public-base-url https://d22u50embnfa6f.cloudfront.net/welcome \
  --distribution-id E9GVRRNS9G2HJ \
  --media-file /absolute/path/to/welcome.mp4 \
  --media-type video \
  --title "Welcome to Mixroom" \
  --body "Create faster with AI production tools." \
  --primary-label "Get started" \
  --secondary-label "Skip" \
  --min-app-version 1.0.9+15 \
  --min-account-created-at 2026-03-29T00:00:00Z
```

How to test:

1. Use an account that has not been marked `welcome_seen`.
2. Ensure the account creation time falls inside the campaign window.
3. Sign in on the new app build.
4. Confirm the screen shows and completes normally.
5. Confirm telemetry shows:
   - `remote_welcome_campaign_update`
   - `welcome_onboarding_shown`
   - `welcome_onboarding_completed`

Rollback:

```bash
bash tool/publish_remote_welcome_campaign.sh \
  --campaign-version 2026-03-29-welcome-disabled \
  --bucket mixroom-magnitude-models-prod \
  --region ap-northeast-2 \
  --public-base-url https://d22u50embnfa6f.cloudfront.net/welcome \
  --distribution-id E9GVRRNS9G2HJ \
  --disable
```

## SOP: Remote Announcements

Use for:

- release notes
- launch notices
- short upgrade / promotion messaging
- maintenance or outage communication

Publish live announcement:

```bash
bash tool/publish_remote_announcement.sh \
  --announcement-version 2026-03-29-announcement-v1 \
  --bucket mixroom-magnitude-models-prod \
  --region ap-northeast-2 \
  --public-base-url https://d22u50embnfa6f.cloudfront.net/announcements \
  --distribution-id E9GVRRNS9G2HJ \
  --presentation-mode both \
  --style info \
  --title "New mastering update" \
  --body "Native analysis and safer remote model updates are now live." \
  --primary-label "Learn more" \
  --secondary-label "Dismiss" \
  --primary-action-url https://mixroom.ai/updates/native-analysis \
  --media-file /absolute/path/to/hero.png \
  --min-app-version 1.0.9+15
```

How to test:

1. Publish a new `announcement_version`.
2. Open the signed-in shell on an internal device/account.
3. Confirm the intended `banner` / `modal` behavior.
4. Tap primary action and dismiss action.
5. Confirm telemetry shows:
   - `remote_announcement_update`
   - `remote_announcement_shown`
   - `remote_announcement_interacted`

Rollback:

```bash
bash tool/publish_remote_announcement.sh \
  --announcement-version 2026-03-29-announcement-disabled \
  --bucket mixroom-magnitude-models-prod \
  --region ap-northeast-2 \
  --public-base-url https://d22u50embnfa6f.cloudfront.net/announcements \
  --distribution-id E9GVRRNS9G2HJ \
  --disable
```

## Testing Notes

These remote surfaces only exist on app builds that already include the client
code:

- magnitude updater
- remote welcome
- remote announcements

So the sequence is:

1. ship the app build once
2. use remote updates after that

For each new remote feature version:

- test on at least one internal device
- verify the expected analytics event exists
- verify the version string matches what you published
- verify rollback works before broad rollout

## Monitoring Summary

### Admin / Prompt Observability

Use admin + PostHog for:

- prompt cycle timing
- model/runtime fingerprints
- tool usage
- magnitude model source/version

### Key Event Names

Use these as the main checks.

- `ai_prompt_cycle_completed`
- `ai_prompt_cycle_failed`
- `ai_magnitude_model_update`
- `remote_welcome_campaign_update`
- `welcome_onboarding_shown`
- `welcome_onboarding_completed`
- `remote_announcement_update`
- `remote_announcement_shown`
- `remote_announcement_interacted`

## Current Production URLs

- magnitude manifest:
  - `https://d22u50embnfa6f.cloudfront.net/magnitude/manifest.json`
- welcome manifest:
  - `https://d22u50embnfa6f.cloudfront.net/welcome/manifest.json`
- announcement manifest:
  - `https://d22u50embnfa6f.cloudfront.net/announcements/manifest.json`

## Current AWS Publishing Scripts

- `tool/publish_magnitude_models.sh`
- `tool/publish_remote_welcome_campaign.sh`
- `tool/publish_remote_announcement.sh`
