import 'dart:async';
import 'dart:io';
import 'dart:ui' show Offset;

import 'package:flutter/services.dart';

enum DesktopFileDropKind {
  mixroom,
  audio,
  folder,
  unknown,
}

enum DesktopFileDragPhase {
  entered,
  updated,
  exited,
  dropped,
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

class DesktopFileDragEvent {
  const DesktopFileDragEvent({
    required this.phase,
    required this.items,
    this.location,
  });

  final DesktopFileDragPhase phase;
  final List<DesktopFileDropItem> items;
  final Offset? location;

  List<DesktopFileDropItem> get audioItems =>
      items.where((item) => item.isAudio).toList(growable: false);

  bool get hasAudio => items.any((item) => item.isAudio);

  static DesktopFileDragEvent? fromRaw(
    DesktopFileDragPhase phase,
    dynamic rawPayload,
  ) {
    final payload = rawPayload is Map ? rawPayload : const <String, dynamic>{};
    final rawItems = (payload['items'] as List?) ?? const <dynamic>[];
    final items = rawItems
        .whereType<Map>()
        .map(DesktopFileDropItem.fromMap)
        .whereType<DesktopFileDropItem>()
        .toList(growable: false);
    if (phase != DesktopFileDragPhase.exited && items.isEmpty) {
      return null;
    }
    return DesktopFileDragEvent(
      phase: phase,
      items: items,
      location: _locationFromPayload(payload),
    );
  }

  static Offset? _locationFromPayload(Map<dynamic, dynamic> payload) {
    final raw = payload['location'];
    if (raw is! Map) return null;
    final x = _asDouble(raw['x']);
    final y = _asDouble(raw['y']);
    if (x == null || y == null) return null;
    if (!x.isFinite || !y.isFinite) return null;
    return Offset(x, y);
  }

  static double? _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return null;
  }
}

class DesktopFileIngressService {
  DesktopFileIngressService._();

  static const MethodChannel _channel = MethodChannel('mixroom/finder_drop');
  static final StreamController<List<DesktopFileDropItem>> _controller =
      StreamController<List<DesktopFileDropItem>>.broadcast();
  static final StreamController<DesktopFileDragEvent> _dragSessionController =
      StreamController<DesktopFileDragEvent>.broadcast();
  static final List<List<DesktopFileDropItem>> _pendingBatches =
      <List<DesktopFileDropItem>>[];
  static final List<DesktopFileDragEvent> _pendingDragEvents =
      <DesktopFileDragEvent>[];

  static Stream<List<DesktopFileDropItem>> get stream => _controller.stream;

  static Stream<DesktopFileDragEvent> get dragSession =>
      _dragSessionController.stream;

  static Future<void> init() async {
    if (!Platform.isMacOS) {
      return;
    }

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'deliverFinderDrop':
          _publishDropFromRaw(call.arguments);
          return;
        case 'finderDragEntered':
          _publishDragFromRaw(DesktopFileDragPhase.entered, call.arguments);
          return;
        case 'finderDragUpdated':
          _publishDragFromRaw(DesktopFileDragPhase.updated, call.arguments);
          return;
        case 'finderDragExited':
          _publishDragFromRaw(DesktopFileDragPhase.exited, call.arguments);
          return;
        default:
          return;
      }
    });

    try {
      final raw = await _channel
          .invokeListMethod<dynamic>('getPendingFinderDrops')
          .timeout(const Duration(seconds: 2));
      if (raw == null) return;
      for (final entry in raw) {
        _publishDropFromRaw(entry);
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

  static List<DesktopFileDragEvent> consumePendingDragEvents() {
    if (_pendingDragEvents.isEmpty) {
      return const <DesktopFileDragEvent>[];
    }
    final pending = List<DesktopFileDragEvent>.from(_pendingDragEvents);
    _pendingDragEvents.clear();
    return pending;
  }

  static void _publishDropFromRaw(dynamic rawPayload) {
    final dropEvent = DesktopFileDragEvent.fromRaw(
      DesktopFileDragPhase.dropped,
      rawPayload,
    );
    if (dropEvent == null || dropEvent.items.isEmpty) return;

    if (!_controller.hasListener) {
      _pendingBatches.add(dropEvent.items);
    }
    _controller.add(dropEvent.items);

    _publishDragEvent(dropEvent);
  }

  static void _publishDragFromRaw(
    DesktopFileDragPhase phase,
    dynamic rawPayload,
  ) {
    final event = DesktopFileDragEvent.fromRaw(phase, rawPayload);
    if (event == null) return;
    _publishDragEvent(event);
  }

  static void _publishDragEvent(DesktopFileDragEvent event) {
    if (!_dragSessionController.hasListener) {
      // Only queue terminal drops. Hover events are ephemeral.
      if (event.phase == DesktopFileDragPhase.dropped) {
        _pendingDragEvents.add(event);
      }
    }
    _dragSessionController.add(event);
  }
}
