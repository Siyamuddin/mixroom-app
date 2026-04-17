Place bundled sample packs under this directory.

Recommended structure:

- `assets/sample_packs/starter_kit_v1/...audio files...`
- `assets/sample_packs/starter_kit_v1/pack.json`
- `assets/sample_packs/starter_kit_v1/LICENSES.md`

Notes:

- The audio editor auto-discovers each first-level folder under
  `assets/sample_packs/`, extracts it into app-private
  `Application Support/sample_packs/<Display Name>/`, and mounts it as a
  default File Browser root.
- Flutter does not reliably bundle nested sample-pack audio from only the top
  `assets/sample_packs/` entry. Add each shipped audio subfolder explicitly in
  `pubspec.yaml`.
- Version each shipped pack by folder name. Example: `starter_kit_v1`,
  `starter_kit_v2`.
- Keep a per-pack `pack.json` with metadata such as `name`, `version`, and
  `license`.
- Keep a per-pack `LICENSES.md` or similar file with the exact source URLs and
  license text/notes for every bundled sample.
