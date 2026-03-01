# Third-Party Notices

Last updated: 2026-02-26

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
   - License files are included in upstream directories where required
3. Third-party instrument references
   - Source: `docs/THIRD_PARTY_INSTRUMENT_CREDITS.md`
   - Current usage is tracked as reference/inspiration unless otherwise noted

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
   - Usage: bundled SFZ presets + WAV one-shots for electronic drum kits.

## Release Checklist

1. Re-verify license terms for all shipped dependencies before each release.
2. Confirm in-app license page renders and includes current dependency notices.
3. If any third-party code/assets are copied into this repository:
   - record source URL and commit hash,
   - include full license text in this repo,
   - include attribution required by the source license.
4. Ensure App Store / Play Store disclosures remain consistent with actual app
   behavior and included SDKs.

## Contact

General inquiries: contact@mixroom.ai

Support requests: support@mixroom.ai
