# Third-Party Notices

Last updated: 2026-04-15

This document tracks third-party software and content used by Mixroom. It is
intended as a central index for license and attribution obligations.

## In-App License View

Mixroom provides an in-app open-source license viewer through Flutter's
`showLicensePage`. This should remain enabled in production builds.

## Primary Components

1. Flutter framework and Dart packages
   - Source: `pubspec.yaml` / `pubspec.lock`
   - License texts: available via in-app open-source license page
2. JUCE and JUCE-related native dependencies used by `juce_audio_engine`
   - Source: `juce_audio_engine/android/src/main/cpp/juce/...`
   - Release requirement: ship only with an active JUCE commercial license
     covering your product/platforms, or comply with the AGPL for the full app
   - Keep the commercial invoice/order record outside the repo with release
     sign-off for each shipped build
3. FFmpeg / ffmpeg-kit
   - Source: `ffmpeg_kit_flutter_new_full` in `pubspec.yaml` and iOS pods
   - Release requirement: archive the upstream license bundle for the exact
     shipped package and verify codec/encoder choices do not introduce GPL or
     patent obligations you are not prepared to satisfy
   - Android note: the unused local `ffmpeg-kit-full-gpl` override was removed
     from this repo on 2026-03-08 and should not be reintroduced casually
4. Third-party instrument references
   - Source: `docs/THIRD_PARTY_INSTRUMENT_CREDITS.md`
   - Current usage is tracked as reference/inspiration unless otherwise noted
5. Basic Pitch audio-to-MIDI model by Spotify
   - Source: https://github.com/spotify/basic-pitch/tree/v0.4.0
   - Local path:
     `assets/models/basic_pitch_nmp.onnx`,
     `assets/licenses/basic_pitch/LICENSE`,
     `assets/licenses/basic_pitch/NOTICE`
   - License: Apache License 2.0
   - Usage: bundled ONNX model for on-device audio-to-MIDI transcription
   - Release requirement: keep the Apache 2.0 license text and upstream
     `NOTICE` bundled with app distributions and surfaced in the in-app license
     view; do not imply Spotify endorsement

## Bundled Audio Assets

1. VSCO 2 Community Edition sample set
   - Source: https://versilian-studios.com/vsco-community/
   - Local path: `assets/instruments/VSCO-2-CE-1.1.0/`
   - License: CC0 1.0 Universal (see bundled `LICENSE`)
   - Usage: bundled SFZ presets + WAV samples

2. Tic Tok Men drum machine sample sets (Moogdrums1, RetroDrums1)
   - Source mirror: https://github.com/sfzinstruments/TicTokMen.Moogdrums1 and
     https://github.com/sfzinstruments/TicTokMen.RetroDrums1
   - Local path:
     `assets/instruments/VSCO-2-CE-1.1.0/Electronic/TicTokMen/`
   - License note: upstream README states source recordings are under "free use
     licenses"; no SPDX license file is included in those mirrors.
   - Release status: treat as blocked for public release until provenance,
     redistribution rights, and required attribution are documented in-repo.
   - Usage: bundled SFZ presets + WAV one-shots for electronic drum kits.

3. Mixroom Starter Kit v1
   - Local path: `assets/sample_packs/starter_kit_v1/`
   - Source record: `assets/sample_packs/starter_kit_v1/LICENSES.md`
   - Declared license basis: curated CC0 / public-domain sample bundle for beta
   - Usage: default bundled sample pack mounted into the in-app File Browser
   - Release requirement: keep exact upstream source URLs and downloaded archive
     records for every included file; remove any file whose redistribution basis
     is not clearly supportable on review

## Release Checklist

1. Re-verify license terms for all shipped dependencies before each release.
2. Confirm in-app license page renders and includes current dependency notices.
3. Confirm JUCE commercial licensing is active for the shipped build, or pause
   release until AGPL obligations are intentionally met.
4. Confirm FFmpeg / ffmpeg-kit notices for the exact shipped binary package are
   stored internally and reflected in public attribution materials if required.
5. Remove or replace any bundled assets whose license provenance is incomplete.
6. If any third-party code/assets are copied into this repository:
   - record source URL and commit hash,
   - include full license text in this repo,
   - include attribution required by the source license.
7. If any third-party model weights are bundled with the app:
   - record the exact upstream tag / commit and source URL,
   - verify redistribution rights for the exact weights you ship,
   - ensure any model-specific LICENSE / NOTICE text is included in the app.
8. Ensure App Store / Play Store disclosures remain consistent with actual app
   behavior and included SDKs.

## Contact

General inquiries: contact@mixroom.ai

Support requests: support@mixroom.ai
