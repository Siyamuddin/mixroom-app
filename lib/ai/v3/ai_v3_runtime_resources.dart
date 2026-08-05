import 'dart:io';

import 'ai_v3_resources.dart';

class AiV3RuntimeResourceBinding {
  const AiV3RuntimeResourceBinding({
    required this.kind,
    required this.stableId,
    this.parentRowKey,
  });

  final AiV3ResourceKind kind;
  final Object stableId;
  final String? parentRowKey;
}

class AiV3WorkflowRuntime {
  final Map<String, AiV3RuntimeResourceBinding> _bindings =
      <String, AiV3RuntimeResourceBinding>{};
  final Set<String> _retiredBindings = <String>{};
  final Set<String> _generatedArtifactPaths = <String>{};

  String _key(AiV3ResourceRef ref) => '${ref.commandId}.${ref.output}';

  void bind({
    required AiV3ResourceRef ref,
    required AiV3ResourceKind kind,
    required Object stableId,
    AiV3ResourceRef? parentRowRef,
    String? parentRowKey,
  }) {
    final validId = switch (kind) {
      AiV3ResourceKind.audioClip || AiV3ResourceKind.midiClip =>
        stableId is String && stableId.trim().isNotEmpty,
      AiV3ResourceKind.audioRow ||
      AiV3ResourceKind.midiRow => stableId is int && stableId >= 0,
      AiV3ResourceKind.group =>
        stableId is String && stableId.trim().isNotEmpty,
    };
    final key = _key(ref);
    if (!validId ||
        _bindings.containsKey(key) ||
        _retiredBindings.contains(key)) {
      throw StateError('v3_resource_binding_invalid');
    }
    _bindings[key] = AiV3RuntimeResourceBinding(
      kind: kind,
      stableId: stableId,
      parentRowKey:
          parentRowKey ?? (parentRowRef == null ? null : _key(parentRowRef)),
    );
  }

  AiV3RuntimeResourceBinding resolve(
    AiV3ResourceRef ref, {
    required AiV3ResourceKind expectedKind,
  }) => resolveAccepted(ref, acceptedKinds: <AiV3ResourceKind>{expectedKind});

  AiV3RuntimeResourceBinding resolveAccepted(
    AiV3ResourceRef ref, {
    required Set<AiV3ResourceKind> acceptedKinds,
  }) {
    final key = _key(ref);
    if (_retiredBindings.contains(key)) {
      throw StateError('v3_resource_binding_unavailable');
    }
    final binding = _bindings[key];
    if (binding == null) {
      throw StateError('v3_resource_binding_missing');
    }
    if (!acceptedKinds.contains(binding.kind)) {
      throw StateError('v3_resource_binding_type_mismatch');
    }
    return binding;
  }

  void retire(AiV3ResourceRef ref) {
    final key = _key(ref);
    if (!_bindings.containsKey(key) || !_retiredBindings.add(key)) {
      throw StateError('v3_resource_binding_unavailable');
    }
  }

  void retireRowAndChildren(AiV3ResourceRef ref) {
    final key = _key(ref);
    final binding = _bindings[key];
    if (binding == null ||
        (binding.kind != AiV3ResourceKind.audioRow &&
            binding.kind != AiV3ResourceKind.midiRow) ||
        !_retiredBindings.add(key)) {
      throw StateError('v3_resource_binding_unavailable');
    }
    for (final entry in _bindings.entries) {
      if (entry.value.parentRowKey == key) {
        _retiredBindings.add(entry.key);
      }
    }
  }

  void retireStableIds(Iterable<Object> stableIds) {
    final retiredIds = stableIds.toSet();
    for (final entry in _bindings.entries) {
      if (retiredIds.contains(entry.value.stableId)) {
        _retiredBindings.add(entry.key);
      }
    }
  }

  void trackGeneratedArtifact(String path) {
    final normalized = path.trim();
    if (normalized.isNotEmpty) _generatedArtifactPaths.add(normalized);
  }

  Future<bool> deleteGeneratedArtifacts() async {
    var complete = true;
    for (final path in _generatedArtifactPaths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        complete = false;
      }
    }
    return complete;
  }
}
