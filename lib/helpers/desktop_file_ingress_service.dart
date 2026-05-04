import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

enum DesktopFileDropKind {
  mixroom,
  audio,
  folder,
  unknown,
}

class DesktopFileDropItem {
  const DesktopFileDropItem({
    required this.path,
    required this.kind,
    required this.isDirectory,
  });

  final String path;
  final DesktopFileDropKind kind;
  final bool isDirectory;

  bool get isMixroom => kind == DesktopFileDropKind.mixroom;
  bool get isAudio => kind == DesktopFileDropKind.audio;
  bool get isFolder => kind == DesktopFileDropKind.folder;

  static DesktopFileDropItem? fromMap(Map<dynamic, dynamic> map) {
    final path = (map['path'] as String?)?.trim() ?? '';
    if (path.isEmpty) return null;
    final rawKind = (map['kind'] as String?)?.trim().toLowerCase() ?? '';
    final isDirectory = map['isDirectory'] == true;
    return DesktopFileDropItem(
      path: path,
      kind: switch (rawKind) {
        'mixroom' => DesktopFileDropKind.mixroom,
        'audio' => DesktopFileDropKind.audio,
        'folder' => DesktopFileDropKind.folder,
        _ => DesktopFileDropKind.unknown,
      },
      isDirectory: isDirectory,
    );
  }
}

class DesktopFileIngressService {
  DesktopFileIngressService._();

  static const MethodChannel _channel = MethodChannel('mixroom/finder_drop');
  static final StreamController<List<DesktopFileDropItem>> _controller =
      StreamController<List<DesktopFileDropItem>>.broadcast();
  static final List<List<DesktopFileDropItem>> _pendingBatches =
      <List<DesktopFileDropItem>>[];

  static Stream<List<DesktopFileDropItem>> get stream => _controller.stream;

  static Future<void> init() async {
    if (!Platform.isMacOS) {
      return;
    }

    _channel.setMethodCallHandler((call) async {
      if (call.method != 'deliverFinderDrop') {
        return;
      }
      _publishFromRaw(call.arguments);
    });

    try {
      final raw = await _channel
          .invokeListMethod<dynamic>('getPendingFinderDrops')
          .timeout(const Duration(seconds: 2));
      if (raw == null) return;
      for (final entry in raw) {
        _publishFromRaw(entry);
      }
    } on TimeoutException {
      // Do not block startup on the native side.
    } on MissingPluginException {
      // Desktop channel may not be bound yet during startup.
    } on PlatformException {
      // Ignore transient channel errors.
    }
  }

  static List<List<DesktopFileDropItem>> consumePendingBatches() {
    if (_pendingBatches.isEmpty) {
      return const <List<DesktopFileDropItem>>[];
    }
    final pending = List<List<DesktopFileDropItem>>.from(_pendingBatches);
    _pendingBatches.clear();
    return pending;
  }

  static void _publishFromRaw(dynamic rawPayload) {
    final payload = rawPayload is Map ? rawPayload : const <String, dynamic>{};
    final rawItems = (payload['items'] as List?) ?? const <dynamic>[];
    final items = rawItems
        .whereType<Map>()
        .map(DesktopFileDropItem.fromMap)
        .whereType<DesktopFileDropItem>()
        .toList(growable: false);
    if (items.isEmpty) return;
    if (!_controller.hasListener) {
      _pendingBatches.add(items);
    }
    _controller.add(items);
  }
}
