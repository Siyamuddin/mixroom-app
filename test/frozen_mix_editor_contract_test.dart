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
    // Listen-only never writes: the early return comes before any snapshot
    // is built, so a background flush cannot leak in-memory edits into the
    // prepared projection.
    expect(autosave, isNot(contains('writeCompatibleProjection')));
    expect(
      autosave.indexOf('if (_usingCompatibilityAudio) return;'),
      allOf(
        greaterThanOrEqualTo(0),
        lessThan(autosave.indexOf('_buildProjectJsonSnapshot()')),
      ),
    );
    expect(editor, contains('_scheduleListenOnlyEditAutosave('));
    expect(editor, contains('_listenOnlyInMemoryDirty = true'));
    expect(
      editor,
      contains(
        'if (_usingCompatibilityAudio) {\n      _listenOnlyInMemoryDirty = true;\n      unawaited(_scheduleListenOnlyEditAutosave(',
      ),
    );
    expect(editor, contains('mutationGate'));
    expect(editor, contains('_listenOnlyMutationGate'));
    expect(editor, contains('_confirmFrozenMixCopyForEditsAndReplay()'));
    expect(editor, contains('takePendingGatedActions()'));
    expect(editor, contains('_listenOnlyBaselineUndoDepth'));
    expect(editor, contains('undoSteps(extraSteps)'));

    final execute = _methodBody(
      editor,
      'Future<void> execute(EditorUndoAction action) async',
    );
    expect(
      execute.indexOf('_allowMutation('),
      lessThan(execute.indexOf('await action.redo()')),
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

  test('manual save and back never write a listen-only mix', () {
    final save = _methodBody(
      editor,
      'Future<void> _saveProject({bool showSnackBar = true}) async',
    );
    expect(save, isNot(contains('writeCompatibleProjection')));
    // Dirty listen-only -> ask for a Frozen mix; clean -> just tell the user.
    expect(save, contains('_listenOnlyInMemoryDirty'));
    expect(save, contains('_confirmFrozenMixCopyForEdits()'));
    expect(save, contains('Listen only. Make a Frozen mix to save changes.'));
    expect(
      save.indexOf('if (_usingCompatibilityAudio)'),
      allOf(
        greaterThanOrEqualTo(0),
        lessThan(save.indexOf('_projectAutosaveCoordinator.flush()')),
      ),
    );

    final back = _methodBody(editor, 'Future<void> _handleBackPressed() async');
    expect(
      back,
      contains(
        'if (_usingCompatibilityAudio) {\n'
        '      // Listen-only: nothing is written on the way out.',
      ),
    );
    expect(
      back.indexOf('if (_usingCompatibilityAudio)'),
      lessThan(back.indexOf('_saveProject(showSnackBar: false)')),
    );
  });

  test('frozen mix fork writes a family link and never auto-syncs', () {
    final fork = _methodBody(
      editor,
      'Future<bool> _forkCompatibilityProjectForEdits() async',
    );
    expect(fork, contains('applyFrozenMixFamily('));
    expect(fork, contains('frozenMixDisplayName('));
    // Each new copy gets the next free number in its family before the
    // folder is renamed, so copies never fall back to "#1" collision names.
    expect(fork, contains('_nextFrozenMixIndexForFamily(oldProjectDir)'));
    expect(fork, contains('index: frozenMixIndex'));
    final nextIndex = _methodBody(
      editor,
      'Future<int> _nextFrozenMixIndexForFamily(Directory originalDir) async',
    );
    // Numbering also avoids names used by unrelated projects.
    expect(
      nextIndex,
      contains(
        'allProjectNames: <String>[for (final meta in projects) meta.name]',
      ),
    );
    expect(
      fork.indexOf('_nextFrozenMixIndexForFamily('),
      lessThan(fork.indexOf('duplicateProject(')),
    );
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

  test('a failed frozen mix fork cleans up and drops the queued edits', () {
    final fork = _methodBody(
      editor,
      'Future<bool> _forkCompatibilityProjectForEdits() async',
    );
    // The half-made copy is removed only while the editor still points at
    // the original; once switched, the copy is the live project.
    expect(fork, contains('} catch (e, stack) {'));
    expect(fork, contains('if (!switched && copyDir != null)'));
    expect(fork, contains('copyDir.delete(recursive: true)'));
    expect(
      fork.indexOf('copyDir = duplicated;'),
      allOf(
        greaterThan(fork.indexOf('duplicateProject(')),
        lessThan(fork.indexOf('renameProject(')),
      ),
    );
    expect(
      fork.indexOf('switched = true;'),
      greaterThan(fork.indexOf('_projectDir = forkDir;')),
    );

    final prompt = _methodBody(
      editor,
      'Future<bool> _promptFrozenMixCopyForEdits() async',
    );
    final forkCall = prompt.indexOf(
      'final forked = await _forkCompatibilityProjectForEdits();',
    );
    expect(forkCall, greaterThanOrEqualTo(0));
    expect(
      prompt.indexOf('Could not make a Frozen mix.'),
      greaterThan(forkCall),
    );
    expect(
      prompt.lastIndexOf('_discardListenOnlyEdit()'),
      greaterThan(forkCall),
    );

    // Both unawaited entry points swallow errors and drop the queued actions.
    for (final signature in [
      'Future<void> _confirmFrozenMixCopyForEditsAndReplay() async',
      'Future<void> _scheduleListenOnlyEditAutosave({',
    ]) {
      final body = _methodBody(editor, signature);
      expect(body, contains('} catch (e, stack) {'), reason: signature);
      expect(
        body.lastIndexOf('_undoManager.dropPendingGatedActions()'),
        greaterThan(body.indexOf('} catch (e, stack) {')),
        reason: signature,
      );
    }
  });
}
