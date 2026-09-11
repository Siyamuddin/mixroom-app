import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/screens/audio_editor.dart';
import 'package:mixroom/screens/audio_timeline_pro.dart';

void main() {
  group('large project loading safety', () {
    test('editor initialization always clears the loading overlay', () {
      final source = File('lib/screens/audio_editor.dart').readAsStringSync();
      final initializationStart = source.indexOf(
        'WidgetsBinding.instance.addPostFrameCallback((_) async {\n      try {',
      );
      final nextMethod = source.indexOf(
        '\n  Future<void> _runInitialActionIfNeeded()',
        initializationStart,
      );

      expect(initializationStart, greaterThanOrEqualTo(0));
      expect(nextMethod, greaterThan(initializationStart));
      final initialization = source.substring(initializationStart, nextMethod);
      expect(initialization, contains('} catch (error, stackTrace) {'));
      expect(initialization, contains('FlutterError.reportError('));
      expect(initialization, contains('} finally {'));
      expect(
        initialization,
        contains(
          'if (mounted && _isLoadingNextScreen) {\n'
          '          setState(() => _isLoadingNextScreen = false);',
        ),
      );
    });

    test('the complete project restores in one fail-closed transaction', () {
      final source = File('lib/screens/audio_editor.dart').readAsStringSync();
      final loadStart = source.indexOf('Future<void> _loadProjectIfAny()');
      final loadEnd = source.indexOf(
        '\n  void _queueCompatibilityAudioOpenNotice()',
        loadStart,
      );

      expect(loadStart, greaterThanOrEqualTo(0));
      expect(loadEnd, greaterThan(loadStart));
      final load = source.substring(loadStart, loadEnd);
      final begin = load.indexOf(
        'await JuceAudioEngine.beginProjectClipLoad();',
      );
      final restoreRows = load.indexOf(
        'await _restoreRowsFromProjectJson(rowsJson, tracks);',
      );
      final restoreClips = load.indexOf(
        'for (int trackIndex = 0; trackIndex < tracks.length; trackIndex++)',
      );
      final restoreRowState = load.indexOf('for (final rs in rowStatesList)');
      final restoreEffects = load.indexOf(
        'final effectsRestore = Stopwatch()..start();',
      );
      final restoreHostedInstruments = load.indexOf(
        'await _restoreDeferredHostedInstrumentLoadsDuringProjectLoad();',
      );
      final syncAutomation = load.indexOf(
        'await _syncNativeAutomationForAllRows();',
      );
      final detailedEnd = load.indexOf(
        'await JuceAudioEngine.endProjectClipLoadDetailed();',
      );
      final primeTransport = load.indexOf(
        'await JuceAudioEngine.setTransportSeconds(0.001);',
      );

      expect(begin, greaterThanOrEqualTo(0));
      expect(restoreRows, greaterThan(begin));
      expect(restoreClips, greaterThan(restoreRows));
      expect(restoreRowState, greaterThan(restoreClips));
      expect(restoreEffects, greaterThan(restoreRowState));
      expect(restoreHostedInstruments, greaterThan(restoreEffects));
      expect(syncAutomation, greaterThan(restoreHostedInstruments));
      expect(detailedEnd, greaterThan(syncAutomation));
      expect(primeTransport, greaterThan(detailedEnd));
      expect(
        RegExp('beginProjectClipLoad\\(\\)').allMatches(load),
        hasLength(1),
      );
      expect(
        RegExp('endProjectClipLoadDetailed\\(\\)').allMatches(load),
        hasLength(1),
      );
      expect(load, isNot(contains('JuceAudioEngine.endProjectClipLoad();')));
      expect(load, contains('if (!nativeLoadFinalization.succeeded)'));
      expect(load, contains('_rollbackFailedProjectClipPublication('));
      expect(load, contains('Error.throwWithStackTrace('));
      expect(load, contains('[ProjectLoadSummary]'));
      expect(load, contains('rowRestoreMs='));
      expect(load, contains('clipAdmissionMs='));
      expect(load, contains('nativeFinalizeMs='));
      expect(load, contains('deferredSyncMs='));
      expect(load, contains('effectsRestoreMs='));
      expect(load, contains('nativeTransactions='));
      expect(load, contains('nativeDetailedFinalizations='));
    });

    test('publication failure restores the pre-load graph or closes it', () {
      final source = File('lib/screens/audio_editor.dart').readAsStringSync();
      final rollbackStart = source.indexOf(
        'Future<void> _rollbackFailedProjectClipPublication(',
      );
      final rollbackEnd = source.indexOf(
        '\n  Future<Map<String, dynamic>> _buildProjectJsonSnapshot()',
        rollbackStart,
      );

      expect(rollbackStart, greaterThanOrEqualTo(0));
      expect(rollbackEnd, greaterThan(rollbackStart));
      final rollback = source.substring(rollbackStart, rollbackEnd);
      expect(rollback, contains('await _requireNativeClipRemoval('));
      expect(rollback, contains('snapshot.layout.trackGroups'));
      expect(rollback, contains('await _restoreRowsFromProjectJson('));
      expect(rollback, contains('_restoreProjectLoadRowUi('));
      expect(rollback, contains('await _restoreRowSnapshot('));
      expect(rollback, contains('await _restoreMasterSnapshot('));
      expect(rollback, contains('await _syncNativeAutomationForAllRows();'));
      expect(
        RegExp('beginProjectClipLoad\\(\\)').allMatches(rollback),
        hasLength(1),
      );
      expect(
        RegExp('endProjectClipLoadDetailed\\(\\)').allMatches(rollback),
        hasLength(1),
      );
      expect(rollback, contains('await _shutdownAudioEngineV2Aware();'));
      expect(source, contains('_projectLoadPublicationFailedClosed = true;'));
      expect(
        source,
        contains(
          'This project could not be opened safely. Reopen it to try again.',
        ),
      );
    });

    test('clip IDs are released only after confirmed native removal', () {
      final source = File('lib/screens/audio_editor.dart').readAsStringSync();

      expect(source, contains('Future<void> _requireNativeClipRemoval('));
      expect(source, contains('unloadClipsDetailed(ids)'));
      expect(source, contains('_unrecyclableEngineClipIds'));
      expect(
        source,
        contains('_unrecyclableEngineClipIds.contains(_nextEngineClipId)'),
      );

      final deleteStart = source.indexOf('class DeleteClipAction');
      final deleteEnd = source.indexOf('class DeleteClipsAction', deleteStart);
      expect(deleteStart, greaterThanOrEqualTo(0));
      expect(deleteEnd, greaterThan(deleteStart));
      final deleteAction = source.substring(deleteStart, deleteEnd);
      expect(
        deleteAction.indexOf('await _requireNativeClipRemoval('),
        lessThan(deleteAction.indexOf('tracks.removeAt(idx);')),
      );
    });

    test(
      'entity load traces are debug-only and transport starts are guarded',
      () {
        final source = File('lib/screens/audio_editor.dart').readAsStringSync();

        expect(source, contains('void _projectLoadTrace(String message)'));
        expect(
          source,
          contains(
            'assert(() {\n'
            "      if (const bool.fromEnvironment('MIXROOM_PROJECT_LOAD_VERBOSE')) {\n"
            '        debugPrint(message);\n'
            '      }\n'
            '      return true;\n'
            '    }());',
          ),
        );
        expect(
          RegExp(r'debugPrint\([\s\S]{0,120}\[ProjectLoad\]').hasMatch(source),
          isFalse,
        );
        expect(
          source,
          contains('logger: _isProjectLoading ? _projectLoadTrace : null'),
        );
        expect(
          source,
          contains(
            '_restoreRowSnapshot(\n'
            '            resolvedSnapshot,\n'
            '            logger: _projectLoadTrace,',
          ),
        );
        expect(
          source,
          contains(
            '_restoreMasterSnapshot(\n'
            '              ms,\n'
            '              logger: _projectLoadTrace,',
          ),
        );
        expect(
          source,
          contains('bool _rejectTransportStartWhileProjectLoading()'),
        );
        expect(
          source,
          contains(
            'if (targetPlaying && _rejectTransportStartWhileProjectLoading())',
          ),
        );
        expect(
          source,
          contains(
            'if (_isPlaying == willPlay) {\n'
            '          _insertSystemChatText(',
          ),
        );
      },
    );
  });

  group('clip inspector target policy', () {
    test('an inactive inspector stays closed', () {
      expect(
        audioEditorClipInspectorTargetAfterSelection(
          currentTargetId: null,
          currentTargetExists: false,
          primarySelectedClipId: 'clip-b',
          origin: TimelineSelectionChangeOrigin.interaction,
        ),
        isNull,
      );
    });

    test('an open inspector follows the primary selection', () {
      expect(
        audioEditorClipInspectorTargetAfterSelection(
          currentTargetId: 'clip-a',
          currentTargetExists: true,
          primarySelectedClipId: 'clip-b',
          origin: TimelineSelectionChangeOrigin.interaction,
        ),
        'clip-b',
      );
    });

    test('empty selection retains the current target', () {
      expect(
        audioEditorClipInspectorTargetAfterSelection(
          currentTargetId: 'clip-a',
          currentTargetExists: true,
          primarySelectedClipId: null,
          origin: TimelineSelectionChangeOrigin.interaction,
        ),
        'clip-a',
      );
    });

    test('reconciliation preserves a surviving stable target', () {
      expect(
        audioEditorClipInspectorTargetAfterSelection(
          currentTargetId: 'clip-a',
          currentTargetExists: true,
          primarySelectedClipId: 'stale-index-clip',
          origin: TimelineSelectionChangeOrigin.reconciliation,
        ),
        'clip-a',
      );
    });

    test('reconciliation closes an inspector whose target disappeared', () {
      expect(
        audioEditorClipInspectorTargetAfterSelection(
          currentTargetId: 'clip-a',
          currentTargetExists: false,
          primarySelectedClipId: null,
          origin: TimelineSelectionChangeOrigin.reconciliation,
        ),
        isNull,
      );
    });

    test('a replacement primary wins when the old target disappeared', () {
      expect(
        audioEditorClipInspectorTargetAfterSelection(
          currentTargetId: 'clip-a',
          currentTargetExists: false,
          primarySelectedClipId: 'clip-b',
          origin: TimelineSelectionChangeOrigin.reconciliation,
        ),
        'clip-b',
      );
    });

    test('interaction follows selection regardless of prior topology', () {
      expect(
        audioEditorClipInspectorTargetAfterSelection(
          currentTargetId: 'clip-a',
          currentTargetExists: true,
          primarySelectedClipId: 'clip-b',
          origin: TimelineSelectionChangeOrigin.interaction,
        ),
        'clip-b',
      );
    });

    test('stale missing-target cleanup cannot close a new target', () {
      expect(
        audioEditorShouldApplyScheduledMissingClipResolution(
          expectedMissingClipId: 'clip-a',
          currentTargetId: 'clip-b',
          expectedTargetExists: false,
        ),
        isFalse,
      );
      expect(
        audioEditorShouldApplyScheduledMissingClipResolution(
          expectedMissingClipId: 'clip-a',
          currentTargetId: 'clip-a',
          expectedTargetExists: false,
        ),
        isTrue,
      );
      expect(
        audioEditorShouldApplyScheduledMissingClipResolution(
          expectedMissingClipId: 'clip-a',
          currentTargetId: 'clip-a',
          expectedTargetExists: true,
        ),
        isFalse,
      );
    });

    test('rename drafts commit only meaningful normalized changes', () {
      expect(
        audioEditorNormalizedClipInspectorRename(
          currentLabel: 'Verse',
          draft: '  Chorus  ',
        ),
        'Chorus',
      );
      expect(
        audioEditorNormalizedClipInspectorRename(
          currentLabel: 'Verse',
          draft: '   ',
        ),
        isNull,
      );
      expect(
        audioEditorNormalizedClipInspectorRename(
          currentLabel: 'Verse',
          draft: 'Verse',
        ),
        isNull,
      );
    });
  });

  group('Project Settings audio-routing visibility', () {
    test('phone and narrow tablet layouts keep the routing launcher', () {
      expect(
        showProjectSettingsAudioRoutingLauncher(
          showInlineAudioRouting: false,
          isMobilePlatform: true,
        ),
        isTrue,
      );
    });

    test('desktop and landscape tablet layouts keep existing routing UI', () {
      expect(
        showProjectSettingsAudioRoutingLauncher(
          showInlineAudioRouting: true,
          isMobilePlatform: false,
        ),
        isTrue,
      );
      expect(
        showProjectSettingsAudioRoutingLauncher(
          showInlineAudioRouting: true,
          isMobilePlatform: true,
        ),
        isTrue,
      );
    });

    test('non-mobile narrow layouts remain unchanged', () {
      expect(
        showProjectSettingsAudioRoutingLauncher(
          showInlineAudioRouting: false,
          isMobilePlatform: false,
        ),
        isFalse,
      );
    });
  });

  group('transport endpoint', () {
    test('short projects use the 128-bar boundary', () {
      final endPoint = audioEditorTransportEndPoint(
        contentEnd: const Duration(seconds: 10),
        bpm: 120,
      );

      expect(endPoint, const Duration(seconds: 256));
    });

    test('projects longer than 128 bars use their content boundary', () {
      const contentEnd = Duration(seconds: 300);

      expect(
        audioEditorTransportEndPoint(contentEnd: contentEnd, bpm: 120),
        contentEnd,
      );
    });

    test(
      'playhead after short content but before bar 128 keeps its position',
      () {
        final endPoint = audioEditorTransportEndPoint(
          contentEnd: const Duration(seconds: 10),
          bpm: 120,
        );

        expect(
          audioEditorPlayheadAtOrPastTransportEnd(
            hasTimelineClips: true,
            playhead: const Duration(seconds: 30),
            transportEnd: endPoint,
          ),
          isFalse,
        );
        expect(
          audioEditorPlayheadAtOrPastTransportEnd(
            hasTimelineClips: true,
            playhead: endPoint,
            transportEnd: endPoint,
          ),
          isTrue,
        );
      },
    );

    test('tempo changes recalculate the 128-bar boundary', () {
      final at120 = audioEditorTransportEndPoint(
        contentEnd: const Duration(seconds: 10),
        bpm: 120,
      );
      final at60 = audioEditorTransportEndPoint(
        contentEnd: const Duration(seconds: 10),
        bpm: 60,
      );

      expect(at120, const Duration(seconds: 256));
      expect(at60, const Duration(seconds: 512));
    });

    test('empty projects do not trigger transport-end restart behavior', () {
      expect(
        audioEditorPlayheadAtOrPastTransportEnd(
          hasTimelineClips: false,
          playhead: const Duration(seconds: 512),
          transportEnd: const Duration(seconds: 256),
        ),
        isFalse,
      );
    });
  });
}
