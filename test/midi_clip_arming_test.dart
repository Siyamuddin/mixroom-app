import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/midi_clip_arming.dart';
import 'package:mixroom/models/models.dart';

Future<AudioTrack> _buildTrack({
  required int engineClipId,
  required ClipKind kind,
  required String label,
  int rowIndex = -1,
}) {
  final file = File('/tmp/$label.wav');
  return AudioTrack.create(
    file: file,
    originalFile: file,
    audioDuration: const Duration(seconds: 1),
    trimEnd: const Duration(seconds: 1),
    engineClipId: engineClipId,
    label: label,
    clipKind: kind,
    rowIndex: rowIndex,
  );
}

void main() {
  test('V2 recording resolves MIDI before audio-row validation', () {
    final editor = File('lib/screens/audio_editor.dart').readAsStringSync();
    final start = editor.indexOf('Future<void> _startRecordingJuce() async {');
    final end = editor.indexOf(
      'Future<void> _letRecordingVisualStatePaint()',
      start,
    );
    final method = editor.substring(start, end);

    final midiTarget = method.indexOf('final midiClipIndex =');
    final midiStart = method.indexOf(
      'await _startMidiClipRecording(midiClipIndex)',
    );
    final laneTarget = method.indexOf(
      'resolveSelectedInstrumentLaneRecordingRow(',
    );
    final laneStart = method.indexOf(
      'await _startSelectedInstrumentLaneMidiRecording(',
    );
    final audioGuard = method.indexOf('if (_isBluetoothV2Session)');

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    expect(midiTarget, greaterThanOrEqualTo(0));
    expect(midiStart, greaterThan(midiTarget));
    expect(laneTarget, greaterThan(midiStart));
    expect(laneStart, greaterThan(laneTarget));
    expect(audioGuard, greaterThan(laneStart));
  });

  test('explicit audio row outranks stale MIDI editor state', () {
    final editor = File('lib/screens/audio_editor.dart').readAsStringSync();
    final start = editor.indexOf('Future<void> _startRecordingJuce() async {');
    final end = editor.indexOf(
      'Future<void> _letRecordingVisualStatePaint()',
      start,
    );
    final method = editor.substring(start, end);

    final audioSelection = method.indexOf('final explicitAudioRowSelected =');
    final midiResolution = method.indexOf('_activeMidiRecordingClipIndex()');
    expect(audioSelection, greaterThanOrEqualTo(0));
    expect(midiResolution, greaterThan(audioSelection));
    expect(method, contains('if (!explicitAudioRowSelected)'));
    expect(
      method,
      contains('_rows[_selectedRow].kind == TimelineRowKind.audio'),
    );
  });

  test('audio take owns a stable row ID through publication', () {
    final editor = File('lib/screens/audio_editor.dart').readAsStringSync();
    final start = editor.indexOf('Future<void> _startAudioRecordingJuce()');
    final stop = editor.indexOf('Future<void> _stopAudioRecordingJuce', start);
    final startMethod = editor.substring(start, stop);
    final stopEnd = editor.indexOf('Future<void> _addAudioTrackFromFile', stop);
    final stopMethod = editor.substring(stop, stopEnd);

    expect(startMethod, contains('final targetRowId = _rowIdAt(_selectedRow)'));
    expect(startMethod, contains('_audioRecordingTargetRowId = targetRowId'));
    expect(stopMethod, contains('_rowIndexForId(targetRowId)'));
    expect(
      stopMethod,
      isNot(
        contains(
          'final int row = (_selectedRow >= 0 && _selectedRow < _rowCount)',
        ),
      ),
    );
    expect(stopMethod, contains("_rows[row].kind != TimelineRowKind.audio"));
    expect(stopMethod, contains('_audioRecordingTargetRowId = null'));
  });

  test('record button reaches MIDI resolution before V2 audio validation', () {
    final editor = File('lib/screens/audio_editor.dart').readAsStringSync();
    final handlerStart = editor.indexOf(
      'Future<void> _handleRecordPressed({required bool keepPlayingOnStop})',
    );
    final handlerEnd = editor.indexOf(
      'String _normalizeEffectText',
      handlerStart,
    );
    final handler = editor.substring(handlerStart, handlerEnd);
    final start = editor.indexOf('Future<void> _startRecordingJuce() async {');
    final end = editor.indexOf(
      'Future<void> _letRecordingVisualStatePaint()',
      start,
    );
    final method = editor.substring(start, end);

    expect(handler, isNot(contains('_supportsV2AudioRecording')));
    expect(handler, isNot(contains('_v2AudioSessionInvalidated')));
    expect(handler, contains('await _startRecordingJuce();'));

    final midiTarget = method.indexOf('final midiClipIndex =');
    final laneTarget = method.indexOf(
      'resolveSelectedInstrumentLaneRecordingRow(',
    );
    final audioCapability = method.indexOf('if (!_supportsV2AudioRecording)');
    final audioInvalidation = method.indexOf('if (_v2AudioSessionInvalidated)');

    expect(midiTarget, greaterThanOrEqualTo(0));
    expect(laneTarget, greaterThan(midiTarget));
    expect(audioCapability, greaterThan(laneTarget));
    expect(audioInvalidation, greaterThan(audioCapability));
    expect(
      method.substring(audioInvalidation),
      contains('_showSmallNotice(_v2AudioSessionInvalidationNotice)'),
    );
  });

  test('MIDI recording commits only after playback succeeds', () {
    final editor = File('lib/screens/audio_editor.dart').readAsStringSync();
    final start = editor.indexOf(
      'Future<void> _startMidiRecordingTransaction({',
    );
    final end = editor.indexOf('Future<void> _stopMidiClipRecording', start);
    final method = editor.substring(start, end);

    final transportStart = method.indexOf(
      'await _togglePlayPauseAudio(_safeAudioEditorStateSetter)',
    );
    final transportGuard = method.indexOf(
      'if (!mounted || !_isPlaying || _recordStartCancelRequested) return;',
    );
    final targetCreation = method.indexOf(
      'await _createSelectedInstrumentLaneMidiRecordingClip(',
    );
    final liveTargetArm = method.indexOf(
      'await _armLiveMidiInputTargetForRecording(',
    );
    final staleEventDrain = method.indexOf(
      'await JuceAudioEngine.consumeLiveMidiInputEvents()',
    );
    final recordingCommit = method.indexOf('_isRecording = true;');
    final midiCommit = method.indexOf('_isMidiClipRecording = true;');
    final timerStart = method.indexOf(
      '_midiHeldNoteRefreshTimer = Timer.periodic(',
    );

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    expect(transportStart, greaterThanOrEqualTo(0));
    expect(transportGuard, greaterThan(transportStart));
    expect(targetCreation, greaterThan(transportGuard));
    expect(liveTargetArm, greaterThan(targetCreation));
    expect(staleEventDrain, greaterThan(liveTargetArm));
    expect(recordingCommit, greaterThan(staleEventDrain));
    expect(midiCommit, greaterThan(recordingCommit));
    expect(timerStart, greaterThan(midiCommit));
  });

  test('failed MIDI startup rolls back clips, runtime, and pending UI', () {
    final editor = File('lib/screens/audio_editor.dart').readAsStringSync();
    final start = editor.indexOf(
      'Future<void> _startMidiRecordingTransaction({',
    );
    final end = editor.indexOf('Future<void> _stopMidiClipRecording', start);
    final method = editor.substring(start, end);
    final clearStart = editor.indexOf('void _clearMidiRecordingRuntimeState()');
    final clearEnd = editor.indexOf(
      'Future<void> _startMidiRecordingTransaction({',
      clearStart,
    );
    final clearMethod = editor.substring(clearStart, clearEnd);

    final runtimeClear = method.indexOf('_clearMidiRecordingRuntimeState();');
    final rollback = method.indexOf('await rollbackAction.undo();');
    final targetRestore = method.indexOf(
      'await _syncLiveMidiInputTargetClip();',
      rollback,
    );
    final transportRestore = method.indexOf(
      'if (!transportWasPlaying && _isPlaying)',
      targetRestore,
    );

    expect(runtimeClear, greaterThanOrEqualTo(0));
    expect(rollback, greaterThan(runtimeClear));
    expect(targetRestore, greaterThan(rollback));
    expect(transportRestore, greaterThan(targetRestore));
    expect(method, contains('_clearMidiRecordingRuntimeState();'));
    expect(clearMethod, contains('_midiInputPollTimer = null;'));
    expect(clearMethod, contains('_midiHeldNoteRefreshTimer = null;'));
    expect(clearMethod, contains('_midiRecordingClipEngineId = null;'));
    expect(clearMethod, contains('_midiRecordingClipIndex = null;'));
    expect(clearMethod, contains('_isMidiClipRecording = false;'));
    expect(method, contains('_recordStartVisualPending = false;'));
    expect(method, contains('_isRecording = false;'));
    expect(method, contains('_recordTransitionInFlight = false;'));
    expect(method, contains('if (!transportWasPlaying && _isPlaying)'));
  });

  test('MIDI stop is serialized and always releases its guard', () {
    final editor = File('lib/screens/audio_editor.dart').readAsStringSync();
    final start = editor.indexOf('Future<void> _stopMidiClipRecording({');
    final end = editor.indexOf(
      'Future<bool> _stopMidiClipRecordingImpl({',
      start,
    );
    final method = editor.substring(start, end);

    final guard = method.indexOf('if (_recordTransitionInFlight) return;');
    final acquire = method.indexOf('_recordTransitionInFlight = true;');
    final stop = method.indexOf('await _stopMidiClipRecordingImpl(');
    final release = method.indexOf('_recordTransitionInFlight = false;');

    expect(guard, greaterThanOrEqualTo(0));
    expect(acquire, greaterThan(guard));
    expect(stop, greaterThan(acquire));
    expect(release, greaterThan(stop));
    expect(method, contains('finally'));
    expect(method.indexOf('_scheduleProjectAutosave();'), greaterThan(release));
  });

  test('MIDI stop reaches idle before fallible engine synchronization', () {
    final editor = File('lib/screens/audio_editor.dart').readAsStringSync();
    final start = editor.indexOf('Future<bool> _stopMidiClipRecordingImpl({');
    final end = editor.indexOf('Future<void> _startRecordingJuce()', start);
    final method = editor.substring(start, end);

    final captureChanges = method.indexOf(
      'final hadMidiChanges = _midiRecordHasChanges;',
    );
    final runtimeClear = method.indexOf('_clearMidiRecordingRuntimeState();');
    final uiClear = method.indexOf('_isRecording = false;', runtimeClear);
    final engineSync = method.indexOf('await _updateMidiClipEventsLive(clip)');
    final previewRestore = method.indexOf(
      'await _setLiveMidiInputTargetClipIfNeeded(previewClip, force: true)',
    );

    expect(captureChanges, greaterThanOrEqualTo(0));
    expect(runtimeClear, greaterThan(captureChanges));
    expect(uiClear, greaterThan(runtimeClear));
    expect(engineSync, greaterThan(uiClear));
    expect(previewRestore, greaterThan(engineSync));
    expect(method, contains('MIDI recording final drain failed:'));
    expect(method, contains('MIDI recording engine sync failed:'));
    expect(method, contains('MIDI recording preview target restore failed:'));
    expect(method, contains('MIDI recording transport stop failed:'));
  });

  test('live target failure retains local MIDI recording', () {
    final editor = File('lib/screens/audio_editor.dart').readAsStringSync();
    final start = editor.indexOf(
      'Future<void> _startMidiRecordingTransaction({',
    );
    final end = editor.indexOf('Future<void> _stopMidiClipRecording', start);
    final method = editor.substring(start, end);

    expect(method, contains('var liveTargetOk ='));
    expect(method, isNot(contains('if (!liveTargetOk) return')));
    expect(method, contains('liveTargetOk = false;'));
    expect(method, contains('_midiRecordingLiveInputArmed = liveTargetOk;'));
    expect(method, contains('_isMidiClipRecording = true;'));
  });

  test('V2 safety boundary clears MIDI without audio recorder cleanup', () {
    final editor = File('lib/screens/audio_editor.dart').readAsStringSync();
    final start = editor.indexOf('bool _endMidiRecordingForV2SafetyBoundary()');
    final end = editor.indexOf(
      'Future<void> _restoreInterruptedMidiClipAfterV2Recovery()',
      start,
    );
    final method = editor.substring(start, end);

    expect(method, contains('closeHeldNotes: true'));
    expect(method, contains('_clearMidiRecordingRuntimeState();'));
    expect(method, isNot(contains('_stopAudioRecordingJuce')));
    expect(method, isNot(contains('abortRecordingV2')));
  });

  test('non-MIDI targets retain the existing audio recording path', () {
    final editor = File('lib/screens/audio_editor.dart').readAsStringSync();
    final start = editor.indexOf('Future<void> _startRecordingJuce() async {');
    final end = editor.indexOf(
      'Future<void> _letRecordingVisualStatePaint()',
      start,
    );
    final method = editor.substring(start, end);

    final audioGuard = method.indexOf('if (_isBluetoothV2Session)');
    final v2AudioStart = method.indexOf(
      'await _startAudioRecordingJuce();',
      audioGuard,
    );
    final legacyAudioStart = method.indexOf(
      'await _startAudioRecordingJuce();',
      v2AudioStart + 1,
    );

    expect(audioGuard, greaterThanOrEqualTo(0));
    expect(v2AudioStart, greaterThan(audioGuard));
    expect(legacyAudioStart, greaterThan(v2AudioStart));
  });

  test('prefers active midi editor clip when available', () async {
    final tracks = <AudioTrack>[
      await _buildTrack(engineClipId: 11, kind: ClipKind.midi, label: 'piano'),
      await _buildTrack(engineClipId: 22, kind: ClipKind.audio, label: 'audio'),
    ];

    final armed = resolveArmedMidiClip(
      tracks: tracks,
      activeMidiClipEngineId: 11,
      primarySelectedClipIndex: 1,
    );

    expect(armed?.engineClipId, 11);
  });

  test(
    'falls back to the selected midi clip when editor clip is absent',
    () async {
      final tracks = <AudioTrack>[
        await _buildTrack(
          engineClipId: 11,
          kind: ClipKind.audio,
          label: 'audio',
        ),
        await _buildTrack(
          engineClipId: 22,
          kind: ClipKind.midi,
          label: 'strings',
        ),
      ];

      final armed = resolveArmedMidiClip(
        tracks: tracks,
        activeMidiClipEngineId: null,
        primarySelectedClipIndex: 1,
      );

      expect(armed?.engineClipId, 22);
    },
  );

  test(
    'recording ignores an armed midi clip from another selected row',
    () async {
      final tracks = <AudioTrack>[
        await _buildTrack(
          engineClipId: 11,
          kind: ClipKind.midi,
          label: 'piano',
          rowIndex: 0,
        ),
        await _buildTrack(
          engineClipId: 22,
          kind: ClipKind.audio,
          label: 'voice',
          rowIndex: 1,
        ),
      ];

      final armed = resolveArmedMidiClip(
        tracks: tracks,
        activeMidiClipEngineId: 11,
        primarySelectedClipIndex: 0,
        requiredRowIndex: 1,
      );

      expect(armed, isNull);
    },
  );

  test('does not arm a non-midi primary selection', () async {
    final tracks = <AudioTrack>[
      await _buildTrack(engineClipId: 11, kind: ClipKind.audio, label: 'audio'),
      await _buildTrack(engineClipId: 22, kind: ClipKind.midi, label: 'bass'),
    ];

    final armed = resolveArmedMidiClip(
      tracks: tracks,
      activeMidiClipEngineId: null,
      primarySelectedClipIndex: 0,
    );

    expect(armed, isNull);
  });

  test(
    'preferred instrument row wins over a selected midi clip on another row',
    () async {
      final tracks = <AudioTrack>[
        await _buildTrack(
          engineClipId: 11,
          kind: ClipKind.midi,
          label: 'piano',
          rowIndex: 0,
        ),
        await _buildTrack(
          engineClipId: 22,
          kind: ClipKind.midi,
          label: 'synth',
          rowIndex: 1,
        ),
      ];

      final armed = resolveArmedMidiClip(
        tracks: tracks,
        activeMidiClipEngineId: 11,
        primarySelectedClipIndex: 0,
        preferredRowIndex: 1,
      );

      expect(armed?.engineClipId, 22);
    },
  );

  test(
    'preferred row keeps the open editor clip when it belongs to that row',
    () async {
      final tracks = <AudioTrack>[
        await _buildTrack(
          engineClipId: 11,
          kind: ClipKind.midi,
          label: 'synth-a',
          rowIndex: 1,
        ),
        await _buildTrack(
          engineClipId: 22,
          kind: ClipKind.midi,
          label: 'synth-b',
          rowIndex: 1,
        ),
      ];

      final armed = resolveArmedMidiClip(
        tracks: tracks,
        activeMidiClipEngineId: 22,
        primarySelectedClipIndex: 0,
        preferredRowIndex: 1,
      );

      expect(armed?.engineClipId, 22);
    },
  );

  test(
    'preferred row with no midi clips falls back to the selected midi clip',
    () async {
      final tracks = <AudioTrack>[
        await _buildTrack(
          engineClipId: 11,
          kind: ClipKind.midi,
          label: 'piano',
          rowIndex: 0,
        ),
        await _buildTrack(
          engineClipId: 22,
          kind: ClipKind.audio,
          label: 'voice',
          rowIndex: 1,
        ),
      ];

      final armed = resolveArmedMidiClip(
        tracks: tracks,
        activeMidiClipEngineId: null,
        primarySelectedClipIndex: 0,
        preferredRowIndex: 1,
      );

      expect(armed?.engineClipId, 11);
    },
  );

  test('preferred audio-only row does not arm midi by itself', () async {
    final tracks = <AudioTrack>[
      await _buildTrack(
        engineClipId: 11,
        kind: ClipKind.audio,
        label: 'voice',
        rowIndex: 0,
      ),
      await _buildTrack(
        engineClipId: 22,
        kind: ClipKind.midi,
        label: 'piano',
        rowIndex: 1,
      ),
    ];

    final armed = resolveArmedMidiClip(
      tracks: tracks,
      activeMidiClipEngineId: null,
      primarySelectedClipIndex: 0,
      preferredRowIndex: 0,
    );

    expect(armed, isNull);
  });

  test('header row select arms live MIDI for instrument lanes', () {
    final editor = File('lib/screens/audio_editor.dart').readAsStringSync();
    final start = editor.indexOf('onSelectRow:');
    final end = editor.indexOf('onToggleExpanded:', start);
    final handler = editor.substring(start, end);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    expect(handler, contains('_selectedRow = row'));
    expect(handler, contains('_armLiveMidiInputForInstrumentRow'));
    expect(handler, contains('unawaited('));
  });

  test(
    'instrument header arming finds or creates a clip before syncing live MIDI',
    () {
      final editor = File('lib/screens/audio_editor.dart').readAsStringSync();
      final start = editor.indexOf(
        'Future<void> _armLiveMidiInputForInstrumentRow(int row) async {',
      );
      final end = editor.indexOf(
        'Future<void> _openInstrumentUiForRow(int row) async {',
        start,
      );
      final method = editor.substring(start, end);

      final findClip = method.indexOf('_midiClipIndexForInstrumentRow(row)');
      final createClip = method.indexOf(
        'await _createMidiClipInInstrumentLane(',
      );
      final retarget = method.indexOf(
        '_retargetOpenMidiClipEditorToSelection(clipIndex)',
      );
      final prepare = method.indexOf(
        'unawaited(_prepareLiveMidiPreviewRoute())',
      );
      final sync = method.indexOf('await _syncLiveMidiInputTargetClip()');

      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      expect(findClip, greaterThanOrEqualTo(0));
      expect(createClip, greaterThan(findClip));
      expect(retarget, greaterThan(createClip));
      expect(prepare, greaterThan(retarget));
      expect(sync, greaterThan(prepare));
      expect(method, contains('openEditor: false'));
      expect(method, contains('!_rows[row].isInstrumentLane'));
      expect(method, contains('_isLiveMidiRowArmCurrent(rowId, armEpoch)'));
      expect(method, contains('_liveMidiRowArmEpoch'));
      expect(method, isNot(contains('_showPianoRoll = true')));
    },
  );

  test('live MIDI lookups follow the selected instrument row', () {
    final editor = File('lib/screens/audio_editor.dart').readAsStringSync();
    final armedStart = editor.indexOf('AudioTrack? _armedMidiClipOrNull() {');
    final armedEnd = editor.indexOf(
      'int _activeMidiClipEditorIndex() {',
      armedStart,
    );
    final armed = editor.substring(armedStart, armedEnd);
    final desktopStart = editor.indexOf(
      'AudioTrack? _desktopMidiTargetClipOrNull() {',
    );
    final desktopEnd = editor.indexOf(
      'bool _desktopKeyboardMidiCanCapture() {',
      desktopStart,
    );
    final desktop = editor.substring(desktopStart, desktopEnd);
    final syncStart = editor.indexOf(
      'Future<void> _syncLiveMidiInputTargetClip() async {',
    );
    final syncEnd = editor.indexOf(
      'void _handleUndoHistoryChanged() {',
      syncStart,
    );
    final sync = editor.substring(syncStart, syncEnd);

    expect(armed, contains('preferredRowIndex:'));
    expect(armed, contains('resolveSelectedInstrumentLaneRecordingRow('));
    expect(desktop.trim(), contains('return _armedMidiClipOrNull();'));
    expect(sync, contains('_armedMidiClipOrNull()?.engineClipId'));
    expect(sync, isNot(contains('_clipIndexForEngineId(activeEngineId)')));

    final selectionStart = editor.indexOf('onSelectionChanged:');
    final selectionEnd = editor.indexOf(
      'onSnapSettingsChanged:',
      selectionStart,
    );
    final selection = editor.substring(selectionStart, selectionEnd);
    expect(selection, contains('_selectedRow = clipRow'));
    expect(selection, contains('unawaited('));
    expect(selection, contains('_syncLiveMidiInputTargetClip()'));
  });

  test('resolves a selected instrument lane for midi recording', () {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Audio', iconId: 0),
      TimelineRow(
        rowId: 2,
        name: 'Keys',
        iconId: 1,
        kind: TimelineRowKind.instrument,
        instrumentId: 'sfz.vsco.upright_piano',
        instrumentName: 'Upright Piano',
      ),
    ];

    expect(
      resolveSelectedInstrumentLaneRecordingRow(rows: rows, selectedRow: 1),
      1,
    );
  });

  test('does not resolve an audio row for midi recording', () {
    final rows = <TimelineRow>[TimelineRow(rowId: 1, name: 'Audio', iconId: 0)];

    expect(
      resolveSelectedInstrumentLaneRecordingRow(rows: rows, selectedRow: 0),
      isNull,
    );
  });
}
