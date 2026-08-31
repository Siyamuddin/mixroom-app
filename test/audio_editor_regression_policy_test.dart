import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/screens/audio_editor.dart';
import 'package:mixroom/screens/audio_timeline_pro.dart';

void main() {
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
