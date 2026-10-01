import 'dart:async';

import 'package:flutter/foundation.dart';

import 'voice_command_journal.dart';
import 'voice_protocol.dart';
import 'voice_relay_transport.dart';

typedef VoiceCommandHandler = Future<VoiceResult> Function(
  VoiceCommand command,
);

/// The relay carries messages; this controller is the sole native command owner.
class VoiceSessionController extends ChangeNotifier {
  VoiceSessionController({
    required this.transport,
    required this.journal,
    required this.stateProvider,
    required this.commandHandler,
    required this.onDisconnect,
    this.onEmergencyStop,
    this.pollInterval = const Duration(milliseconds: 800),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final VoiceRelayTransport transport;
  final VoiceCommandJournal journal;
  final Map<String, dynamic> Function() stateProvider;
  final VoiceCommandHandler commandHandler;
  final Future<void> Function() onDisconnect;
  final void Function(String captureId)? onEmergencyStop;
  final Duration pollInterval;
  final DateTime Function() _clock;
  String? sessionId;
  String? _deviceToken;
  String? activeCommandId;
  String? captureReadyId;
  String? cancelledCaptureId;
  String? error;
  bool browserConnected = false;
  bool _polling = false;
  bool _disposed = false;
  int _connectionGeneration = 0;
  Timer? _timer;
  final Map<String, Map<String, dynamic>> _pendingResults = {};

  bool get connected => sessionId != null && _deviceToken != null;
  bool get busy => activeCommandId != null;

  Future<void> pair(String code, {String deviceName = 'MixRoom macOS'}) async {
    if (connected || busy) throw StateError('voice_session_already_connected');
    await journal.load();
    _pendingResults.clear();
    final response = await transport.request(
      'POST',
      '/pairing/claim',
      body: {'pairingCode': code.trim(), 'deviceName': deviceName},
    );
    final id = response['sessionId'];
    final token = response['deviceToken'];
    if (id is! String || id.isEmpty || token is! String || token.isEmpty) {
      throw const FormatException('Invalid pairing response.');
    }
    sessionId = id;
    _deviceToken = token;
    _connectionGeneration++;
    error = null;
    _notify();
    _timer = Timer.periodic(pollInterval, (_) => unawaited(poll()));
    await publishState();
    unawaited(poll());
  }

  Future<void> publishState() async {
    if (!connected) return;
    final state = stateProvider();
    await transport.request(
      'PUT',
      '/sessions/$sessionId/state',
      token: _deviceToken,
      body: {
        'projectSessionId': state['projectSessionId'],
        'projectRevision': state['projectRevision'],
        'state': state['state'],
      },
    );
  }

  Future<void> poll() async {
    if (_polling || !connected || _disposed) return;
    _polling = true;
    final generation = _connectionGeneration;
    final polledSessionId = sessionId;
    final polledToken = _deviceToken;
    try {
      await publishState();
      if (generation != _connectionGeneration || !connected) return;
      for (final entry in _pendingResults.entries.toList()) {
        await transport.request(
          'POST',
          '/sessions/$polledSessionId/results',
          token: polledToken,
          body: entry.value,
        );
        if (generation != _connectionGeneration || !connected) return;
        _pendingResults.remove(entry.key);
      }
      final response = await transport.request(
        'GET',
        '/sessions/$polledSessionId/poll',
        token: polledToken,
      );
      if (generation != _connectionGeneration || !connected) return;
      captureReadyId = response['captureReadyId'] as String?;
      if (response['stopRequested'] == true &&
          response['cancelCaptureId'] is String) {
        cancelCapture(response['cancelCaptureId'] as String);
      }
      final wasBrowserConnected = browserConnected;
      browserConnected = response['browserConnected'] == true;
      if (wasBrowserConnected && !browserConnected) await onDisconnect();
      error = null;
      final command = response['command'];
      if (command is Map && !busy) {
        unawaited(
          execute(VoiceCommand.fromJson(Map<String, dynamic>.from(command))),
        );
      }
    } catch (failure) {
      if (generation != _connectionGeneration || !connected) return;
      if (failure is VoiceRelayException &&
          const {401, 403, 404, 410}.contains(failure.statusCode)) {
        // A fresh local database or expired session requires a new pairing.
        // Never move pending receipts or commands into that replacement session.
        try {
          await disconnect();
        } catch (_) {}
        error = 'This voice session ended. Connect with a new pairing code.';
        return;
      }
      error = 'Connection interrupted. Reconnecting without repeating edits.';
      browserConnected = false;
      captureReadyId = null;
      try {
        await onDisconnect();
      } catch (_) {}
    } finally {
      _polling = false;
      _notify();
    }
  }

  Future<VoiceResult> execute(VoiceCommand command) async {
    await journal.load();
    final existing = journal.lookup(command);
    if (existing != null) {
      if (existing.status != 'running') _queueResult(command, existing);
      return existing;
    }
    if (busy)
      return const VoiceResult('rejected', 'Another request is running.');
    final snapshot = stateProvider();
    VoiceResult? rejection;
    if (!connected || command.sessionId != sessionId) {
      rejection = const VoiceResult(
        'rejected',
        'This voice session is no longer connected.',
      );
    } else if (!_clock().toUtc().isBefore(command.expiresAt)) {
      rejection = const VoiceResult(
        'rejected',
        'This request expired before it could run.',
      );
    } else if (command.projectSessionId != snapshot['projectSessionId']) {
      rejection = const VoiceResult(
        'rejected',
        'The project changed. Ask again in the current project.',
      );
    } else if (command.expectedRevision != null &&
        command.expectedRevision != snapshot['projectRevision']) {
      rejection = const VoiceResult(
        'rejected',
        'The project changed since this request. Please ask again.',
      );
    }
    activeCommandId = command.id;
    _notify();
    try {
      await journal.begin(command);
      final result = rejection ?? await commandHandler(command);
      await journal.complete(command, result);
      _queueResult(command, result);
      return result;
    } catch (_) {
      const result = VoiceResult(
        'failed',
        'The request did not finish. Check the project before retrying.',
      );
      try {
        await journal.complete(command, result);
      } catch (_) {}
      _queueResult(command, result);
      return result;
    } finally {
      activeCommandId = null;
      _notify();
      unawaited(poll());
    }
  }

  void _queueResult(VoiceCommand command, VoiceResult result) {
    if (command.sessionId != sessionId || !connected) return;
    final succeeded = const {
      'verified',
      'succeeded',
      'respond',
      'clarify',
      'unsupported',
    }.contains(result.status);
    _pendingResults[command.id] = {
      'commandId': command.id,
      'status': succeeded
          ? 'succeeded'
          : result.status == 'rejected'
          ? 'rejected'
          : 'failed',
      'message': result.message,
      'state': stateProvider()['state'],
      'details': {'nativeStatus': result.status, ...result.data},
    };
  }

  Future<Map<String, dynamic>> plan(Map<String, dynamic> request) {
    if (!connected || activeCommandId == null)
      throw StateError('voice_planner_not_paired');
    return transport.request(
      'POST',
      '/sessions/$sessionId/planner',
      token: _deviceToken,
      body: {
        'commandId': activeCommandId,
        'request': request,
        'sessionState': stateProvider()['state'],
      },
    );
  }

  Future<bool> waitForCaptureReady(
    String id, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = _clock().add(timeout);
    while (connected && !_disposed && _clock().isBefore(deadline)) {
      if (cancelledCaptureId == id) return false;
      if (captureReadyId == id && browserConnected) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  void cancelCapture(String id) {
    cancelledCaptureId = id;
    onEmergencyStop?.call(id);
  }

  Future<void> disconnect() async {
    _connectionGeneration++;
    _timer?.cancel();
    _timer = null;
    sessionId = null;
    _deviceToken = null;
    captureReadyId = null;
    cancelledCaptureId = null;
    browserConnected = false;
    _pendingResults.clear();
    await onDisconnect();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _connectionGeneration++;
    _disposed = true;
    _timer?.cancel();
    sessionId = null;
    _deviceToken = null;
    transport.close();
    super.dispose();
  }
}
