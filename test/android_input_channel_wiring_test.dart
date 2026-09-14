import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final editor = File('lib/screens/audio_editor.dart').readAsStringSync();
  final plugin = File(
    'juce_audio_engine/android/src/main/kotlin/com/mixroom/juce_audio_engine/JuceAudioEnginePlugin.kt',
  ).readAsStringSync();
  String section(String source, String start, String end) {
    final begin = source.indexOf(start);
    expect(begin, greaterThanOrEqualTo(0));
    final finish = source.indexOf(end, begin + start.length);
    expect(finish, greaterThan(begin));
    return source.substring(begin, finish);
  }

  test(
    'both input-control locations use the shared selector and explicit replacement persists',
    () {
      expect(
        RegExp(
          r'_buildInputChannelRouteSelector\(\),',
        ).allMatches(editor).length,
        2,
      );
      final selector = section(
        editor,
        '  Widget _buildInputChannelRouteSelector() {',
        '    if (Platform.isMacOS && _isBluetoothV2Session) {',
      );
      expect(selector, contains('row?.inputChannelStart'));
      expect(selector, contains('row?.inputChannelCount'));
      expect(selector, contains('onUseSupportedInput:'));
      expect(selector, contains('_scheduleProjectAutosave();'));
      expect(selector, isNot(contains('_buildInputChannelRouteOptions')));
    },
  );

  test(
    'replacement is blocked by capture transitions but not metadata refresh',
    () {
      final policy = section(
        editor,
        '  bool get _monoSystemInputReplacementEnabled',
        '  Widget _buildInputChannelRouteSelector()',
      );
      expect(policy, contains('_recordTransitionInFlight'));
      expect(policy, contains('AudioRouteCoordinatorStateV2.preparingInput'));
      expect(policy, contains('AudioRouteCoordinatorStateV2.reconfiguring'));
      expect(policy, isNot(contains('_androidInputRefreshFuture')));
    },
  );
  test('replacement refreshes the visible audio-routing sheet immediately', () {
    final refresh = section(
      editor,
      '  void _setStateAndRefreshProjectSettings(',
      '  void _refreshAudioEditorView(',
    );
    expect(refresh, contains('_audioRoutingSheetStateSetter'));
    expect(editor, contains('_audioRoutingSheetStateSetter = setSheetState;'));
    expect(editor, contains('_audioRoutingSheetStateSetter = null;'));
  });
  test(
    'input refresh is coalesced, rejects superseded responses and does not mutate audio',
    () {
      final refresh = section(
        editor,
        '  Future<void> _refreshAndroidRecordingInput()',
        '  void _clearAndroidVerifiedInputName()',
      );
      expect(refresh, contains('_androidInputRefreshFuture ??='));
      expect(refresh, contains('revision != _androidInputRefreshRevision'));
      for (final forbidden in [
        'transitionIntent(',
        '_pausePlayback(',
        'prepareRecording',
        '_normalizeInputChannelSelection(',
        'copyWith(',
      ]) {
        expect(refresh, isNot(contains(forbidden)));
      }
      final callback = section(
        plugin,
        'override fun onAudioDevicesAdded',
        'private val',
      );
      expect(
        RegExp(r'emitInputStatusChangedV2\(\)').allMatches(callback).length,
        2,
      );
    },
  );
  test(
    'native rejects unsupported intent ranges before selecting an adapter and rechecks start/readiness',
    () {
      final intent = section(
        plugin,
        '  private fun setAudioRouteIntentV2(',
        '  private fun startPreparedCaptureV2(',
      );
      expect(intent, contains('AndroidRecordingChannelPolicyV2.accepts('));
      expect(
        intent.indexOf('!validRecordingSelection'),
        lessThan(intent.indexOf('prepareSystemSelectedRecordingV2(')),
      );
      final start = section(
        plugin,
        '  private fun startPreparedCaptureV2(',
        '  private fun ',
      );
      expect(start, contains('!AndroidRecordingChannelPolicyV2.accepts('));
      final readiness = section(
        plugin,
        '  private fun validatePreparedRecordingV2(',
        '  private fun ',
      );
      expect(readiness, contains('!AndroidRecordingChannelPolicyV2.accepts('));
    },
  );
}
