import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _methodBody(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: signature);
  final afterSignature = start + signature.length;
  final openBrace = source.indexOf('{', afterSignature);
  expect(openBrace, greaterThan(start), reason: signature);
  var depth = 0;
  for (var i = openBrace; i < source.length; i++) {
    final ch = source[i];
    if (ch == '{') depth++;
    if (ch == '}') {
      depth--;
      if (depth == 0) {
        return source.substring(openBrace, i + 1);
      }
    }
  }
  fail('Unclosed method: $signature');
}

void main() {
  late String editor;
  late String juceEngine;

  setUpAll(() {
    editor = File('lib/screens/audio_editor.dart').readAsStringSync();
    juceEngine = File(
      'juce_audio_engine/lib/juce_audio_engine.dart',
    ).readAsStringSync();
  });

  test('engine startup remembers the native diagnostic result', () {
    expect(juceEngine, contains('lastPlaybackStartupResultV2'));
    expect(juceEngine, contains('_rememberPlaybackStartupResultV2('));
    expect(
      juceEngine,
      contains('return _rememberPlaybackStartupResultV2(result);'),
    );
  });

  test('back does not save a project that never loaded', () {
    final body = _methodBody(editor, 'Future<void> _handleBackPressed() async');
    final guard = body.indexOf('if (_loadedOnce)');
    final save = body.indexOf('_saveProject(showSnackBar: false)');
    expect(guard, greaterThanOrEqualTo(0));
    expect(save, greaterThan(guard));
  });

  test('save and autosave refuse to write before the project loaded', () {
    final save = _methodBody(
      editor,
      'Future<void> _saveProject({bool showSnackBar = true}) async',
    );
    expect(save, contains('if (!_loadedOnce)'));
    expect(
      save.indexOf('if (!_loadedOnce)'),
      lessThan(save.indexOf('await _projectAutosaveCoordinator.flush()')),
    );

    final autosave = _methodBody(
      editor,
      'Future<void> _performAutosaveWrite() async',
    );
    expect(autosave, contains('if (!_loadedOnce)'));
    expect(
      autosave.indexOf('if (!_loadedOnce)'),
      lessThan(autosave.indexOf('if (_usingCompatibilityAudio)')),
    );
  });

  test('resumed apps retry start-up when audio failed to start', () {
    final body = _methodBody(
      editor,
      'void didChangeAppLifecycleState(AppLifecycleState state)',
    );
    expect(
      body,
      contains(
        'if (_audioStartupFailed && !_editorStartupInFlight) {\n'
        '          unawaited(_startEditorSession());',
      ),
    );
  });
}
