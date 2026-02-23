# Third-Party Instrument Credits

This document tracks third-party JUCE instrument projects referenced by Mixroom's instrument catalog.

## Current integration scope (as of 2026-02-20)

- Mixroom currently uses internal/native rendering code plus preset mappings.
- The third-party projects below are used as reference/inspiration for instrument presets and naming.
- If any third-party source code or assets are copied into this repository in the future, add:
  - the exact commit hash used,
  - full license text in a `licenses/` folder,
  - attribution notices required by that license.

## Referenced projects

| Mixroom Instrument ID | Source Project | Repository | License (upstream) | Notes |
| --- | --- | --- | --- | --- |
| `mixroom.figbug_wavetable` | FigBug/Wavetable | https://github.com/FigBug/Wavetable | BSD-3-Clause | Preset inspiration/reference. |
| `mixroom.sarah_harmonic` | getdunne/SARAH | https://github.com/getdunne/SARAH | MIT | Preset inspiration/reference. |
| `mixroom.vanilla_poly` | getdunne/VanillaJuce | https://github.com/getdunne/VanillaJuce | MIT | Preset inspiration/reference. |
| `mixroom.duck_synth` | jsvaldezv/duck-synth | https://github.com/jsvaldezv/duck-synth | MIT | Preset inspiration/reference. |
| `mixroom.chow_kick` | jatinchowdhury18/ChowKick | https://github.com/jatinchowdhury18/ChowKick | BSD-3-Clause | Drum preset inspiration/reference. |
| (planned/reference) | jcurtis4207/Juce-Plugins | https://github.com/jcurtis4207/Juce-Plugins | See upstream license | Track here if any instrument code/assets are integrated. |

## Additional index used during discovery

- awesome-juce list: https://github.com/sudara/awesome-juce

## Maintenance checklist before release

1. Re-verify each referenced project's license on its upstream repository.
2. Confirm whether usage is reference-only or includes copied code/assets.
3. If code/assets were copied, add full attribution + license text in-app and in-repo.
4. Keep this file synced with `kInstrumentCatalog` in `lib/screens/audio_editor.dart`.
