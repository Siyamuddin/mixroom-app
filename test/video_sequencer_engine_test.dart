import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/video_sequencer_engine.dart';

void main() {
  group('VideoSequencerEngine user actions', () {
    test('starts with one video track and one audio track', () {
      final engine = VideoSequencerEngine();
      expect(engine.videoTracks.length, 1);
      expect(engine.audioTracks.length, 1);
      expect(engine.tracks.length, 2);
    });

    test('addTrack creates additional tracks by type', () {
      final engine = VideoSequencerEngine();
      engine.addTrack(SequencerTrackType.video);
      engine.addTrack(SequencerTrackType.audio);
      expect(engine.videoTracks.length, 2);
      expect(engine.audioTracks.length, 2);
    });

    test('addClip targets latest track of same type', () {
      final engine = VideoSequencerEngine();
      final secondVideo = engine.addTrack(SequencerTrackType.video);
      final secondAudio = engine.addTrack(SequencerTrackType.audio);

      final videoClip = engine.addClip(
        type: SequencerTrackType.video,
        sourcePath: '/tmp/v1.mp4',
        label: 'v1',
        sourceDuration: const Duration(seconds: 3),
      );
      final audioClip = engine.addClip(
        type: SequencerTrackType.audio,
        sourcePath: '/tmp/a1.wav',
        label: 'a1',
        sourceDuration: const Duration(seconds: 2),
      );

      expect(engine.trackForClip(videoClip.id)?.id, secondVideo.id);
      expect(engine.trackForClip(audioClip.id)?.id, secondAudio.id);
    });

    test('horizontal move resolves non-overlap within track', () {
      final engine = VideoSequencerEngine();
      final first = engine.addClip(
        type: SequencerTrackType.video,
        sourcePath: '/tmp/v1.mp4',
        label: 'v1',
        sourceDuration: const Duration(seconds: 3),
        timelineStart: Duration.zero,
      );
      final second = engine.addClip(
        type: SequencerTrackType.video,
        sourcePath: '/tmp/v2.mp4',
        label: 'v2',
        sourceDuration: const Duration(seconds: 2),
        timelineStart: const Duration(seconds: 1),
      );

      engine.moveClip(second.id, Duration.zero);
      final moved = engine.videoClipById(second.id)!;
      expect(moved.timelineStart, first.timelineEnd);
    });

    test('move clip between tracks and reject wrong type target', () {
      final engine = VideoSequencerEngine();
      final clip = engine.addClip(
        type: SequencerTrackType.video,
        sourcePath: '/tmp/v1.mp4',
        label: 'v1',
        sourceDuration: const Duration(seconds: 2),
      );
      final secondVideo = engine.addTrack(SequencerTrackType.video);
      final audio = engine.audioTrack;

      final moved = engine.moveClipToTrack(clip.id, secondVideo.id);
      final rejected = engine.moveClipToTrack(clip.id, audio.id);

      expect(moved, isTrue);
      expect(rejected, isFalse);
      expect(engine.trackForClip(clip.id)?.id, secondVideo.id);
    });

    test('moveClipToNeighborTrack moves vertically by direction', () {
      final engine = VideoSequencerEngine();
      final clip = engine.addClip(
        type: SequencerTrackType.audio,
        sourcePath: '/tmp/a1.wav',
        label: 'a1',
        sourceDuration: const Duration(seconds: 2),
      );
      final source = engine.trackForClip(clip.id)!;
      engine.addTrack(SequencerTrackType.audio);

      final movedDown = engine.moveClipToNeighborTrack(clip.id, 1);
      final afterDown = engine.trackForClip(clip.id)!;
      final movedUp = engine.moveClipToNeighborTrack(clip.id, -1);
      final afterUp = engine.trackForClip(clip.id)!;

      expect(movedDown, isTrue);
      expect(afterDown.id, isNot(source.id));
      expect(movedUp, isTrue);
      expect(afterUp.id, source.id);
    });

    test('split clip at timeline point', () {
      final engine = VideoSequencerEngine();
      final clip = engine.addClip(
        type: SequencerTrackType.video,
        sourcePath: '/tmp/v1.mp4',
        label: 'v1',
        sourceDuration: const Duration(seconds: 4),
      );

      final ok = engine.splitClip(clip.id, const Duration(seconds: 2));
      final track = engine.trackForClip(clip.id)!;

      expect(ok, isTrue);
      expect(track.clips.length, 2);
      expect(track.clips[0].sourceDuration, const Duration(seconds: 2));
      expect(track.clips[1].sourceDuration, const Duration(seconds: 2));
    });

    test('trim clip updates source bounds and enforces minimum duration', () {
      final engine = VideoSequencerEngine();
      final clip = engine.addClip(
        type: SequencerTrackType.audio,
        sourcePath: '/tmp/a1.wav',
        label: 'a1',
        sourceDuration: const Duration(seconds: 5),
        sourceTotalDuration: const Duration(seconds: 10),
      );

      final ok = engine.trimClip(
        clip.id,
        newSourceStart: const Duration(seconds: 1),
        newSourceDuration: const Duration(milliseconds: 120),
      );
      final after = engine.trackForClip(clip.id)!.clips.first;

      expect(ok, isTrue);
      expect(after.sourceStart, const Duration(seconds: 1));
      expect(
        after.sourceDuration >= VideoSequencerEngine.minClipDuration,
        isTrue,
      );
    });

    test('transition requires same-track adjacency and sanitizes after move',
        () {
      final engine = VideoSequencerEngine();
      final left = engine.addClip(
        type: SequencerTrackType.video,
        sourcePath: '/tmp/v1.mp4',
        label: 'left',
        sourceDuration: const Duration(seconds: 4),
      );
      final right = engine.addClip(
        type: SequencerTrackType.video,
        sourcePath: '/tmp/v2.mp4',
        label: 'right',
        sourceDuration: const Duration(seconds: 4),
      );

      final transition = engine.addOrUpdateTransition(
        fromClipId: left.id,
        toClipId: right.id,
      );
      expect(transition, isNotNull);

      final secondVideo = engine.addTrack(SequencerTrackType.video);
      final moved = engine.moveClipToTrack(right.id, secondVideo.id);
      expect(moved, isTrue);
      expect(engine.transitionBetweenClips(left.id, right.id), isNull);

      final cannotAddCrossTrack = engine.addOrUpdateTransition(
        fromClipId: left.id,
        toClipId: right.id,
      );
      expect(cannotAddCrossTrack, isNull);
    });

    test('clipAtPlayhead picks top-most video track on overlap', () {
      final engine = VideoSequencerEngine();
      final lower = engine.addClip(
        type: SequencerTrackType.video,
        sourcePath: '/tmp/lower.mp4',
        label: 'lower',
        sourceDuration: const Duration(seconds: 3),
        timelineStart: Duration.zero,
      );
      engine.addTrack(SequencerTrackType.video);
      final upper = engine.addClip(
        type: SequencerTrackType.video,
        sourcePath: '/tmp/upper.mp4',
        label: 'upper',
        sourceDuration: const Duration(seconds: 3),
        timelineStart: Duration.zero,
      );

      engine.seek(const Duration(seconds: 1));
      final atPlayhead = engine.clipAtPlayhead(SequencerTrackType.video);

      expect(lower.id, isNot(upper.id));
      expect(atPlayhead?.id, upper.id);
    });

    test('track mute/solo audibility logic works by track id', () {
      final engine = VideoSequencerEngine();
      final video = engine.videoTrack;
      final audio = engine.audioTrack;

      expect(engine.isTrackAudibleById(video.id), isTrue);
      expect(engine.isTrackAudibleById(audio.id), isTrue);

      engine.setTrackMuted(video.id, true);
      expect(engine.isTrackAudibleById(video.id), isFalse);
      expect(engine.isTrackAudibleById(audio.id), isTrue);

      engine.setTrackSolo(audio.id, true);
      expect(engine.isTrackAudibleById(audio.id), isTrue);
      expect(engine.isTrackAudibleById(video.id), isFalse);

      engine.setTrackSolo(audio.id, false);
      engine.setTrackMuted(video.id, false);
      expect(engine.isTrackAudibleById(video.id), isTrue);
    });

    test('removeTrack rehomes clips and keeps one minimum track per type', () {
      final engine = VideoSequencerEngine();
      final baseVideo = engine.videoTrack;
      engine.addClip(
        type: SequencerTrackType.video,
        sourcePath: '/tmp/v1.mp4',
        label: 'v1',
        sourceDuration: const Duration(seconds: 2),
      );
      final secondVideo = engine.addTrack(SequencerTrackType.video);
      final movedClip = engine.addClip(
        type: SequencerTrackType.video,
        sourcePath: '/tmp/v2.mp4',
        label: 'v2',
        sourceDuration: const Duration(seconds: 2),
      );
      expect(engine.trackForClip(movedClip.id)?.id, secondVideo.id);

      final removed = engine.removeTrack(secondVideo.id);
      expect(removed, isTrue);
      expect(engine.videoTracks.length, 1);
      expect(engine.trackForClip(movedClip.id)?.id, baseVideo.id);

      final cannotRemoveLastVideo = engine.removeTrack(baseVideo.id);
      expect(cannotRemoveLastVideo, isFalse);
    });

    test('snapshot roundtrip preserves track solo/mute state', () {
      final engine = VideoSequencerEngine();
      final v2 = engine.addTrack(SequencerTrackType.video);
      engine.setTrackSolo(v2.id, true);
      engine.setTrackMuted(engine.audioTrack.id, true);

      final restored = VideoSequencerEngine(initial: engine.toSnapshot());
      final restoredV2 = restored.tracks
          .firstWhere((t) => t.id == v2.id, orElse: () => restored.videoTrack);
      final restoredAudio = restored.audioTrack;

      expect(restoredV2.solo, isTrue);
      expect(restoredAudio.muted, isTrue);
    });
  });
}
