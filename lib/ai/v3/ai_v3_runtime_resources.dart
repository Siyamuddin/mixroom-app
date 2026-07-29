import 'dart:io';

import 'ai_v3_resources.dart';

class AiV3RuntimeResourceBinding {
  const AiV3RuntimeResourceBinding({
    required this.kind,
    required this.stableId,
  });

  final AiV3ResourceKind kind;
  final Object stableId;
}

class AiV3WorkflowRuntime {
  final Map<String, AiV3RuntimeResourceBinding> _bindings =
      <String, AiV3RuntimeResourceBinding>{};
  final Set<String> _generatedArtifactPaths = <String>{};

  String _key(AiV3ResourceRef ref) => '${ref.commandId}.${ref.output}';

  void bind({
    required AiV3ResourceRef ref,
    required AiV3ResourceKind kind,
    required Object stableId,
  }) {
    final validId = switch (kind) {
      AiV3ResourceKind.audioClip ||
      AiV3ResourceKind.midiClip =>
        stableId is String && stableId.trim().isNotEmpty,
      AiV3ResourceKind.audioRow ||
      AiV3ResourceKind.midiRow =>
        stableId is int && stableId >= 0,
    };
    final key = _key(ref);
    if (!validId || _bindings.containsKey(key)) {
      throw StateError('v3_resource_binding_invalid');
    }
    _bindings[key] = AiV3RuntimeResourceBinding(kind: kind, stableId: stableId);
  }

  AiV3RuntimeResourceBinding resolve(
    AiV3ResourceRef ref, {
    required AiV3ResourceKind expectedKind,
  }) {
    final binding = _bindings[_key(ref)];
    if (binding == null) {
      throw StateError('v3_resource_binding_missing');
    }
    if (binding.kind != expectedKind) {
      throw StateError('v3_resource_binding_type_mismatch');
    }
    return binding;
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
