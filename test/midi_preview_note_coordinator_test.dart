import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/midi_preview_note_coordinator.dart';

void main() {
  const key = MidiPreviewNoteKey(clipId: 7, channel: 1, pitch: 60);

  test(
    'release while preparation is pending suppresses the late note-on',
    () async {
      final coordinator = MidiPreviewNoteCoordinator();
      final ready = Completer<bool>();
      final events = <String>[];

      final noteOn = coordinator.noteOn(
        key: key,
        prepare: () => ready.future,
        sendNoteOn: () async {
          events.add('on');
          return true;
        },
        sendNoteOff: () async {
          events.add('compensating-off');
          return true;
        },
      );

      await coordinator.noteOff(
        key: key,
        sendNoteOff: () async {
          events.add('off');
          return true;
        },
      );
      ready.complete(true);

      expect(await noteOn, MidiPreviewNoteOnResult.cancelled);
      expect(events, <String>['off']);
    },
  );

  test(
    'release during note-on delivery sends a compensating note-off',
    () async {
      final coordinator = MidiPreviewNoteCoordinator();
      final noteOnDelivered = Completer<bool>();
      final events = <String>[];

      final noteOn = coordinator.noteOn(
        key: key,
        prepare: () async => true,
        sendNoteOn: () async {
          events.add('on-start');
          return noteOnDelivered.future;
        },
        sendNoteOff: () async {
          events.add('compensating-off');
          return true;
        },
      );
      await Future<void>.delayed(Duration.zero);

      await coordinator.noteOff(
        key: key,
        sendNoteOff: () async {
          events.add('off');
          return true;
        },
      );
      noteOnDelivered.complete(true);

      expect(await noteOn, MidiPreviewNoteOnResult.cancelled);
      expect(events, <String>['on-start', 'off', 'compensating-off']);
    },
  );

  test(
    'releaseAll invalidates pending notes and silences delivered notes',
    () async {
      final coordinator = MidiPreviewNoteCoordinator();
      const secondKey = MidiPreviewNoteKey(clipId: 7, channel: 1, pitch: 62);
      final pendingReady = Completer<bool>();
      final released = <MidiPreviewNoteKey>[];

      expect(
        await coordinator.noteOn(
          key: key,
          prepare: () async => true,
          sendNoteOn: () async => true,
          sendNoteOff: () async => true,
        ),
        MidiPreviewNoteOnResult.delivered,
      );
      final pendingNoteOn = coordinator.noteOn(
        key: secondKey,
        prepare: () => pendingReady.future,
        sendNoteOn: () async => true,
        sendNoteOff: () async => true,
      );

      await coordinator.releaseAll(
        sendNoteOff: (note) async {
          released.add(note);
          return true;
        },
      );
      pendingReady.complete(true);

      expect(await pendingNoteOn, MidiPreviewNoteOnResult.cancelled);
      expect(released, containsAll(<MidiPreviewNoteKey>[key, secondKey]));
    },
  );

  test(
    'retrigger waits for an older in-flight note-on to be compensated',
    () async {
      final coordinator = MidiPreviewNoteCoordinator();
      final firstDelivered = Completer<bool>();
      final events = <String>[];

      final first = coordinator.noteOn(
        key: key,
        prepare: () async => true,
        sendNoteOn: () async {
          events.add('first-on');
          return firstDelivered.future;
        },
        sendNoteOff: () async {
          events.add('first-off');
          return true;
        },
      );
      await Future<void>.delayed(Duration.zero);

      final second = coordinator.noteOn(
        key: key,
        prepare: () async => true,
        sendNoteOn: () async {
          events.add('second-on');
          return true;
        },
        sendNoteOff: () async => true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, <String>['first-on']);

      firstDelivered.complete(true);
      expect(await first, MidiPreviewNoteOnResult.cancelled);
      expect(await second, MidiPreviewNoteOnResult.delivered);
      expect(events, <String>['first-on', 'first-off', 'second-on']);
    },
  );
}
