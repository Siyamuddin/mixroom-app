# Local Setup

Owner: Engineering  
Status: Draft  
Last reviewed: 2026-06-05  
Update trigger: Update this when supported platforms, required SDK versions,
native library selection, media dependencies, or backend local setup changes.

## Purpose

This page gets a new developer from a clean machine to a running Mixroom build.
The app is a Flutter client with native audio integration, platform-specific
media dependencies, and optional backend services.

## Required Tools

- Flutter and Dart, matching the version expected by `pubspec.yaml`
- Xcode for iOS and macOS builds
- Android Studio, Android SDK, and Android NDK for Android builds
- CocoaPods for iOS plugin integration
- AWS CLI and SAM CLI for backend work
- Python for backend test and deploy scripts

## First Run

From the repo root:

```bash
flutter pub get
```

The app uses `ffmpeg_kit_flutter_new_full` for Android, iOS, and macOS.
For Android Play releases, verify the final APK/AAB passes 16 KB native
library alignment checks before submission.

## iOS Native Audio Library Selection

`juce_audio_engine/ios/juce_audio_engine.podspec` automatically selects the
prebuilt JUCE archive through sdk/config-specific `OTHER_LDFLAGS`.

- Debug on a real device: `ios-arm64/libJuceModules_debug3.a`
- Profile/Release on a real device: `ios-arm64/libJuceModules.a`
- Simulator: `ios-arm64_x86_64-simulator/libJuceModules_sim.a`

## Common App Commands

Analyze:

```bash
dart analyze
```

Run Flutter tests:

```bash
flutter test
```

Run the integration suite:

```bash
./tool/run_integration_suite.sh
```

## Backend Setup Pointers

The main backend docs live outside this section:

- `backend/app_api/README.md`
- `backend/llm_proxy/README.md`
- `docs/BETA_AWS_OPENAI_SETUP_CHECKLIST.md`
- `docs/BETA_EXTERNAL_SETUP_CHECKLIST.md`

Use those docs when working on auth, billing, entitlements, admin APIs, AI
proxy behavior, or deployment.
