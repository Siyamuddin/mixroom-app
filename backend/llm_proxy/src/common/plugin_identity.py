"""Capture/runtime plugin identity parity; matches producer_plugin_identity.dart."""
import hashlib
import re


def canonical_plugin_id(value):
    value = str(value)
    if re.fullmatch(r'plugin_[a-f0-9]{64}', value):
        return value
    path = re.search(r'^(?:file://|/|\\)|[A-Za-z]:[\\/]|/(?:Users|Library|Applications|System|Volumes|private|var|tmp)/', value)
    if path or re.search(r'Bearer\s+\S+', value, re.I):
        return 'plugin_' + hashlib.sha256(value.encode('utf-8')).hexdigest()
    return value
