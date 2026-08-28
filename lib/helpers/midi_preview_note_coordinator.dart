import 'dart:async';

enum MidiPreviewNoteOnResult { delivered, failed, cancelled }

class MidiPreviewNoteKey {
  const MidiPreviewNoteKey({
    required this.clipId,
    required this.channel,
    required this.pitch,
  });

  final int clipId;
  final int channel;
  final int pitch;

  @override
  bool operator ==(Object other) =>
      other is MidiPreviewNoteKey &&
      other.clipId == clipId &&
      other.channel == channel &&
      other.pitch == pitch;

  @override
  int get hashCode => Object.hash(clipId, channel, pitch);
}

/// Keeps asynchronous live-MIDI preparation from delivering a note-on after
/// the matching pointer/key has already been released.
class MidiPreviewNoteCoordinator {
  final Map<MidiPreviewNoteKey, int> _pendingTokens =
      <MidiPreviewNoteKey, int>{};
  final Set<MidiPreviewNoteKey> _soundingNotes = <MidiPreviewNoteKey>{};
  final Map<MidiPreviewNoteKey, Future<void>> _noteOnOperations =
      <MidiPreviewNoteKey, Future<void>>{};
  int _nextToken = 0;

  bool _isCurrent(MidiPreviewNoteKey key, int token) =>
      _pendingTokens[key] == token;

  Future<MidiPreviewNoteOnResult> noteOn({
    required MidiPreviewNoteKey key,
    required Future<bool> Function() prepare,
    required Future<bool> Function() sendNoteOn,
    required Future<bool> Function() sendNoteOff,
  }) {
    final token = ++_nextToken;
    _pendingTokens[key] = token;
    final previousOperation = _noteOnOperations[key] ?? Future<void>.value();

    final operation = _deliverNoteOn(
      key: key,
      token: token,
      previousOperation: previousOperation,
      prepare: prepare,
      sendNoteOn: sendNoteOn,
      sendNoteOff: sendNoteOff,
    );
    final completion = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _noteOnOperations[key] = completion;
    unawaited(
      completion.whenComplete(() {
        if (identical(_noteOnOperations[key], completion)) {
          _noteOnOperations.remove(key);
        }
      }),
    );
    return operation;
  }

  Future<MidiPreviewNoteOnResult> _deliverNoteOn({
    required MidiPreviewNoteKey key,
    required int token,
    required Future<void> previousOperation,
    required Future<bool> Function() prepare,
    required Future<bool> Function() sendNoteOn,
    required Future<bool> Function() sendNoteOff,
  }) async {
    await previousOperation;
    if (!_isCurrent(key, token)) {
      return MidiPreviewNoteOnResult.cancelled;
    }

    final prepared = await prepare();
    if (!_isCurrent(key, token)) {
      return MidiPreviewNoteOnResult.cancelled;
    }
    if (!prepared) {
      _pendingTokens.remove(key);
      return MidiPreviewNoteOnResult.failed;
    }

    final sent = await sendNoteOn();
    if (!sent) {
      final wasCurrent = _isCurrent(key, token);
      if (wasCurrent) {
        _pendingTokens.remove(key);
      }
      return wasCurrent
          ? MidiPreviewNoteOnResult.failed
          : MidiPreviewNoteOnResult.cancelled;
    }

    if (!_isCurrent(key, token)) {
      // A release raced the platform-channel response. The native note-on may
      // already be queued, so send a second note-off after it.
      await sendNoteOff();
      return MidiPreviewNoteOnResult.cancelled;
    }

    _pendingTokens.remove(key);
    _soundingNotes.add(key);
    return MidiPreviewNoteOnResult.delivered;
  }

  Future<bool> noteOff({
    required MidiPreviewNoteKey key,
    required Future<bool> Function() sendNoteOff,
  }) async {
    _pendingTokens.remove(key);
    final sent = await sendNoteOff();
    if (sent) {
      _soundingNotes.remove(key);
    }
    return sent;
  }

  Future<void> releaseAll({
    required Future<bool> Function(MidiPreviewNoteKey key) sendNoteOff,
  }) async {
    final notes = <MidiPreviewNoteKey>{
      ..._pendingTokens.keys,
      ..._soundingNotes,
    }.toList(growable: false);
    _pendingTokens.clear();

    for (final key in notes) {
      final sent = await sendNoteOff(key);
      if (sent) {
        _soundingNotes.remove(key);
      }
    }
  }
}
