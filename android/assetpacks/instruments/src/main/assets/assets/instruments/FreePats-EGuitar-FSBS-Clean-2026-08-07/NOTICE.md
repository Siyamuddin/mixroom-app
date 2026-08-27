# Clean Electric Guitar provenance

The product-facing name for this instrument is **Clean Electric Guitar**.

- Source project: FreePats Electric Guitar FSBS Clean
- Upstream: https://github.com/freepats/electric-guitar-FSBS-clean
- Release: `2026-08-07`
- Archive: `EGuitarFSBS-clean-bridge-small-SFZ+FLAC-20260807.7z`
- Archive URL: https://github.com/freepats/electric-guitar-FSBS-clean/releases/download/2026-08-07/EGuitarFSBS-clean-bridge-small-SFZ%2BFLAC-20260807.7z
- Recording: direct-sampled basic-model Fender guitar, clean processed sound
- License: Creative Commons CC0 1.0 Universal

The upstream README applies CC0 to this sound bank, and the release includes
the full CC0 1.0 Universal legal text bundled here as `LICENSE`. Twelve of the
release's thirteen recordings are used; the C2 root is outside the declared
MIDI 40-88 product range.

Source identity:

- Archive SHA-256: `07c8cdf94dc9b4875ff6c43e51440d84f939a45530060c0761093a56d4a1f032`
- Source SFZ SHA-256: `aa74229ecf4a7ea8dc5773bb0a943481e146c767304222d8210a3b5fc368f095`
- Source license SHA-256: `a2010f343487d3f7618affe54f789f5487602331c0a8d03f49e9a7c547cf0499`
- Source README SHA-256: `9d0f723bf48f9e0aae245360aed45eb4328f3f881cd6f34afe4eeabf66f09e43`
- Selected source-audio aggregate SHA-256: `6f8c41fdbdf75c7ea066aa4e26f8f5d552d5a2bcebcad06d687410df79f6781f`
- Validated converted bank aggregate SHA-256: `b26d4adb046f733e562a8caf68d96e2f4b152bf51f03650812c938710a0b84c6`

Mixroom conversion:

- FFmpeg 9.0.1 (Homebrew build 9.0.1_1, libmp3lame)
- Mono MP3, 44.1 kHz, constant 96 kbps
- Conservative bank-wide peak adjustment of -3 dB; no compression
- 20 ms click-safe terminal fade; natural decay retained
- 12 source roots mapped across MIDI 40-88

The converted audio files were copied byte-for-byte from the approved PRO-5
validation bank. The production SFZ changes only its identifying header; its
validated mapping and playback opcodes are unchanged.
