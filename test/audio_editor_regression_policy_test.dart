import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/screens/audio_editor.dart';

void main() {
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
