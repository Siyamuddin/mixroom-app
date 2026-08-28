# Build And Release Process

Owner: Release Engineering  
Status: Draft  
Last reviewed: 2026-06-05  
Update trigger: Update this when build commands, release targets, signing,
store requirements, compliance gates, SDK requirements, deployment steps, or
release ownership changes.

## Purpose

This page gives engineers the technical release path. The compliance checklist
still lives in `docs/RELEASE_COMPLIANCE_CHECKLIST.md`.

## Pre-Release Checks

Run docs freshness:

```bash
dart run tool/check_docs_freshness.dart --base origin/main
```

Developers can also enable repo-owned Git hooks:

```bash
git config core.hooksPath tool/git-hooks
```

The hook scripts live in `tool/git-hooks/`.

Run analysis and tests appropriate to the change:

```bash
dart analyze
flutter test
```

Run the AI IP source gate for every app release candidate:

```bash
dart run tool/check_ai_ip_boundary.dart --static
```

For backend changes, run the relevant backend test suite from the backend
directory before deploying.

## Platform Build Notes

### Android

Build the requested artifact:

```bash
flutter build apk
flutter build appbundle
```

Before Play submission, verify the final APK/AAB passes Android 16 KB native
library alignment checks.

### iOS

`juce_audio_engine/ios/juce_audio_engine.podspec` selects the correct JUCE
archive automatically for simulator, debug device, and Profile/Release device
builds.

App Store Connect requires builds made with the iOS 26 SDK starting
2026-04-28. Run:

```bash
./tools/ios/check_xcode_26_sdk.sh
```

### macOS And Windows

Use the Flutter desktop build commands and check platform-specific plugin,
file-access, and signing behavior before release.

```bash
flutter build macos
flutter build windows
```

Scan each release-equivalent output before signing or distribution. Pass the
APK/AAB archive itself and the unpacked iOS, macOS, and Windows application
directories so assets, native/AOT binaries, frameworks, and symbol bundles are
included:

```bash
dart run tool/check_ai_ip_boundary.dart --artifact <artifact-or-directory>
```

Any V3 or other-AI finding blocks distribution. Update the reviewed manifest
only when a value is proven non-sensitive; do not allowlist an unrelated prompt
or direct-provider marker to make a release pass.

## Backend Deploys

App API and AI proxy deployments use AWS SAM and related scripts. Start with:

- `backend/app_api/README.md`
- `backend/llm_proxy/README.md`
- `docs/REMOTE_OPERATIONS.md`
- `docs/BETA_AWS_OPENAI_SETUP_CHECKLIST.md`

Do not treat app release and backend release as independent when auth, billing,
entitlements, AI actions, feature flags, or cloud project behavior changes.

For an AI V3 client release, deploy and verify the authenticated context-only
`/v1/llm/v3/responses` route before distributing a build with
`AI_V3_PRIMARY_ENABLED=true`. Backend contract v2 owns all V3 semantics and
provider policy. Keep `AI_V3_SERVER_CONTRACT_ENABLED=true` and
`AI_V3_LEGACY_CLIENT_CONTRACT_ENABLED=true` while released legacy clients need
compatibility. A client build with `AI_V3_PRIMARY_ENABLED=false` keeps the
existing V1 route; the app never silently retries an individual failed V3
request through V1.

## Release Sign-Off

Before public release, record owners for:

- app build and store upload
- backend deploy
- auth/billing verification
- privacy/legal compliance
- licensing and third-party notices
- crash/analytics monitoring
- rollback decision
