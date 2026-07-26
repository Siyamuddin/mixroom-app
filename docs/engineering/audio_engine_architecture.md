# Audio Engine Architecture

Owner: Audio Engineering  
Status: Draft  
Last reviewed: 2026-06-05  
Update trigger: Update this when playback, recording, plugin scanning,
rendering/export, MIDI, routing, bundled native libraries, or JUCE build inputs
change.

## Purpose

The audio engine gives the Flutter app a production-oriented audio layer without
putting real-time audio work in Dart. Flutter calls the plugin API, the plugin
bridges into native code, and the native side performs audio processing,
playback, recording, plugin handling, and export.

## Main Entry Points

- Dart API: `juce_audio_engine/lib/juce_audio_engine.dart`
- Platform interface: `juce_audio_engine/lib/juce_audio_engine_platform_interface.dart`
- Method channel implementation: `juce_audio_engine/lib/juce_audio_engine_method_channel.dart`
- iOS podspec and library selection: `juce_audio_engine/ios/juce_audio_engine.podspec`
- Android native integration: `juce_audio_engine/android/`
- Editor callers: `lib/screens/audio_editor.dart`,
  `lib/screens/audio_timeline_pro.dart`, and helpers under `lib/helpers/`

## Responsibilities

The engine owns:

- playback transport and real-time routing
- audio recording lifecycle
- clip and track rendering
- mix and track export
- plugin scanning and plugin-host behavior where supported
- MIDI playback support where available
- native device and route behavior
- native logs and event delivery back to Flutter

Flutter owns:

- editor UI and controls
- project state and persistence orchestration
- import/export UX
- user-facing error handling
- deciding when to call engine methods
- saving restored project state after native operations

V3 action-first chat changes do not bypass this boundary. Prepared AI actions
still use the same Flutter-owned transaction, native synchronization, exact
readback, and rollback paths. Slow local rendering or analysis may show
progress, but chat cannot report success until native verification completes.

## Export Path

The public Dart API exposes `exportMix`, `exportTrack`, and export progress
helpers. Export behavior crosses three boundaries:

1. Editor or export UI gathers format and destination choices.
2. Dart calls the engine through `juce_audio_engine.dart`.
3. Native code renders the requested output and reports progress.

Update this page and [Project and file model](project_file_model.md) when export
changes file locations, supported formats, naming, progress semantics, or
failure recovery behavior.

## Platform-Specific Notes

### iOS

iOS selects the prebuilt JUCE archive in
`juce_audio_engine/ios/juce_audio_engine.podspec` through sdk/config-specific
linker flags. Debug device builds use the debug archive, Profile/Release device
builds use the release archive, and simulator builds use the simulator archive.

### Android

Android native code lives under `juce_audio_engine/android`. Keep Android NDK,
ABI, CMake, asset pack, and FFmpeg variant changes coordinated with app-level
build docs.

### Desktop

Desktop behavior can differ for plugin hosting, export, file access, and audio
device routing. See [Known platform issues](known_platform_issues.md) before
changing desktop audio behavior.

## Real-Time Audio Rule

Do not perform blocking file I/O, network calls, allocation-heavy work, or UI
callbacks from a real-time audio path. Route slow work through background
threads and report state back to Flutter through explicit events or polling.
