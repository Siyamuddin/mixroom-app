import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/v3/ai_v3_context.dart';
import 'package:mixroom/ai/v3/ai_v3_contract.dart';
import 'package:mixroom/voice/voice_command_journal.dart';
import 'package:mixroom/voice/voice_project_notes.dart';
import 'package:mixroom/voice/voice_protocol.dart';
import 'package:mixroom/voice/voice_relay_planner.dart';
import 'package:mixroom/voice/voice_relay_transport.dart';
import 'package:mixroom/voice/voice_session_controller.dart';

class _Relay implements VoiceRelayTransport {
  bool failPoll = false;
  int pollFailureStatus = 503;
  String pairedSessionId = 'session';
  Map<String, dynamic> pollResponse = {
    'command': null,
    'browserConnected': true,
  };
  final List<Map<String, dynamic>> results = [];
  final List<Map<String, dynamic>> states = [];
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    if (path == '/pairing/claim')
      return {'sessionId': pairedSessionId, 'deviceToken': 'test-token'};
    if (path.endsWith('/state')) states.add(body!);
    if (path.endsWith('/results')) results.add(body!);
    if (path.endsWith('/poll')) {
      if (failPoll) throw VoiceRelayException(pollFailureStatus);
      return pollResponse;
    }
    return {};
  }

  @override
  void close() {}
}

final _now = DateTime.utc(2026, 10, 1, 5);
VoiceCommand _command(
  String id, {
  String text = 'Lower the vocal by 3 dB',
  int revision = 1,
  String project = 'project',
  DateTime? expiry,
}) => VoiceCommand(
  id: id,
  sessionId: 'session',
  projectSessionId: project,
  kind: 'utterance',
  arguments: {'text': text},
  expectedRevision: revision,
  expiresAt: expiry ?? _now.add(const Duration(minutes: 2)),
);

