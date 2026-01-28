import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class JuceAudioEngine {
  static const _ch = MethodChannel('juce_audio_engine');
  static const _eventCh = EventChannel('juce_audio_engine/events');

  static Stream<Map<String, dynamic>> get _events =>
      _eventCh.receiveBroadcastStream().cast<Map<dynamic, dynamic>>().map((e) => Map<String, dynamic>.from(e));

  static void initialiseEventListeners() {
    _events.listen((event) {
      if (event['event'] == 'pluginLoaded') {
        final track = event['track'] as int;
        final path = event['path'] as String;
        final success = event['success'] as bool;
        print("Plugin loaded: $success for $path on track $track");
      }
    });
  }

  // -------------------------------
  // Helpers
  // -------------------------------
  static void _logError(String method, Object error) {
    print('JuceAudioEngine.$method failed: $error');
  }

  // -------------------------------
  // Platform version (for tests)
  // -------------------------------
  Future<String?> getPlatformVersion() async {
    try {
      return await _ch.invokeMethod<String>('getPlatformVersion');
    } on PlatformException catch (e) {
      _logError('getPlatformVersion', e);
      return null;
    }
  }

  // -------------------------------
  // Core controls
  // -------------------------------
  static Future<void> initialise() async {
    try {
      await _ch.invokeMethod('initialise');
    } on PlatformException catch (e) {
      _logError('initialise', e);
    }
  }

  static Future<void> shutdown() async {
    try {
      await _ch.invokeMethod('shutdown');
    } on PlatformException catch (e) {
      _logError('shutdown', e);
    }
  }

  // DEPRECATED – prefer loadClip()
  static Future<void> loadTrack(int index, String path) async {
    try {
      await _ch.invokeMethod('loadTrack', {'index': index, 'path': path});
    } on PlatformException catch (e) {
      _logError('loadTrack', e);
    }
  }

  static Future<void> play() async {
    try {
      await _ch.invokeMethod('play');
    } on PlatformException catch (e) {
      _logError('play', e);
    }
  }

  static Future<void> pause() async {
    try {
      await _ch.invokeMethod('pause');
    } on PlatformException catch (e) {
      _logError('pause', e);
    }
  }

  /// Bypass (freeze) or un-bypass (resume) a single track.
  static Future<void> bypassTrack(int track, bool shouldBypass) async {
    try {
      await _ch.invokeMethod('bypassTrack', {
        'track': track,
        'bypass': shouldBypass,
      });
    } on PlatformException catch (e) {
      print('bypassTrack failed: $e');
    }
  }

  // -------------------------------
  // Track / clip management (legacy)
  // -------------------------------
  static Future<void> removeTrack(int track) async {
    try {
      await _ch.invokeMethod('removeTrack', {'track': track});
    } on PlatformException catch (e) {
      _logError('removeTrack', e);
    }
  }

  static Future<void> seek(int track, double position) async {
    try {
      await _ch.invokeMethod('seek', {
        'track': track,
        'position': position,
      });
    } on PlatformException catch (e) {
      _logError('seek', e);
    }
  }

  static Future<double> getCurrentPosition(int track) async {
    try {
      final pos = await _ch.invokeMethod<double>(
        'getCurrentPosition',
        {'track': track},
      );
      return pos ?? 0.0;
    } on PlatformException catch (e) {
      _logError('getCurrentPosition', e);
      return 0.0;
    }
  }

  static Future<double> getTrackDuration(int track) async {
    try {
      final dur = await _ch.invokeMethod<double>(
        'getTrackDuration',
        {'track': track},
      );
      return dur ?? 0.0;
    } on PlatformException catch (e) {
      _logError('getTrackDuration', e);
      return 0.0;
    }
  }

  // -------------------------------
  // Effects management (clip-level)
  // -------------------------------
  static Future<void> insertEffect(int track, String path) async {
    try {
      await _ch.invokeMethod('insertEffect', {'track': track, 'path': path});
    } on PlatformException catch (e) {
      _logError('insertEffect', e);
    }
  }

  static Future<void> removeEffect(int track, int effect) async {
    try {
      await _ch.invokeMethod('removeEffect', {
        'track': track,
        'effect': effect,
      });
    } on PlatformException catch (e) {
      _logError('removeEffect', e);
    }
  }

  static Future<void> reorderEffects(
    int track,
    int from,
    int to,
  ) async {
    try {
      await _ch.invokeMethod('reorderEffects', {
        'track': track,
        'from': from,
        'to': to,
      });
    } on PlatformException catch (e) {
      _logError('reorderEffects', e);
    }
  }

  static Future<List<String>> getTrackEffects(int track) async {
    final list = await _ch.invokeListMethod<String>(
      'getTrackEffects',
      {'track': track},
    );
    return list ?? <String>[];
  }

  static Future<List<Map<String, dynamic>>> getPluginParameters(
    int trackIndex,
    int effectIndex,
  ) async {
    try {
      final rawList = await _ch.invokeMethod<List<dynamic>>(
        'getPluginParameters',
        {'track': trackIndex, 'effect': effectIndex},
      );
      if (rawList == null) return [];

      return rawList.map((item) {
        return Map<String, dynamic>.from(item as Map);
      }).toList();
    } on PlatformException catch (e) {
      _logError('getPluginParameters', e);
      return <Map<String, dynamic>>[];
    }
  }

  static Future<List<Map<String, dynamic>>> getTrackPluginParameters(
    int row,
    int effectIndex,
  ) async {
    try {
      final rawList = await _ch.invokeMethod<List<dynamic>>(
        'getTrackPluginParameters',
        {'row': row, 'effect': effectIndex},
      );
      if (rawList == null) return [];

      return rawList.map((item) {
        return Map<String, dynamic>.from(item as Map);
      }).toList();
    } on PlatformException catch (e) {
      _logError('getTrackPluginParameters', e);
      return <Map<String, dynamic>>[];
    }
  }

  static Future<List<Map<String, dynamic>>> getMasterPluginParameters(
    int effectIndex,
  ) async {
    try {
      final rawList = await _ch.invokeMethod<List<dynamic>>(
        'getMasterPluginParameters',
        {'effect': effectIndex},
      );
      if (rawList == null) return [];

      return rawList.map((item) {
        return Map<String, dynamic>.from(item as Map);
      }).toList();
    } on PlatformException catch (e) {
      _logError('getMasterPluginParameters', e);
      return <Map<String, dynamic>>[];
    }
  }

  // DEPRECATED – use setTrackEffect / setMasterEffect for new graph
  static Future<void> setEffect(int track, int pluginIndex, String paramId, dynamic value) async {
    try {
      await _ch.invokeMethod('setEffect', {
        'track': track,
        'pluginIndex': pluginIndex,
        'paramId': paramId,
        'value': value,
      });
    } on PlatformException catch (e) {
      _logError('setEffect', e);
    }
  }

  static Future<void> bypassPlugin(int track, int effect, bool shouldBypass) async {
    try {
      await _ch.invokeMethod('bypassPlugin', {
        'track': track,
        'effect': effect,
        'bypass': shouldBypass,
      });
    } on PlatformException catch (e) {
      _logError('bypassPlugin', e);
    }
  }

  static Future<bool> getPluginBypassState(int track, int effect) async {
    try {
      final res = await _ch.invokeMethod('getPluginBypassState', {
        'track': track,
        'effect': effect,
      });
      return res;
    } on PlatformException catch (e) {
      _logError('getPluginBypassState', e);
    }
    return false;
  }

  static Future<void> setTrackVolume(int track, double volume) async {
    try {
      await _ch.invokeMethod('setTrackVolume', {
        'track': track,
        'volume': volume,
      });
    } on PlatformException catch (e) {
      _logError('setTrackVolume', e);
    }
  }

  // -------------------------------
  // Plugin scanning & export
  // -------------------------------
  static Future<List<Map<String, String>>> scanPlugins() async {
    try {
      final result = await _ch.invokeMethod<List<dynamic>>('scanPlugins');
      return result?.cast<Map<dynamic, dynamic>>().map((m) => Map<String, String>.from(m)).toList() ??
          <Map<String, String>>[];
    } on PlatformException catch (e) {
      _logError('scanPlugins', e);
      return <Map<String, String>>[];
    }
  }

  static Future<String> exportMix(String outPath) async {
    try {
      final result = await _ch.invokeMethod<String>(
        'exportMix',
        {'outPath': outPath},
      );
      return result ?? '';
    } on PlatformException catch (e) {
      _logError('exportMix', e);
      return '';
    }
  }

  static Future<String> exportTrack(int track, String outPath) async {
    try {
      final result = await _ch.invokeMethod<String>(
        'exportTrack',
        {'track': track, 'outPath': outPath},
      );
      return result ?? '';
    } on PlatformException catch (e) {
      _logError('exportTrack', e);
      return '';
    }
  }

  // -------------------------------
  // Video audio lane
  // -------------------------------
  static Future<void> loadVideoAudio(String path) async {
    try {
      await _ch.invokeMethod('loadVideoAudio', {'path': path});
    } on PlatformException catch (e) {
      _logError('loadVideoAudio', e);
    }
  }

  static Future<void> unloadVideoAudio() async {
    try {
      await _ch.invokeMethod('unloadVideoAudio');
    } on PlatformException catch (e) {
      _logError('unloadVideoAudio', e);
    }
  }

  static Future<void> setVideoAudioGain(double gain0to3) async {
    try {
      await _ch.invokeMethod('setVideoAudioGain', {'gain': gain0to3});
    } on PlatformException catch (e) {
      _logError('setVideoAudioGain', e);
    }
  }

  static Future<void> seekVideoAudio(double seconds) async {
    try {
      await _ch.invokeMethod('seekVideoAudio', {'seconds': seconds});
    } on PlatformException catch (e) {
      _logError('seekVideoAudio', e);
    }
  }

  // ===============================
  // NEW CLIP-LEVEL API
  // ===============================
  static Future<void> loadClip(int clipIndex, int rowIndex, String path) async {
    try {
      await _ch.invokeMethod('loadClip', {
        'clip': clipIndex,
        'row': rowIndex,
        'path': path,
      });
    } on PlatformException catch (e) {
      _logError('loadClip', e);
    }
  }

  static Future<void> setClipGain(int clipIndex, double gain0to3) async {
    try {
      await _ch.invokeMethod('setClipGain', {
        'clip': clipIndex,
        'gain': gain0to3,
      });
    } on PlatformException catch (e) {
      _logError('setClipGain', e);
    }
  }

  static Future<void> setClipPan(int clipIndex, double panMinus1To1) async {
    try {
      await _ch.invokeMethod('setClipPan', {
        'clip': clipIndex,
        'pan': panMinus1To1,
      });
    } on PlatformException catch (e) {
      _logError('setClipPan', e);
    }
  }

  static Future<void> muteClip(int clipIndex, bool mute) async {
    try {
      await _ch.invokeMethod('muteClip', {
        'clip': clipIndex,
        'mute': mute,
      });
    } on PlatformException catch (e) {
      _logError('muteClip', e);
    }
  }

  static Future<void> moveClipToRow(int clipIndex, int newRow) async {
    try {
      await _ch.invokeMethod('moveClipToRow', {
        'clip': clipIndex,
        'row': newRow,
      });
    } on PlatformException catch (e) {
      _logError('moveClipToRow', e);
    }
  }

  // ===============================
  // NEW ROW (TRACK BUS) API
  // ===============================
  static Future<void> insertTrackEffect(int row, String path) async {
    try {
      await _ch.invokeMethod('insertTrackEffect', {
        'row': row,
        'path': path,
      });
    } on PlatformException catch (e) {
      _logError('insertTrackEffect', e);
    }
  }

  static Future<void> removeTrackEffect(int row, int effectIndex) async {
    try {
      await _ch.invokeMethod('removeTrackEffect', {
        'row': row,
        'effect': effectIndex,
      });
    } on PlatformException catch (e) {
      _logError('removeTrackEffect', e);
    }
  }

  static Future<void> reorderTrackEffects(int row, int from, int to) async {
    try {
      await _ch.invokeMethod('reorderTrackEffects', {
        'row': row,
        'from': from,
        'to': to,
      });
    } on PlatformException catch (e) {
      _logError('reorderTrackEffects', e);
    }
  }

  static Future<List<String>> getTrackEffectsForRow(int row) async {
    try {
      final list = await _ch.invokeListMethod<String>(
        'getTrackEffectsForRow',
        {'row': row},
      );
      return list ?? <String>[];
    } on PlatformException catch (e) {
      _logError('getTrackEffectsForRow', e);
      return <String>[];
    }
  }

  static Future<void> setTrackEffect(int row, int effectIndex, String paramId, dynamic value) async {
    try {
      await _ch.invokeMethod('setTrackEffect', {
        'row': row,
        'effect': effectIndex,
        'paramId': paramId,
        'value': value,
      });
    } on PlatformException catch (e) {
      _logError('setTrackEffect', e);
    }
  }

  static Future<void> bypassRowEffect(int row, int effectIndex, bool bypass) async {
    try {
      await _ch.invokeMethod('bypassRowEffect', {
        'row': row,
        'effect': effectIndex,
        'bypass': bypass,
      });
    } on PlatformException catch (e) {
      _logError('bypassRowEffect', e);
    }
  }

  static Future<bool> getRowEffectBypassState(int row, int effectIndex) async {
    try {
      final res = await _ch.invokeMethod<bool>(
        'getRowEffectBypassState',
        {
          'row': row,
          'effect': effectIndex,
        },
      );
      return res ?? false;
    } on PlatformException catch (e) {
      _logError('getRowEffectBypassState', e);
      return false;
    }
  }

  /// points: List<Map<String, double>> with keys like
  /// { "timeSeconds": double, "value": double }
  static Future<void> setTrackAutomationPoints(int row, List<Map<String, dynamic>> points) async {
    try {
      await _ch.invokeMethod('setTrackAutomationPoints', {
        'row': row,
        'points': points,
      });
    } on PlatformException catch (e) {
      _logError('setTrackAutomationPoints', e);
    }
  }

  static Future<void> setRowGain(int row, double gain0to3) async {
    try {
      await _ch.invokeMethod('setRowGain', {
        'row': row,
        'gain': gain0to3,
      });
    } on PlatformException catch (e) {
      _logError('setRowGain', e);
    }
  }

  static Future<void> muteRow(int row, bool mute) async {
    try {
      await _ch.invokeMethod('muteRow', {
        'row': row,
        'mute': mute,
      });
    } on PlatformException catch (e) {
      _logError('muteRow', e);
    }
  }

  static Future<bool> isRowMuted(int row) async {
    try {
      final res = await _ch.invokeMethod<bool>(
        'isRowMuted',
        {'row': row},
      );
      return res ?? false;
    } on PlatformException catch (e) {
      _logError('isRowMuted', e);
      return false;
    }
  }

  static Future<void> setRowPan(int row, double panMinus1To1) async {
    try {
      await _ch.invokeMethod('setRowPan', {
        'row': row,
        'pan': panMinus1To1,
      });
    } on PlatformException catch (e) {
      _logError('setRowPan', e);
    }
  }

  // ===============================
  // MASTER BUS API
  // ===============================
  static Future<void> insertMasterEffect(String path) async {
    try {
      await _ch.invokeMethod('insertMasterEffect', {'path': path});
    } on PlatformException catch (e) {
      _logError('insertMasterEffect', e);
    }
  }

  static Future<void> removeMasterEffect(int effectIndex) async {
    try {
      await _ch.invokeMethod('removeMasterEffect', {
        'effect': effectIndex,
      });
    } on PlatformException catch (e) {
      _logError('removeMasterEffect', e);
    }
  }

  static Future<void> reorderMasterEffects(int from, int to) async {
    try {
      await _ch.invokeMethod('reorderMasterEffects', {
        'from': from,
        'to': to,
      });
    } on PlatformException catch (e) {
      _logError('reorderMasterEffects', e);
    }
  }

  static Future<List<String>> getMasterEffects() async {
    try {
      final list = await _ch.invokeListMethod<String>('getMasterEffects');
      return list ?? <String>[];
    } on PlatformException catch (e) {
      _logError('getMasterEffects', e);
      return <String>[];
    }
  }

  static Future<void> setMasterEffect(int effectIndex, String paramId, dynamic value) async {
    try {
      await _ch.invokeMethod('setMasterEffect', {
        'effect': effectIndex,
        'paramId': paramId,
        'value': value,
      });
    } on PlatformException catch (e) {
      _logError('setMasterEffect', e);
    }
  }

  static Future<void> bypassMasterEffect(int effectIndex, bool bypass) async {
    try {
      await _ch.invokeMethod('bypassMasterEffect', {
        'effect': effectIndex,
        'bypass': bypass,
      });
    } on PlatformException catch (e) {
      _logError('bypassMasterEffect', e);
    }
  }

  static Future<bool> getMasterEffectBypassState(int effectIndex) async {
    try {
      final res = await _ch.invokeMethod<bool>(
        'getMasterEffectBypassState',
        {'effect': effectIndex},
      );
      return res ?? false;
    } on PlatformException catch (e) {
      _logError('getMasterEffectBypassState', e);
      return false;
    }
  }

  static Future<void> setMasterGain(double gain0to3) async {
    try {
      await _ch.invokeMethod('setMasterGain', {'gain': gain0to3});
    } on PlatformException catch (e) {
      _logError('setMasterGain', e);
    }
  }

  static Future<void> muteMaster(bool mute) async {
    try {
      await _ch.invokeMethod('muteMaster', {'mute': mute});
    } on PlatformException catch (e) {
      _logError('muteMaster', e);
    }
  }

  static Future<void> setMasterPan(double panMinus1To1) async {
    try {
      await _ch.invokeMethod('setMasterPan', {'pan': panMinus1To1});
    } on PlatformException catch (e) {
      _logError('setMasterPan', e);
    }
  }

  // ===============================
  // TRANSPORT / DEBUG
  // ===============================
  static Future<void> setAutomationTransport(double timeSeconds) async {
    try {
      await _ch.invokeMethod('setAutomationTransport', {
        'timeSeconds': timeSeconds,
      });
    } on PlatformException catch (e) {
      _logError('setAutomationTransport', e);
    }
  }

  static Future<void> debugPrintGraph(String title) async {
    try {
      await _ch.invokeMethod('debugPrintGraph', {'title': title});
    } on PlatformException catch (e) {
      _logError('debugPrintGraph', e);
    }
  }

  static Future<void> debugPrintGraphStructure() async {
    try {
      await _ch.invokeMethod('debugPrintGraphStructure');
    } on PlatformException catch (e) {
      _logError('debugPrintGraphStructure', e);
    }
  }

  static Future<void> setMetronomeEnabled(bool enabled) async {
    try {
      await _ch.invokeMethod('setMetronomeEnabled', {
        'enabled': enabled,
      });
    } on PlatformException catch (e) {
      _logError('setMetronomeEnabled', e);
    }
  }

  static Future<void> setMetronomeVolume(double volume0to1) async {
    try {
      await _ch.invokeMethod('setMetronomeVolume', {
        'volume': volume0to1,
      });
    } on PlatformException catch (e) {
      _logError('setMetronomeVolume', e);
    }
  }

  static Future<void> setMetronomeBpm(double bpm) async {
    try {
      await _ch.invokeMethod('setMetronomeBpm', {
        'bpm': bpm,
      });
    } on PlatformException catch (e) {
      _logError('setMetronomeBpm', e);
    }
  }

  static Future<void> setMetronomeTransportMs(double ms) async {
    try {
      await _ch.invokeMethod('setMetronomeTransportMs', {
        'ms': ms,
      });
    } on PlatformException catch (e) {
      _logError('setMetronomeTransportMs', e);
    }
  }

  static Future<Float32List> decodeAudioMono16k(String path) async {
    final List<dynamic> raw = await _ch.invokeMethod(
      'decodeAudioMono16k',
      {'path': path},
    );

    return Float32List.fromList(
      raw.map((e) => (e as num).toDouble()).toList(),
    );
  }

  static Future<List<String>> getInputDevices() async {
    try {
      final res = await _ch.invokeMethod<List>('getInputDevices');
      return (res ?? []).cast<String>();
    } on PlatformException catch (e) {
      _logError('getInputDevices', e);
      return [];
    }
  }

  static Future<bool> selectInputDevice(String name) async {
    try {
      final res = await _ch.invokeMethod<bool>('selectInputDevice', {
        'name': name,
      });
      return res ?? false;
    } on PlatformException catch (e) {
      _logError('selectInputDevice', e);
      return false;
    }
  }

  static Future<int> getNumInputChannels() async {
    try {
      final res = await _ch.invokeMethod<int>('getNumInputChannels');
      return res ?? 0;
    } on PlatformException catch (e) {
      _logError('getNumInputChannels', e);
      return 0;
    }
  }

  static Future<double> getRecordingPeak() async {
    try {
      final res = await _ch.invokeMethod<double>('getRecordingPeak');
      return res ?? 0.0;
    } on PlatformException catch (e) {
      _logError('getRecordingPeak', e);
      return 0;
    }
  }

  static Future<String> getCurrentDeviceName() async {
    try {
      final res = await _ch.invokeMethod<String>('getCurrentDeviceName');
      return res ?? '';
    } on PlatformException catch (e) {
      _logError('getCurrentDeviceName', e);
      return '';
    }
  }

  static Future<bool> startRecording(
    String path,
    int channelStart,
    int channelCount,
  ) async {
    try {
      final res = await _ch.invokeMethod<bool>('startRecording', {
        'path': path,
        'channelStart': channelStart,
        'channelCount': channelCount,
      });
      return res ?? false;
    } on PlatformException catch (e) {
      _logError('startRecording', e);
      return false;
    }
  }

  static Future<void> stopRecording() async {
    try {
      await _ch.invokeMethod('stopRecording');
    } on PlatformException catch (e) {
      _logError('stopRecording', e);
    }
  }

  static Future<bool> isRecording() async {
    try {
      final res = await _ch.invokeMethod<bool>('isRecording');
      return res ?? false;
    } on PlatformException catch (e) {
      _logError('isRecording', e);
      return false;
    }
  }
}
