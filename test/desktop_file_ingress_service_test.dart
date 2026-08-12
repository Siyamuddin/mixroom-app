import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/desktop_file_ingress_service.dart';

void main() {
  group('DesktopFileDropItem.fromMap', () {
    test('parses audio items', () {
      final item = DesktopFileDropItem.fromMap({
        'path': '/tmp/kick.wav',
        'kind': 'audio',
        'isDirectory': false,
      });
      expect(item, isNotNull);
      expect(item!.path, '/tmp/kick.wav');
      expect(item.isAudio, isTrue);
      expect(item.isDirectory, isFalse);
    });

    test('parses mixroom and folder kinds', () {
      final mixroom = DesktopFileDropItem.fromMap({
        'path': '/tmp/song.mixroom',
        'kind': 'mixroom',
        'isDirectory': false,
      });
      final folder = DesktopFileDropItem.fromMap({
        'path': '/tmp/samples',
        'kind': 'folder',
        'isDirectory': true,
      });
      expect(mixroom!.isMixroom, isTrue);
      expect(folder!.isFolder, isTrue);
      expect(folder.isDirectory, isTrue);
    });

    test('returns null for empty path', () {
      expect(
        DesktopFileDropItem.fromMap({
          'path': '   ',
          'kind': 'audio',
          'isDirectory': false,
        }),
        isNull,
      );
    });
  });

  group('DesktopFileDragEvent.fromRaw', () {
    test('parses dropped payload with location', () {
      final event = DesktopFileDragEvent.fromRaw(
        DesktopFileDragPhase.dropped,
        {
          'source': 'finder',
          'items': [
            {
              'path': '/tmp/snare.mp3',
              'kind': 'audio',
              'isDirectory': false,
            },
          ],
          'location': {'x': 120.5, 'y': 340},
        },
      );
      expect(event, isNotNull);
      expect(event!.phase, DesktopFileDragPhase.dropped);
      expect(event.hasAudio, isTrue);
      expect(event.audioItems.single.path, '/tmp/snare.mp3');
      expect(event.location, const Offset(120.5, 340));
    });

    test('allows exited events with empty items', () {
      final event = DesktopFileDragEvent.fromRaw(
        DesktopFileDragPhase.exited,
        {'source': 'finder'},
      );
      expect(event, isNotNull);
      expect(event!.phase, DesktopFileDragPhase.exited);
      expect(event.items, isEmpty);
      expect(event.location, isNull);
    });

    test('rejects non-exit events with empty items', () {
      final event = DesktopFileDragEvent.fromRaw(
        DesktopFileDragPhase.updated,
        {
          'source': 'finder',
          'items': const <dynamic>[],
          'location': {'x': 1, 'y': 2},
        },
      );
      expect(event, isNull);
    });

    test('ignores non-finite location values', () {
      final event = DesktopFileDragEvent.fromRaw(
        DesktopFileDragPhase.updated,
        {
          'items': [
            {
              'path': '/tmp/hat.wav',
              'kind': 'audio',
              'isDirectory': false,
            },
          ],
          'location': {'x': double.nan, 'y': 10},
        },
      );
      expect(event, isNotNull);
      expect(event!.location, isNull);
    });
  });
}
