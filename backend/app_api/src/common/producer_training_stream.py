"""Validate large capture JSON incrementally; keep S3 uploads out of Lambda memory."""

import hashlib
import ijson
from .producer_training_repository import _validate_bundle_privacy, _manifest_checksum


class HashingReader:
    def __init__(self, stream):
        self.stream = stream
        self.digest = hashlib.sha256()
        self.size = 0

    def read(self, size=-1):
        chunk = self.stream.read(size)
        self.digest.update(chunk)
        self.size += len(chunk)
        return chunk


def validate_stream(stream, *, checksum, size, expected, media_manifest):
    reader = HashingReader(stream)
    seen = {}
    manifest = ijson.common.ObjectBuilder()
    manifest_events = 0
    root_seen = False
    try:
        for prefix, event, value in ijson.parse(reader, use_float=True):
            if not root_seen:
                if prefix or event != "start_map":
                    raise ValueError("Capture must be an object.")
                root_seen = True
            if event == "map_key":
                _validate_bundle_privacy(None, key=value)
            elif event == "string":
                _validate_bundle_privacy(value)
            if prefix in expected and event not in ("map_key", "end_map", "end_array"):
                if prefix in seen or event != "string":
                    raise ValueError("Invalid capture identity fields.")
                seen[prefix] = value
            if prefix == "media_manifest" or prefix.startswith("media_manifest."):
                manifest_events += 1
                if manifest_events > 10000:
                    raise ValueError("Media manifest is too large.")
                manifest.event(event, value)
    except ijson.JSONError as exc:
        raise ValueError("Uploaded bundle is not valid JSON.") from exc
    if seen != expected:
        raise ValueError("Uploaded bundle document did not match its reservation.")
    value = getattr(manifest, "value", None)
    if not isinstance(value, list) or _manifest_checksum(value) != _manifest_checksum(
        media_manifest
    ):
        raise ValueError("Uploaded bundle media manifest did not match.")
    if reader.size != size or reader.digest.hexdigest() != checksum:
        raise ValueError("Uploaded bundle content checksum/size did not match.")
