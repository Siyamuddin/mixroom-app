import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('desktop bar navigation shortcut contract', () {
    late String editor;

    setUpAll(() {
      editor = File('lib/screens/audio_editor.dart').readAsStringSync();
    });

    String methodBody(String start, String end) {
      final startIndex = editor.indexOf(start);
      final endIndex = editor.indexOf(end, startIndex);
      expect(startIndex, greaterThanOrEqualTo(0));
      expect(endIndex, greaterThan(startIndex));
      return editor.substring(startIndex, endIndex);
    }

    test('handler matches bar seek and view pan shortcut ids', () {
      final handler = methodBody(
        'bool _handleMacEditorKeyEvent(KeyEvent event)',
        '\n  @override\n  void initState()',
      );
      expect(handler.contains('_kDesktopShortcutSeekBarLeft'), isTrue);
      expect(handler.contains('_kDesktopShortcutSeekBarRight'), isTrue);
      expect(handler.contains('_kDesktopShortcutScrollTimelineLeft'), isTrue);
      expect(handler.contains('_kDesktopShortcutScrollTimelineRight'), isTrue);
      expect(handler.contains('isKeyRepeat'), isTrue);
      expect(handler.contains('_canHandleTimelineViewPanShortcut()'), isTrue);
    });

    test('shortcut list and defaults include bar seek and view pan', () {
      expect(editor.contains("'seek_bar_left'"), isTrue);
      expect(editor.contains("'seek_bar_right'"), isTrue);
      expect(editor.contains("'scroll_timeline_left'"), isTrue);
      expect(editor.contains("'scroll_timeline_right'"), isTrue);
      expect(editor.contains('LogicalKeyboardKey.comma.keyId'), isTrue);
      expect(editor.contains('LogicalKeyboardKey.period.keyId'), isTrue);
      expect(editor.contains('LogicalKeyboardKey.arrowLeft.keyId'), isTrue);
      expect(editor.contains('LogicalKeyboardKey.arrowRight.keyId'), isTrue);
      expect(editor.contains("'Seek Left 1 Bar'"), isTrue);
      expect(editor.contains("'Scroll Timeline Left'"), isTrue);
    });
  });
}
