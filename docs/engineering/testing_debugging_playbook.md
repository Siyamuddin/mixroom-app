# Testing And Debugging Playbook

Owner: Engineering  
Status: Draft  
Last reviewed: 2026-08-29
Update trigger: Update this when test commands, QA flows, diagnostics, logging,
crash reporting, integration tests, or release gates change.

## Purpose

This page tells a developer which checks to run and where to look when a change
breaks app behavior.

## Fast Local Checks

Run analysis:

```bash
dart analyze
```

Run unit/widget tests:

```bash
flutter test
```

Run integration suite:

```bash
./tool/run_integration_suite.sh
```

Run docs freshness before commit or PR:

```bash
dart run tool/check_docs_freshness.dart --staged
dart run tool/check_docs_freshness.dart --base origin/main
```

## Backend Tests

Backend tests live under:

- `backend/app_api/tests/`
- `backend/llm_proxy/tests/`

Use targeted tests while iterating and the wider suite before deploy. Start with
tests matching the handler or common module you changed.

For authenticated V3 routing changes, cover the dedicated V3 endpoint, its
server kill switch, the unchanged V1 endpoint, client token refresh, and the
client build switch before running the wider Flutter V3 suite.

For V3 AI-IP boundary changes, run the source and release-artifact scanner:

```bash
dart run tool/check_ai_ip_boundary.dart --static
dart run tool/check_ai_ip_boundary.dart --artifact <release-file-or-directory>
```

Scan complete Android archives, Apple app bundles, and the Windows Release
directory. A V3 or cross-AI finding blocks distribution; update the backend
boundary instead of adding an unexplained allowlist exception.

For V3 execution-policy changes, verify the canonical policy table covers every
command, clear plans return `execute_now`, no success message appears before
readback, and synthetic future `confirm` commands retain Apply/Cancel. Run the
V3 unit suites plus focused macOS atomic commit, rollback, and slow local-action
integration cases. The combined macOS runner can occasionally disconnect; when
it does, rerun the interrupted case in isolation and report the harness failure
separately.

## Useful Debug Entry Points

- Analytics: `docs/ANALYTICS.md`
- Remote operations: `docs/REMOTE_OPERATIONS.md`
- Auth QA: `docs/BETA_AUTH_QA_CHECKLIST.md`
- Integration tests: `docs/INTEGRATION_TESTS.md`
- AI chat cookbook: `lib/ai/README_CHATBAR_COOKBOOK.md`
- Audio export analyzer: `tool/audio_export_analyze.dart`
- Local AI debug config: `tool/local_ai_debug.example.json`

## Audio Debugging

When debugging audio, identify which layer failed:

1. Flutter UI state and command construction.
2. Dart plugin API call.
3. Native method-channel handling.
4. Native engine operation.
5. File output, event reporting, or playback route.

Keep real-time audio constraints in mind. A freeze may come from a blocking
operation on the native audio path, not from Flutter UI code.

## Auth Debugging

Auth failures usually involve one of:

- platform SDK payload creation
- app API token validation
- secure token storage
- backend environment variables or secrets
- social-provider console configuration
- stale app version using an older payload contract

Check client logs, app API logs, and the matching backend auth tests.

## Release Debugging

Release-only failures often come from:

- unexpected iOS JUCE archive selection in the podspec linker settings
- wrong FFmpeg variant
- missing store/provider console setup
- signing, entitlement, or permission mismatch
- backend deploy mismatch with the app build
- release build optimizer removing or changing native assets
