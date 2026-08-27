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
    final audioInvalidation = method.indexOf(
      'if (_v2AudioSessionInvalidated)',
    );

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
    final start = editor.indexOf(
      'Future<bool> _stopMidiClipRecordingImpl({',
    );
    final end = editor.indexOf('Future<void> _startRecordingJuce()', start);
    final method = editor.substring(start, end);

    final captureChanges = method.indexOf(
      'final hadMidiChanges = _midiRecordHasChanges;',
    );
    final runtimeClear = method.indexOf('_clearMidiRecordingRuntimeState();');
    final uiClear = method.indexOf('_isRecording = false;', runtimeClear);
    final engineSync = method.indexOf(
      'await _updateMidiClipEventsLive(clip)',
    );
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
      await _buildTrack(
        engineClipId: 11,
        kind: ClipKind.midi,
        label: 'piano',
      ),
      await _buildTrack(
        engineClipId: 22,
        kind: ClipKind.audio,
        label: 'audio',
      ),
    ];

    final armed = resolveArmedMidiClip(
      tracks: tracks,
      activeMidiClipEngineId: 11,
      primarySelectedClipIndex: 1,
    );

    expect(armed?.engineClipId, 11);
  });

  test('falls back to the selected midi clip when editor clip is absent',
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
  });

  test('recording ignores an armed midi clip from another selected row',
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
  });

  test('does not arm a non-midi primary selection', () async {
    final tracks = <AudioTrack>[
      await _buildTrack(
        engineClipId: 11,
        kind: ClipKind.audio,
        label: 'audio',
      ),
      await _buildTrack(
        engineClipId: 22,
        kind: ClipKind.midi,
        label: 'bass',
      ),
    ];

    final armed = resolveArmedMidiClip(
      tracks: tracks,
      activeMidiClipEngineId: null,
      primarySelectedClipIndex: 0,
    );

    expect(armed, isNull);
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
      resolveSelectedInstrumentLaneRecordingRow(
        rows: rows,
        selectedRow: 1,
      ),
      1,
    );
  });

  test('does not resolve an audio row for midi recording', () {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Audio', iconId: 0),
    ];

    expect(
      resolveSelectedInstrumentLaneRecordingRow(
        rows: rows,
        selectedRow: 0,
      ),
      isNull,
    );
  });
}
