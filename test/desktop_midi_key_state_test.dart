import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/desktop_midi_key_state.dart';

void main() {
  group('desktop MIDI held-key state', () {
    test('initial key-down starts one note', () {
      final heldKeys = <String>{};

      final action = transitionDesktopMidiKey(
        heldKeys: heldKeys,
        key: 'A',
        isKeyDown: true,
        isKeyRepeat: false,
        isKeyUp: false,
        canStartNote: true,
      );

      expect(action, DesktopMidiKeyAction.noteOn);
      expect(heldKeys, {'A'});
    });

    test('duplicate down and repeat do not retrigger a held note', () {
      final heldKeys = <String>{'A'};

      for (final event in <({bool down, bool repeat})>[
        (down: true, repeat: false),
        (down: false, repeat: true),
      ]) {
        expect(
          transitionDesktopMidiKey(
            heldKeys: heldKeys,
            key: 'A',
            isKeyDown: event.down,
            isKeyRepeat: event.repeat,
            isKeyUp: false,
            canStartNote: true,
          ),
          DesktopMidiKeyAction.ignored,
        );
      }

      expect(heldKeys, {'A'});
    });

    test('key-up releases a held note when capture is unavailable', () {
      final heldKeys = <String>{'A'};

      final action = transitionDesktopMidiKey(
        heldKeys: heldKeys,
        key: 'A',
        isKeyDown: false,
        isKeyRepeat: false,
        isKeyUp: true,
        canStartNote: false,
      );

      expect(action, DesktopMidiKeyAction.noteOff);
      expect(heldKeys, isEmpty);
    });

    test('key-up for an unheld note is harmless', () {
      final heldKeys = <String>{};

      final action = transitionDesktopMidiKey(
        heldKeys: heldKeys,
        key: 'A',
        isKeyDown: false,
        isKeyRepeat: false,
        isKeyUp: true,
        canStartNote: false,
      );

      expect(action, DesktopMidiKeyAction.ignored);
      expect(heldKeys, isEmpty);
    });
  });

  group('desktop MIDI editor integration contract', () {
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

    test('tracked key-up is handled before editor-state guards', () {
      final handler = methodBody(
        'bool _handleMacEditorKeyEvent(KeyEvent event)',
        '\n  @override\n  void initState()',
      );

      final keyUpTransition = handler.indexOf(
        'if (isKeyUp && midiPitch != null)',
      );
      final settingsGuard = handler.indexOf(
        'if (_desktopShortcutSettingsOpen)',
      );
      final modifierGuard = handler.indexOf('if (!keyboard.isMetaPressed');

      expect(keyUpTransition, greaterThanOrEqualTo(0));
      expect(settingsGuard, greaterThan(keyUpTransition));
      expect(modifierGuard, greaterThan(keyUpTransition));
    });

    test('recording boundaries flush desktop held notes first', () {
      final start = methodBody(
        'Future<void> _startMidiRecordingTransaction({',
        'Future<void> _stopMidiClipRecording',
      );
      final stop = methodBody(
        'Future<void> _stopMidiClipRecording',
        'Future<void> _startRecordingJuce()',
      );
      final startRelease = start.indexOf(
        'await _releaseAllDesktopMidiNotes();',
      );
      final startTransition = start.indexOf('_clearMidiRecordingRuntimeState');
      final stopRelease = stop.indexOf('await _releaseAllDesktopMidiNotes();');
      final stopTransition = stop.indexOf('_stopRecordingPeakPolling');

      expect(startRelease, greaterThanOrEqualTo(0));
      expect(startTransition, greaterThan(startRelease));
      expect(stopRelease, greaterThanOrEqualTo(0));
      expect(stopTransition, greaterThan(stopRelease));
    });

    test('macOS focus loss flushes desktop held notes', () {
      final lifecycle = methodBody(
        'void didChangeAppLifecycleState(AppLifecycleState state)',
        'bool _isEditorBackgroundState',
      );

      expect(
        lifecycle,
        contains('defaultTargetPlatform == TargetPlatform.macOS'),
      );
      expect(lifecycle, contains('state == AppLifecycleState.inactive'));
      expect(lifecycle, contains('_isEditorBackgroundState(state)'));
      expect(lifecycle, contains('_releaseAllDesktopMidiNotes()'));
    });
  });
}
