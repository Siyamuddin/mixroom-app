#!/usr/bin/env python3
"""Generate lightweight, audio-backed timeline previews for bundled demos."""

import array
import json
import math
import subprocess
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEMO_DIR = ROOT / "assets" / "demo_projects"
PEAK_COUNT = 96


def waveform_peaks(audio_bytes: bytes) -> list[float]:
    decoded = subprocess.run(
        [
            "ffmpeg",
            "-v",
            "error",
            "-i",
            "pipe:0",
            "-ac",
            "1",
            "-ar",
            "800",
            "-f",
            "f32le",
            "pipe:1",
        ],
        input=audio_bytes,
        stdout=subprocess.PIPE,
        check=True,
    ).stdout
    samples = array.array("f")
    samples.frombytes(decoded)
    if not samples:
        return []
    bucket_size = max(1, math.ceil(len(samples) / PEAK_COUNT))
    peaks = [
        max(abs(sample) for sample in samples[start : start + bucket_size])
        for start in range(0, len(samples), bucket_size)
    ][:PEAK_COUNT]
    ceiling = max(peaks, default=1.0)
    if ceiling <= 0:
        return [0.0 for _ in peaks]
    return [round(math.sqrt(peak / ceiling), 3) for peak in peaks]


def generate_preview(bundle_path: Path) -> None:
    with zipfile.ZipFile(bundle_path) as bundle:
        project = json.loads(bundle.read("project.json"))
        rows = [
            {
                "rowId": row.get("rowId", 0),
                "name": row.get("name", ""),
                "iconId": row.get("iconId", 0),
                "kind": row.get("kind", "audio"),
                "color": row.get("color", 0),
            }
            for row in project.get("rows", [])
        ]
        tracks = []
        for track in project.get("tracks", []):
            file_name = track.get("fileName", "")
            audio_path = f"audio/{file_name}"
            peaks = waveform_peaks(bundle.read(audio_path)) if file_name else []
            tracks.append(
                {
                    "label": track.get("label", ""),
                    "rowId": track.get("rowId", 0),
                    "rowIndex": track.get("rowIndex", 0),
                    "offset": track.get("offset", 0.0),
                    "trimStartMs": track.get("trimStartMs", 0),
                    "trimEndMs": track.get("trimEndMs", 0),
                    "waveformPeaks": peaks,
                }
            )
    preview = {
        "name": project.get("name", bundle_path.stem),
        "tempoBpm": project.get("tempoBpm", 120.0),
        "rows": rows,
        "tracks": tracks,
    }
    output_path = bundle_path.with_name(f"{bundle_path.name}.preview.json")
    output_path.write_text(
        json.dumps(preview, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    for bundle_path in sorted(DEMO_DIR.glob("*.mixroom")):
        generate_preview(bundle_path)


if __name__ == "__main__":
    main()
