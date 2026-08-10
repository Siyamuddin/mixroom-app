import 'package:flutter/foundation.dart';

typedef MidiPreviewStep = Future<bool> Function();

bool midiPreviewNeedsPlaybackReadiness(
  TargetPlatform platform, {
  required bool isBluetoothV2Session,
}) =>
    platform == TargetPlatform.android ||
    platform == TargetPlatform.iOS ||
    (platform == TargetPlatform.macOS && isBluetoothV2Session);

/// Runs the bounded readiness sequence required before a live MIDI preview.
Future<bool> ensureMidiPreviewReady({
  required MidiPreviewStep prepareRoute,
  required MidiPreviewStep updateProcessor,
  required MidiPreviewStep reloadProcessor,
  required MidiPreviewStep assignLiveTarget,
  required bool Function() isStillValid,
}) async {
  if (!isStillValid() || !await prepareRoute() || !isStillValid()) return false;

  if (await assignLiveTarget()) return isStillValid();
  if (!isStillValid()) return false;

  var reloaded = false;
  var processorReady = await updateProcessor();
  if (!processorReady) {
    reloaded = true;
    processorReady = await reloadProcessor();
  }
  if (!processorReady || !isStillValid()) return false;

  if (await assignLiveTarget()) return isStillValid();
  if (reloaded || !isStillValid()) return false;

  if (!await reloadProcessor() || !isStillValid()) return false;
  return await assignLiveTarget() && isStillValid();
}
