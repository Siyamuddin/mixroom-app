"""Bounded MIDI duration normalization; mirrored by the Dart helper."""
import math

POLICY = "extend_1ms_v1"


def extended_length(original: float, current: float, end: float, bpm: float) -> float:
    if any(not math.isfinite(v) or v <= 0 for v in (original, current, end, bpm)):
        return current
    if end <= current:
        return current
    scale = 60_000_000.0 / bpm
    values = [original * scale, current * scale, end * scale]
    # Keep integer conversion identical on native Dart and Python.
    if any(not math.isfinite(v) or v > 2**53 - 1 for v in values):
        return current
    baseline = math.floor(values[0] + 0.5)
    required = math.ceil(values[2])
    if required - baseline > 1000:
        return current
    return max(current, required / scale)
