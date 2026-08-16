import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String objectiveCMethod(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNonNegative, reason: '$signature must exist');
  final next = source.indexOf('\n- (', start + signature.length);
  return source.substring(start, next < 0 ? source.length : next);
}

void main() {
  late String plugin;
  late String editor;
  late String coordinator;
  late String jucePolicyPatch;

  setUpAll(() {
    plugin = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();
    editor = File('lib/screens/audio_editor.dart').readAsStringSync();
    coordinator = File(
      'juce_audio_engine/lib/audio_route_coordinator_v2.dart',
    ).readAsStringSync();
    jucePolicyPatch = File(
      'tools/ios/juce_vendor/mixroom_ios_audio_session_policy.patch',
    ).readAsStringSync();
  });

  test(
    'native observer distinguishes interruption lifecycle without mutation',
    () {
      final observer = objectiveCMethod(
        plugin,
        '- (void)handleIOSAudioRouteChangeV2:(NSNotification *)notification {',
      );

      expect(observer, contains('AVAudioSessionInterruptionTypeKey'));
      expect(observer, contains('AVAudioSessionInterruptionTypeEnded'));
      expect(observer, contains('AVAudioSessionInterruptionOptionKey'));
      expect(observer, contains('AVAudioSessionInterruptionWasSuspendedKey'));
      expect(observer, contains('AVAudioSessionInterruptionReasonKey'));
      expect(observer, contains('UIApplicationDidEnterBackgroundNotification'));
      expect(observer, contains('@"audioInterruptionBegan"'));
      expect(observer, contains('@"audioInterruptionEnded"'));
      expect(
        observer,
        contains(
          'if ((interruptionBegan && !duplicateSuspendedInterruption) ||',
        ),
      );
      expect(observer, contains('pausePlaybackForRouteChangeV2ObjC'));
      expect(observer, isNot(contains('setActive:')));
      expect(observer, isNot(contains('setCategory:')));
      expect(observer, isNot(contains('setPreferredInput:')));
      expect(observer, isNot(contains('reconfigurePlaybackRouteV2ObjC')));
    },
  );

  test('coordinator holds one recovery until interruption end', () {
    expect(coordinator, contains("event.cause == 'audioInterruptionBegan'"));
    expect(coordinator, contains("event.cause == 'audioInterruptionEnded'"));
    expect(coordinator, contains('_interruptionEndedCompletion'));
    expect(coordinator, contains('_invalidationRecovery'));
    expect(coordinator, contains('if (_interruptionActive)'));
    expect(coordinator, contains('await interruptionEnded.future'));
    expect(coordinator, contains('cancelPendingRecoveryForShutdown'));
    expect(coordinator, isNot(contains('Future.delayed')));
  });

  test('editor cleans interruption before recovery and keeps one owner', () {
    final handlerStart = editor.indexOf(
      'void _handleAudioRouteIntentInvalidatedV2(',
    );
    final handlerEnd = editor.indexOf(
      'Future<void> _synchronizeIOSRouteSafetyPositionV2',
      handlerStart,
    );
    final handler = editor.substring(handlerStart, handlerEnd);

    expect(handler, contains('Audio was interrupted. Recording stopped.'));
    expect(handler, contains('Audio is temporarily unavailable.'));
    expect(handler, contains('Audio is ready. Press Play to continue.'));
    expect(handler, contains('_cleanupV2InterruptedAudio'));
    expect(handler, contains('abortRecordingV2(restorePlayback: false)'));
    expect(
      handler.indexOf('_cleanupV2InterruptedAudio('),
      lessThan(handler.indexOf('recoverPlaybackAfterIntentInvalidation()')),
    );
    expect(handler, contains('_deleteUncommittedRecordingFile'));
    expect(handler, isNot(contains('Future.delayed')));
  });

  test('background cancels only on paused or hidden and recovers on resume', () {
    final lifecycleStart = editor.indexOf(
      'void didChangeAppLifecycleState(AppLifecycleState state)',
    );
    final lifecycleEnd = editor.indexOf(
      'bool get _shouldDeferAndroidRouteRefresh',
      lifecycleStart,
    );
    final lifecycle = editor.substring(lifecycleStart, lifecycleEnd);

    expect(lifecycle, contains('_resumeIOSV2AudioAfterForeground'));
    expect(lifecycle, contains('_handleIOSV2EditorBackgrounded'));
    expect(lifecycle, contains('beginLocalInvalidationEpisode'));
    expect(lifecycle, contains('state == AppLifecycleState.paused'));
    expect(lifecycle, contains('state == AppLifecycleState.hidden'));
    final backgroundCall = lifecycle.indexOf(
      '_handleIOSV2EditorBackgrounded()',
    );
    final inactiveCondition = lifecycle.lastIndexOf(
      'state == AppLifecycleState.inactive',
      backgroundCall,
    );
    expect(inactiveCondition, lessThan(backgroundCall));
    expect(
      lifecycle.substring(inactiveCondition, backgroundCall),
      isNot(
        contains('||\n                state == AppLifecycleState.inactive'),
      ),
    );
    final resumeStart = editor.indexOf(
      'Future<void> _resumeIOSV2AudioAfterForeground()',
    );
    final resumeEnd = editor.indexOf(
      'bool get _shouldDeferAndroidRouteRefresh',
      resumeStart,
    );
    expect(
      editor.substring(resumeStart, resumeEnd),
      isNot(contains('recoverPlaybackAfterIntentInvalidation')),
    );
    expect(
      editor.substring(resumeStart, resumeEnd),
      isNot(contains('_iosV2ForegroundRecoveryPending = false')),
      reason:
          'the native foreground event must retain ownership until it starts recovery',
    );

    final handlerStart = editor.indexOf(
      'void _handleAudioRouteIntentInvalidatedV2(',
    );
    final handlerEnd = editor.indexOf(
      'String? _enterV2AudioSessionSafetyBoundary',
      handlerStart,
    );
    final handler = editor.substring(handlerStart, handlerEnd);
    expect(handler, contains('foregroundRecoveryEvent'));
    expect(handler, contains('_iosV2ForegroundRecoveryPending = false'));
    expect(handler, contains('if (cleanup != null) await cleanup'));
    expect(
      handler.indexOf('if (_v2AudioSessionInvalidated)'),
      lessThan(handler.indexOf('foregroundRecoveryEvent')),
    );
  });

  test('JUCE quiesces stream-format notifications before disposal', () {
    final closeStart = jucePolicyPatch.indexOf(
      '+                    mixroomIOSUnregisterAudioUnitPropertyOwner(this);',
    );
    final closeEnd = jucePolicyPatch.indexOf(
      'AudioComponentInstanceDispose(audioUnit);',
      closeStart,
    );
    final close = jucePolicyPatch.substring(closeStart, closeEnd);

    expect(close, contains('AudioUnitRemovePropertyListenerWithUserData'));
    expect(close, contains('AudioOutputUnitStop(audioUnit)'));
    expect(close, isNot(contains('AudioOutputUnitStart(audioUnit)')));

    final createStart = jucePolicyPatch.indexOf(
      '+            mixroomIOSRegisterAudioUnitPropertyOwner(this);',
    );
    final addListener = jucePolicyPatch.indexOf(
      'AudioUnitAddPropertyListener(audioUnit',
      createStart,
    );
    expect(createStart, isNonNegative);
    expect(createStart, lessThan(addListener));

    final dispatchStart = jucePolicyPatch.indexOf(
      'static void dispatchAudioUnitPropertyChange',
    );
    final dispatchEnd = jucePolicyPatch.indexOf('\n@@', dispatchStart);
    expect(dispatchStart, isNonNegative);
    expect(dispatchEnd, greaterThan(dispatchStart));
    final dispatch = jucePolicyPatch.substring(dispatchStart, dispatchEnd);
    expect(dispatch, contains('mixroomIOSAudioUnitPropertyMutex'));
    expect(dispatch, contains('mixroomIOSAudioUnitPropertyOwners.find(data)'));
    expect(
      dispatch.indexOf('mixroomIOSAudioUnitPropertyOwners.find(data)'),
      lessThan(dispatch.indexOf('handleAudioUnitPropertyChange')),
    );
    expect(jucePolicyPatch, isNot(contains('Future.delayed')));
  });
}
