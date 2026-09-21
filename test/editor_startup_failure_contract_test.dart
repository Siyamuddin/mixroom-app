import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _methodBody(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: signature);
  final afterSignature = start + signature.length;
  var immediateBody = afterSignature;
  while (immediateBody < source.length &&
      source[immediateBody].trim().isEmpty) {
    immediateBody++;
  }
  final asyncBodyMarker = source.indexOf(') async {', afterSignature);
  final syncBodyMarker = source.indexOf(') {', afterSignature);
  final bodyMarkers = <int>[
    if (asyncBodyMarker >= 0) asyncBodyMarker + ') async '.length,
    if (syncBodyMarker >= 0) syncBodyMarker + ') '.length,
  ]..sort();
  final signatureOpensNamedParameters = signature.trimRight().endsWith('(');
  final openBrace =
      !signatureOpensNamedParameters &&
          immediateBody < source.length &&
          source[immediateBody] == '{'
      ? immediateBody
      : bodyMarkers.isEmpty
      ? source.indexOf('{', afterSignature)
      : bodyMarkers.first;
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
  late String recoveryCard;

  setUpAll(() {
    editor = File('lib/screens/audio_editor.dart').readAsStringSync();
    juceEngine = File(
      'juce_audio_engine/lib/juce_audio_engine.dart',
    ).readAsStringSync();
    recoveryCard = File(
      'lib/widgets/audio_startup_recovery_card.dart',
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
    final guard = body.indexOf('if (!_loadedOnce || !_editorSessionReady)');
    final naming = body.indexOf('_ensureProjectNamedOnFirstExit()');
    final save = body.indexOf('_saveProject(showSnackBar: false)');
    expect(guard, greaterThanOrEqualTo(0));
    expect(naming, greaterThan(guard));
    expect(save, greaterThan(guard));
    expect(
      body.substring(guard, naming),
      contains('_projectAutosaveCoordinator.clearDirty()'),
    );
    expect(
      body.substring(guard, naming),
      contains('await _shutdownAudioEngineV2Aware()'),
    );
  });

  test('save and autosave refuse to write before the project loaded', () {
    final save = _methodBody(
      editor,
      'Future<void> _saveProject({bool showSnackBar = true}) async',
    );
    expect(save, contains('if (!_loadedOnce || !_editorSessionReady)'));
    expect(
      save.indexOf('if (!_loadedOnce || !_editorSessionReady)'),
      lessThan(save.indexOf('await _projectAutosaveCoordinator.flush()')),
    );

    final autosave = _methodBody(
      editor,
      'Future<void> _performAutosaveWrite() async',
    );
    expect(autosave, contains('if (!_loadedOnce || !_editorSessionReady)'));
    expect(
      autosave.indexOf('if (!_loadedOnce || !_editorSessionReady)'),
      lessThan(autosave.indexOf('if (_usingCompatibilityAudio)')),
    );
  });

  test('resumed apps retry start-up when audio failed to start', () {
    final body = _methodBody(
      editor,
      'void didChangeAppLifecycleState(AppLifecycleState state)',
    );
    expect(body, contains('state == AppLifecycleState.resumed'));
    expect(body, contains('_audioStartupFailed &&'));
    expect(body, contains('!_editorStartupInFlight'));
    expect(body, contains('unawaited(_startEditorSession())'));
  });

  test('mobile lifecycle work cannot race editor startup', () {
    final lifecycle = _methodBody(
      editor,
      'void didChangeAppLifecycleState(AppLifecycleState state)',
    );
    final readinessGuard = lifecycle.indexOf(
      'if (isMobilePlatform && !_editorSessionReady)',
    );
    final androidResume = lifecycle.indexOf('_handleAndroidEditorResumed()');
    final iosResume = lifecycle.indexOf('_resumeIOSV2AudioAfterForeground()');

    expect(readinessGuard, greaterThanOrEqualTo(0));
    expect(androidResume, greaterThan(readinessGuard));
    expect(iosResume, greaterThan(readinessGuard));
    final guardedLifecycle = lifecycle.substring(0, androidResume);
    expect(guardedLifecycle, contains('_audioStartupFailed'));
    expect(guardedLifecycle, contains('!_editorStartupInFlight'));
    expect(guardedLifecycle, contains('unawaited(_startEditorSession())'));
    expect(guardedLifecycle, contains('return;'));
  });

  test('desktop DAW shortcuts stay blocked until the editor is ready', () {
    final keyboard = _methodBody(
      editor,
      'bool _handleMacEditorKeyEvent(KeyEvent event)',
    );
    final readinessGuard = keyboard.indexOf('if (!_editorSessionReady)');
    final undoShortcut = keyboard.indexOf('_kDesktopShortcutUndo');
    final recordShortcut = keyboard.indexOf('_kDesktopShortcutToggleRecord');

    expect(readinessGuard, greaterThanOrEqualTo(0));
    expect(undoShortcut, greaterThan(readinessGuard));
    expect(recordShortcut, greaterThan(readinessGuard));
    final guardBody = keyboard.substring(0, undoShortcut);
    expect(guardBody, contains('_audioStartupRetryFocusNode.hasFocus'));
    expect(guardBody, contains('_audioStartupBackFocusNode.hasFocus'));
    expect(guardBody, contains('key == LogicalKeyboardKey.tab'));
    expect(guardBody, contains('return true;'));
  });

  test('startup attempts cannot overlap or restore a project twice', () {
    final startup = _methodBody(
      editor,
      'Future<void> _startEditorSession() async',
    );
    expect(startup, contains('_editorStartupInFlight ||'));
    expect(startup, contains('_loadedOnce ||'));
    expect(startup, contains('_projectLoadAttempted'));

    final shutdown = _methodBody(
      editor,
      'Future<void> _shutdownAudioEngineV2Aware()',
    );
    expect(shutdown, contains('final existing = _audioEngineShutdownFuture;'));
    expect(
      shutdown,
      contains('_audioEngineShutdownFuture = null;'),
      reason:
          'A completed cleanup must allow Retry to perform a fresh cleanup.',
    );
  });

  test('project loaded state is published only after restoration succeeds', () {
    final body = _methodBody(editor, 'Future<bool> _loadProjectIfAny() async');
    final attempt = body.indexOf('_projectLoadAttempted = true;');
    final restoreHistory = body.indexOf(
      'await _restorePersistedUndoHistory(json)',
    );
    final loaded = body.indexOf('_loadedOnce = true;');

    expect(attempt, greaterThanOrEqualTo(0));
    expect(restoreHistory, greaterThan(attempt));
    expect(loaded, greaterThan(restoreHistory));
    expect(body, isNot(contains('AnalyticsService.instance.trackScreen(')));
    expect(body, contains('_loadedOnce = false;'));
    expect(body, contains('_projectAutosaveCoordinator.clearDirty();'));
    expect(body, contains('return projectLoadedSuccessfully;'));

    final startup = _methodBody(
      editor,
      'Future<void> _startEditorSession() async',
    );
    expect(
      startup.indexOf('_editorSessionReady = true;'),
      lessThan(startup.indexOf('_trackSuccessfulProjectOpen();')),
    );
    expect(
      startup.indexOf('_editorSessionReady = true;'),
      lessThan(startup.indexOf('await _flushPendingDesktopFinderDrops();')),
      reason: 'Queued imports must stay disabled until startup is complete.',
    );
    final analytics = _methodBody(editor, 'void _trackSuccessfulProjectOpen()');
    expect(analytics, contains('if (_successfulProjectOpenTracked ||'));
    expect(analytics, contains('!_editorSessionReady'));
    expect(analytics, contains('AnalyticsEvents.projectOpened('));
  });

  test('all pre-load failures share cleanup and blocking recovery', () {
    final startup = _methodBody(
      editor,
      'Future<void> _startEditorSession() async',
    );
    final failure = _methodBody(
      editor,
      'Future<void> _enterEditorStartupFailure(',
    );

    expect(startup, contains("diagnosticCode: 'prior_shutdown_failed'"));
    expect(startup, contains("diagnosticCode: 'route_monitoring_unavailable'"));
    expect(startup, contains("diagnosticCode: 'unexpected_startup_error'"));
    expect(failure, contains('_projectAutosaveCoordinator.clearDirty();'));
    expect(failure, contains('_stopMidiDeviceConnectionPolling();'));
    expect(failure, contains('await _shutdownAudioEngineV2Aware();'));
    expect(failure, contains('_audioStartupFailed = true;'));
    expect(recoveryCard, contains('editor_audio_startup_recovery_overlay'));
    expect(editor, contains('_buildAudioStartupRecoveryOverlay()'));
    expect(editor, isNot(contains('_buildAudioStartupFailedBanner()')));
  });

  test('startup diagnostics are concise and omit project paths', () {
    final summary = _methodBody(editor, 'void _logEditorStartupSummary(');
    expect(summary, contains(r'stage=$stage'));
    expect(summary, contains(r'attempt=$attempt'));
    expect(summary, contains('elapsedMs='));
    expect(summary, contains(r'diagnosticCode=$diagnosticCode'));
    expect(summary, contains('routeConsistency='));
    expect(summary, contains('sampleRateHz='));
    expect(summary, contains('bufferFrames='));
    expect(summary, contains('projectLoadBegan='));
    expect(summary, isNot(contains('_projectDir')));
    expect(summary, isNot(contains('_projectId')));
    expect(editor, isNot(contains('_logAudioStartupFailure(')));
    expect(editor, isNot(contains('Audio editor startup failed')));
  });

  test('version snapshots refuse to run before a successful load', () {
    for (final signature in <String>[
      'void _requestLocalVersionSnapshot(',
      'void _flushAndRequestLocalVersionSnapshot(',
    ]) {
      final body = _methodBody(editor, signature);
      expect(
        body,
        contains(
          'if (!_loadedOnce || !_editorSessionReady || _isProjectLoading) return;',
        ),
      );
    }
  });

  test('startup recovery copy exists in every translation table', () {
    final l10n = File('lib/l10n/l10n.dart').readAsStringSync();
    for (final key in <String>[_recoveryMessageKey, _safeOpenMessageKey]) {
      final translationKey = RegExp("'${RegExp.escape(key)}'\\s*:");
      expect(translationKey.allMatches(l10n), hasLength(4), reason: key);
    }
  });
}

const _recoveryMessageKey =
    'Audio is unavailable, so this project has not loaded. Your saved project remains unchanged.';
const _safeOpenMessageKey =
    'This project could not be opened safely. Reopen it to try again.';
