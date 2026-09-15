import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _methodBody(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: signature);
  final openBrace = source.indexOf('{', start + signature.length);
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
  late String projectManager;

  setUpAll(() {
    editor = File('lib/screens/audio_editor.dart').readAsStringSync();
    projectManager = File(
      'lib/helpers/project_manager.dart',
    ).readAsStringSync();
  });

  test('plugin-less hosts do not open raw plugin source as the timeline', () {
    final load = _methodBody(editor, 'Future<void> _loadProjectIfAny() async');
    expect(load, contains('isPlayableOnThisDevice('));
    expect(load, contains('_queuePluginMixUnavailableNotice()'));
    expect(load, contains('_loadedOnce = false'));
    expect(load, contains('_pluginMixOpenBlocked = true'));
    expect(load, contains('pluginCatalogReady:'));
    expect(load, contains('_scanDesktopPlugins()'));
    expect(
      load.indexOf('isPlayableOnThisDevice('),
      lessThan(load.indexOf('_restoreChatHistoryFromProjectJson(json)')),
    );
  });

  test('autosave does not silently fork a listen-only mix', () {
    final autosave = _methodBody(
      editor,
      'Future<void> _performAutosaveWrite() async',
    );
    expect(autosave, isNot(contains('_forkCompatibilityProjectForEdits')));
    expect(autosave, contains('if (!_usingCompatibilityAudio)'));
    expect(editor, contains('_scheduleListenOnlyEditAutosave('));
    expect(
      editor,
      contains(
        'if (_usingCompatibilityAudio) {\n      unawaited(_scheduleListenOnlyEditAutosave(',
      ),
    );

    final prompt = _methodBody(
      editor,
      'Future<bool> _promptFrozenMixCopyForEdits() async',
    );
    expect(prompt, contains('Make a frozen mix?'));
    expect(
      prompt,
      contains(
        "This mix uses plugins that are not available here, so this device can't change those tracks. Make a frozen mix? This won't change the original.",
      ),
    );
    expect(prompt, contains('_discardListenOnlyEdit()'));
    expect(prompt, contains('_canCreateFrozenMixCopy()'));
    expect(prompt, contains('_forkCompatibilityProjectForEdits()'));
  });

  test('frozen mix fork writes a family link and never auto-syncs', () {
    final fork = _methodBody(
      editor,
      'Future<void> _forkCompatibilityProjectForEdits() async',
    );
    expect(fork, contains('applyFrozenMixFamily('));
    expect(fork, contains('frozenMixDisplayName('));
    expect(fork, contains('ProjectManager.mixKindFrozen'));
    expect(fork, contains('stripCloudSyncMetadata('));
    expect(
      fork,
      isNot(
        contains('renameProject(\n        duplicated,\n        _projectName,'),
      ),
    );

    final canSync = _methodBody(editor, 'bool _canAttemptAutoCloudSync()');
    expect(canSync, contains('mixKindFrozen'));
    expect(canSync, contains('_sourceRequiresUnhostedPlugins'));
    expect(canSync, contains('_usingCompatibilityAudio'));

    expect(projectManager, contains('stripFamilyMetadata(duplicateJson)'));
    expect(
      projectManager.indexOf('static Future<Directory> duplicateProject('),
      lessThan(projectManager.indexOf('stripFamilyMetadata(duplicateJson)')),
    );
  });
}
