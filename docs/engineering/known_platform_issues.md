# Known Platform Issues

Owner: Engineering  
Status: Draft  
Last reviewed: 2026-06-05  
Update trigger: Update this when platform support, SDK requirements, plugin
behavior, audio routing, permissions, file access, or store requirements change.

## Purpose

This page records platform differences that can surprise a new developer. Keep
it factual and tied to current code or release requirements.

## iOS

- JUCE library selection in `juce_audio_engine/ios/juce_audio_engine.podspec`
  is automatic through sdk/config-specific linker flags.
- The selected archive still differs for simulator, debug device, and
  Profile/Release device builds.
- App Store Connect requires the iOS 26 SDK for uploads starting 2026-04-28.
- Photo library permission text exists for user-initiated export/save flows in
  `ios/Runner/Info.plist`.

## Android

- Android, iOS, and macOS use `ffmpeg_kit_flutter_new_full`.
- Android Play releases must pass 16 KB native library alignment checks.
- Native audio and asset-pack behavior can depend on ABI, NDK, Gradle, and
  packaged sample/instrument assets.
- Test real-device audio routing and recording behavior before shipping native
  audio changes.

## macOS

- Desktop builds can differ for plugin hosting, file dialogs, sandboxing,
  signing, notarization, and export destinations.
- See `docs/DESKTOP_PLUGIN_HOSTING.md` before changing desktop plugin behavior.

## Windows

- Treat Windows as a separate build and file-access target. Verify export paths,
  plugin behavior, and bundled native dependencies directly on Windows before
  release.

## Cross-Platform Risks

- Audio route changes can behave differently on Bluetooth, wired devices,
  speakers, simulators, emulators, and desktops.
- Export behavior may differ by platform based on native renderer and FFmpeg
  availability.
- Social auth requires platform console configuration and backend deploy
  parameters to match.
- Store disclosures must match actual SDKs, permissions, analytics, crash
  reporting, auth, billing, and AI usage.
