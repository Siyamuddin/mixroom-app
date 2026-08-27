# Steel Acoustic Guitar provenance

The product-facing name for this instrument is **Steel Acoustic Guitar**.

- Source project: Discord SFZ GM Bank
- Upstream: https://github.com/sfzinstruments/Discord-SFZ-GM-Bank
- Pinned commit: `05d5ed8befa042fd9d99a6d159dfc3673d3f8edc`
- Source preset: `Discord GM/Melodic/026-Acoustic Guitar (steel)/_MartinGM2-loop-sw.sfz`
- Instrument: 2017 Martin HD-28 Vintage Series
- Recorder and contributor: Jeff Learman
- License: Creative Commons CC0 1.0 Universal

The upstream preset header identifies Jeff Learman, the instrument, upstream
bank, and CC0 license. The 15 selected recordings are exactly the recordings
referenced by that preset. The bundled `LICENSE` contains the CC0 1.0
Universal legal text.

Source identity:

- Source preset SHA-256: `8249f6e49a45943211b2191a705821dd3f1c7ed1cbdd0b98719b68458dd05ca5`
- Selected source-directory aggregate SHA-256: `7e37b5f405003ca86e582b57b59fb88d686fbd55aab7681b7180a7737ffb0af1`
- Validated converted bank aggregate SHA-256: `72916862f683318cc73afb353e9f2ab96b3ede485d78931eb94d8ef505db1ca1`

Mixroom conversion:

- FFmpeg 9.0.1 (Homebrew build 9.0.1_1, libmp3lame)
- Mono MP3, 44.1 kHz, constant 96 kbps
- Conservative bank-wide peak adjustment of -2 dB; no compression
- 20 ms click-safe terminal fade; natural decay retained
- 15 source roots mapped across MIDI 40-84

The converted audio files were copied byte-for-byte from the approved PRO-5
validation bank. The production SFZ changes only its identifying header; its
validated mapping and playback opcodes are unchanged.