void main() {
  test(
    'lost local session requires pairing and never replays running work',
    () async {
      final relay = _Relay();
      final started = Completer<void>();
      final finish = Completer<void>();
      var calls = 0;
      var disconnects = 0;
      final controller = VoiceSessionController(
        transport: relay,
        journal: VoiceCommandJournal(),
        clock: () => _now,
        pollInterval: const Duration(hours: 1),
        stateProvider: () => {
          'projectSessionId': 'project',
          'projectRevision': 1,
          'state': {},
        },
        commandHandler: (_) async {
          calls++;
          started.complete();
          await finish.future;
          return const VoiceResult('verified', 'Saved locally.');
        },
        onDisconnect: () async {
          disconnects++;
        },
      );
      addTearDown(controller.dispose);
      await controller.pair('123456');
      await Future<void>.delayed(Duration.zero);
      final running = controller.execute(_command('one'));
      await started.future;
      relay.failPoll = true;
      relay.pollFailureStatus = 404;
      await controller.poll();
      expect(controller.connected, isFalse);
      expect(controller.error, contains('new pairing code'));
      expect(disconnects, 1);
      finish.complete();
      await running;
      relay.failPoll = false;
      relay.pairedSessionId = 'replacement-session';
      await controller.pair('654321');
      await Future<void>.delayed(Duration.zero);
      expect((await controller.execute(_command('one'))).status, 'verified');
      await controller.poll();
      expect(calls, 1);
      expect(relay.results, isEmpty);
    },
  );

  test('network loss restores the last committed native state', () async {
    final relay = _Relay();
    var restores = 0;
    final controller = VoiceSessionController(
      transport: relay,
      journal: VoiceCommandJournal(),
      clock: () => _now,
      pollInterval: const Duration(hours: 1),
      stateProvider: () => {
        'projectSessionId': 'project',
        'projectRevision': 1,
        'state': {},
      },
      commandHandler: (_) async => const VoiceResult('verified', 'Done.'),
      onDisconnect: () async {
        restores++;
      },
    );
    addTearDown(controller.dispose);
    await controller.pair('123456');
    await Future<void>.delayed(Duration.zero);
    relay.failPoll = true;
    await controller.poll();
    expect(restores, 1);
    expect(controller.browserConnected, isFalse);
    expect(controller.error, isNotNull);
  });

  test('emergency stop cancels microphone readiness immediately', () async {
    final relay = _Relay();
    String? stopped;
    final controller = VoiceSessionController(
      transport: relay,
      journal: VoiceCommandJournal(),
      clock: () => _now,
      pollInterval: const Duration(hours: 1),
      stateProvider: () => {
        'projectSessionId': 'project',
        'projectRevision': 1,
        'state': {},
      },
      commandHandler: (_) async => const VoiceResult('verified', 'Done.'),
      onDisconnect: () async {},
      onEmergencyStop: (id) => stopped = id,
    );
    addTearDown(controller.dispose);
    await controller.pair('123456');
    await Future<void>.delayed(Duration.zero);
    final ready = controller.waitForCaptureReady('capture-to-stop');
    relay.pollResponse = {
      'command': null,
      'browserConnected': true,
      'stopRequested': true,
      'cancelCaptureId': 'capture-to-stop',
    };
    await controller.poll();
    expect(await ready, isFalse);
    expect(stopped, 'capture-to-stop');
  });

  test('capture duration defaults, bars and upper bound are explicit', () {
    expect(
      voiceCaptureDuration({}, bpm: 120, beatsPerBar: 4),
      const Duration(seconds: 10),
    );
    expect(
      voiceCaptureDuration({'bars': 4}, bpm: 120, beatsPerBar: 4),
      const Duration(seconds: 8),
    );
    expect(
      voiceCaptureDuration({'bars': 4}, bpm: 120, beatsPerBar: 6, beatUnit: 8),
      const Duration(seconds: 6),
    );
    expect(
      () => voiceCaptureDuration(
        {'duration_seconds': 61},
        bpm: 120,
        beatsPerBar: 4,
      ),
      throwsFormatException,
    );
    expect(
      () => voiceCaptureDuration(
        {'duration_seconds': 10, 'bars': 4},
        bpm: 120,
        beatsPerBar: 4,
      ),
      throwsFormatException,
    );
    expect(
      () => voiceCaptureDuration(
        {'duration_seconds': double.nan},
        bpm: 120,
        beatsPerBar: 4,
      ),
      throwsFormatException,
    );
  });

  test('journal survives restart and refuses interrupted work', () async {
    final directory = await Directory.systemTemp.createTemp(
      'mixroom-voice-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/journal.json');
    final first = VoiceCommandJournal(file: file);
    await first.load();
    await first.begin(_command('one'));
    final restarted = VoiceCommandJournal(file: file);
    await restarted.load();
    expect(restarted.lookup(_command('one'))!.status, 'outcome_unknown');
    expect(
      restarted.lookup(_command('one', text: 'Delete everything'))!.status,
      'rejected',
    );
  });

  test('completed command keeps its exact receipt across restart', () async {
    final directory = await Directory.systemTemp.createTemp(
      'mixroom-voice-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/journal.json');
    final first = VoiceCommandJournal(file: file);
    await first.load();
    await first.begin(_command('one'));
    await first.complete(
      _command('one'),
      const VoiceResult('verified', 'Reduced vocal by 3 dB.'),
    );
    final second = VoiceCommandJournal(file: file);
    await second.load();
    expect(second.lookup(_command('one'))!.message, 'Reduced vocal by 3 dB.');
  });

  test('duplicate relative-gain command executes once', () async {
    final relay = _Relay();
    var gain = 0.0;
    final controller = VoiceSessionController(
      transport: relay,
      journal: VoiceCommandJournal(),
      clock: () => _now,
      pollInterval: const Duration(hours: 1),
      stateProvider: () => {
        'projectSessionId': 'project',
        'projectRevision': 1,
        'state': {'busy': false},
      },
      commandHandler: (_) async {
        gain -= 3;
        return const VoiceResult('verified', 'Applied.');
      },
      onDisconnect: () async {},
    );
    addTearDown(controller.dispose);
    await controller.pair('123456');
    expect((await controller.execute(_command('one'))).status, 'verified');
    expect((await controller.execute(_command('one'))).status, 'verified');
    expect(gain, -3);
  });

  test('stale project, revision and expired requests never execute', () async {
    var calls = 0;
    final controller = VoiceSessionController(
      transport: _Relay(),
      journal: VoiceCommandJournal(),
      clock: () => _now,
      pollInterval: const Duration(hours: 1),
      stateProvider: () => {
        'projectSessionId': 'project',
        'projectRevision': 1,
        'state': {},
      },
      commandHandler: (_) async {
        calls++;
        return const VoiceResult('verified', 'Done.');
      },
      onDisconnect: () async {},
    );
    addTearDown(controller.dispose);
    await controller.pair('123456');
    expect(
      (await controller.execute(_command('project', project: 'other'))).status,
      'rejected',
    );
    expect(
      (await controller.execute(_command('revision', revision: 0))).status,
      'rejected',
    );
    expect(
      (await controller.execute(_command('expired', expiry: _now))).status,
      'rejected',
    );
    expect(calls, 0);
  });

  test('capture readiness polling stays live during a long command', () async {
    final relay = _Relay();
    final started = Completer<void>();
    final finish = Completer<void>();
    final controller = VoiceSessionController(
      transport: relay,
      journal: VoiceCommandJournal(),
      clock: () => _now,
      pollInterval: const Duration(hours: 1),
      stateProvider: () => {
        'projectSessionId': 'project',
        'projectRevision': 1,
        'state': {},
      },
      commandHandler: (_) async {
        started.complete();
        await finish.future;
        return const VoiceResult('verified', 'Saved.');
      },
      onDisconnect: () async {},
    );
    addTearDown(controller.dispose);
    await controller.pair('123456');
    await Future<void>.delayed(Duration.zero);
    final running = controller.execute(_command('capture'));
    await started.future;
    relay.pollResponse = {
      'command': null,
      'browserConnected': true,
      'captureReadyId': 'capture-id',
    };
    await controller.poll();
    expect(await controller.waitForCaptureReady('capture-id'), isTrue);
    expect(controller.busy, isTrue);
    finish.complete();
    await running;
  });

  test(
    'notes persist within the selected project and complete by ID',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mixroom-voice-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final notes = VoiceProjectNotes(File('${directory.path}/notes.json'));
      final note = await notes.add(
        'Make the chorus warmer',
        playheadMs: 4200,
        projectId: 'project-one',
        trackId: 42,
      );
      expect((await notes.list()).single['playheadMs'], 4200);
      final reopened = VoiceProjectNotes(File('${directory.path}/notes.json'));
      expect((await reopened.list()).single['projectId'], 'project-one');
      expect((await reopened.list()).single['trackId'], 42);
      expect(await notes.complete(note['id'] as String), isTrue);
      expect((await notes.list()).single['completed'], isTrue);
      expect(await notes.complete('missing'), isFalse);
    },
  );

  test(
    'session-action planner has no invented success message or DAW edits',
    () async {
      Map<String, dynamic>? received;
      final planner = VoiceRelayPlanner(
        request: (_) async => {
          'kind': 'session_action',
          'action': {
            'type': 'notes.add',
            'arguments': {'text': 'Check the bass'},
          },
        },
        onResponse: (value) => received = value,
      );
      final result = await planner.plan(
        context: const AiV3CoreContext(
          profile: AiV3ContextProfile.essential,
          stateDigest: 'digest',
          data: {},
        ),
        originalRequest: 'Remember to check the bass',
      );
      expect(result.plan.commands, isEmpty);
      expect(result.plan.userMessage, isEmpty);
      expect(received!['kind'], 'session_action');
    },
  );

  test('planner rejects unknown commands instead of forwarding them', () async {
    final planner = VoiceRelayPlanner(
      request: (_) async => {
        'kind': 'daw_plan',
        'response': {
          'schema_version': 'v3_plan_response_server_v1',
          'plan': {
            'schema_version': aiV3PlanVersion,
            'outcome': 'plan',
            'user_message': '',
            'question_options': [],
            'commands': [
              {'command_id': 'bad', 'type': 'shell.execute', 'arguments': {}},
            ],
          },
        },
      },
      onResponse: (_) {},
    );
    expect(
      () => planner.plan(
        context: const AiV3CoreContext(
          profile: AiV3ContextProfile.essential,
          stateDigest: 'digest',
          data: {},
        ),
        originalRequest: 'Bad command',
      ),
      throwsA(isA<AiV3ContractException>()),
    );
  });
}
