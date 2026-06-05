# Flutter/Native Bridge

Owner: Engineering  
Status: Draft  
Last reviewed: 2026-06-05  
Update trigger: Update this when method-channel names, payloads, event payloads,
platform implementations, or native social/auth bridge behavior changes.

## Purpose

The bridge is the contract between Flutter and platform code. Treat it like an
API. Changes need backward-compatible payloads where possible, explicit failure
behavior, and tests or manual QA on every supported platform.

## Audio Engine Channels

The main audio plugin declares:

- Method channel: `juce_audio_engine`
- Event channel: `juce_audio_engine/events`

Primary Dart entry point:

- `juce_audio_engine/lib/juce_audio_engine.dart`

Platform-level wrapper:

- `juce_audio_engine/lib/juce_audio_engine_method_channel.dart`

The iOS plugin podspec preserves the prebuilt JUCE archives and links the
correct archive through sdk/config-specific `OTHER_LDFLAGS`.

## Native App Channels

App-level native integration starts in:

- iOS: `ios/Runner/AppDelegate.swift`
- Android: `android/app/src/main/kotlin/com/moss/mossapp/MainActivity.kt`

Use these for platform features that belong to the app shell rather than the
audio plugin.

## Social Sign-In Bridge

Client entry points:

- `lib/helpers/native_social_sign_in.dart`
- `lib/config/native_social_auth_config.dart`
- `lib/helpers/auth_service.dart`

Backend entry points:

- `backend/app_api/src/handlers/api_auth.py`
- `backend/app_api/src/common/social_auth.py`
- `backend/app_api/src/common/native_auth.py`

The native layer obtains provider tokens or platform identity payloads. The app
API validates them and returns Mixroom app auth state. Do not trust provider
payloads solely because they came from a platform SDK.

## Contract Rules

- Keep channel names stable.
- Use maps with explicit keys for non-trivial payloads.
- Treat missing keys and unknown enum values as recoverable errors where
  possible.
- Log enough context to debug failures, but never log tokens, secrets, full
  credentials, or private user content.
- Add a compatibility note when changing payloads that released app versions may
  still send.

## Change Checklist

When changing a bridge method:

1. Update the Dart method signature and native implementation together.
2. Document the payload shape here if it is not obvious from a single function.
3. Test the affected platform directly.
4. Run `dart analyze` and relevant Flutter tests.
5. Update [Known platform issues](known_platform_issues.md) if behavior differs
   by platform.
