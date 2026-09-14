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


def model_plugin_id(effect):
    stable = effect.get('modelPluginId', '')
    if isinstance(stable, str) and re.fullmatch(r'plugin_uid_v1_[a-f0-9]{64}', stable):
        return stable
    return canonical_plugin_id(effect.get('effectId', ''))


def supported_descriptor(descriptor, effect, controls):
    """Prefer stable identity; old artifacts may still recognize this exact path.

    Never invent cross-machine aliases for historical captures lacking metadata.
    """
    from .mix_magnitude_contract import fingerprint
    if fingerprint(descriptor) in controls:
        return descriptor
    legacy = dict(descriptor, effect_id=canonical_plugin_id(effect.get('effectId', '')))
    return legacy if fingerprint(legacy) in controls else descriptor
