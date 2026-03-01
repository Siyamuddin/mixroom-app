import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class JuceEngineCapabilities {
  final bool externalPluginHosting;
  final List<String> supportedPluginFormats;
  final bool nativePluginEditor;

  const JuceEngineCapabilities({
    required this.externalPluginHosting,
    required this.supportedPluginFormats,
    required this.nativePluginEditor,
  });

  static const JuceEngineCapabilities none = JuceEngineCapabilities(
    externalPluginHosting: false,
    supportedPluginFormats: <String>[],
    nativePluginEditor: false,
  );

  factory JuceEngineCapabilities.fromMap(Map<String, dynamic> map) {
    final rawFormats = map['supportedPluginFormats'];
    final formats = <String>[];
    if (rawFormats is List) {
      for (final item in rawFormats) {
        final value = item?.toString().trim() ?? '';
        if (value.isNotEmpty) formats.add(value);
      }
    }
    return JuceEngineCapabilities(
      externalPluginHosting: map['externalPluginHosting'] == true,
      supportedPluginFormats: formats,
      nativePluginEditor: map['nativePluginEditor'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'externalPluginHosting': externalPluginHosting,
      'supportedPluginFormats': supportedPluginFormats,
      'nativePluginEditor': nativePluginEditor,
    };
  }
}

class JuceAudioEngine {
  static const _ch = MethodChannel('juce_audio_engine');
  static const _eventCh = EventChannel('juce_audio_engine/events');

  static Stream<Map<String, dynamic>> get _events => _eventCh
      .receiveBroadcastStream()
      .cast<Map<dynamic, dynamic>>()
      .map((e) => Map<String, dynamic>.from(e));

  static void initialiseEventListeners() {
    _events.listen((event) {
      if (event['event'] == 'pluginLoaded') {
        final track = event['track'] as int;
        final path = event['path'] as String;
        final success = event['success'] as bool;
        debugPrint("Plugin loaded: $success for $path on track $track");
      }
    });
  }

  // -------------------------------
  // Helpers
  // -------------------------------
  static void _logError(String method, Object error) {
    debugPrint('JuceAudioEngine.$method failed: $error');
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
      debugPrint('bypassTrack failed: $e');
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

  static Future<void> setTransportSeconds(double timeSeconds) async {
    try {
      await _ch
          .invokeMethod('setTransportSeconds', {'timeSeconds': timeSeconds});
    } on PlatformException catch (e) {
      _logError('setTransportSeconds', e);
    }
  }

  static Future<double> getTransportSeconds() async {
    try {
      final t = await _ch.invokeMethod<double>('getTransportSeconds');
      return t ?? 0.0;
    } on PlatformException catch (e) {
      _logError('getTransportSeconds', e);
      return 0.0;
    }
  }

  static Future<void> seekTransport(double timeSeconds) async {
    try {
      await _ch.invokeMethod('seekTransport', {'timeSeconds': timeSeconds});
    } on PlatformException catch (e) {
      _logError('seekTransport', e);
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
  static Future<void> setEffect(
      int track, int pluginIndex, String paramId, dynamic value) async {
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

  static Future<void> bypassPlugin(
      int track, int effect, bool shouldBypass) async {
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
  static JuceEngineCapabilities _fallbackEngineCapabilities() {
    if (kIsWeb) return JuceEngineCapabilities.none;
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
        return const JuceEngineCapabilities(
          externalPluginHosting: true,
          supportedPluginFormats: <String>['AU', 'VST3'],
          nativePluginEditor: false,
        );
      case TargetPlatform.windows:
        return const JuceEngineCapabilities(
          externalPluginHosting: true,
          supportedPluginFormats: <String>['VST3'],
          nativePluginEditor: false,
        );
      case TargetPlatform.iOS:
        return const JuceEngineCapabilities(
          externalPluginHosting: false,
          supportedPluginFormats: <String>['AUv3'],
          nativePluginEditor: false,
        );
      case TargetPlatform.android:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return JuceEngineCapabilities.none;
    }
  }

  static Future<JuceEngineCapabilities> getEngineCapabilities() async {
    try {
      final raw = await _ch
          .invokeMethod<Map<dynamic, dynamic>>('getEngineCapabilities');
      if (raw == null) return _fallbackEngineCapabilities();
      return JuceEngineCapabilities.fromMap(Map<String, dynamic>.from(raw));
    } on MissingPluginException {
      return _fallbackEngineCapabilities();
    } on PlatformException catch (e) {
      _logError('getEngineCapabilities', e);
      return _fallbackEngineCapabilities();
    }
  }

  static Future<List<Map<String, dynamic>>> scanPlugins() async {
    try {
      final result = await _ch.invokeMethod<List<dynamic>>('scanPlugins');
      final normalized = <Map<String, dynamic>>[];
      if (result == null) return normalized;
      for (final item in result) {
        if (item is! Map) continue;
        final raw = Map<String, dynamic>.from(item);
        final rawId = raw['id']?.toString().trim() ?? '';
        final rawPath = raw['path']?.toString().trim() ?? '';
        final rawName = raw['name']?.toString().trim() ?? '';

        final id =
            rawId.isNotEmpty ? rawId : (rawPath.isNotEmpty ? rawPath : rawName);
        if (id.isEmpty) continue;

        final out = <String, dynamic>{
          'id': id,
          'name': rawName.isNotEmpty ? rawName : id,
        };

        final format = raw['format']?.toString().trim() ?? '';
        if (format.isNotEmpty) out['format'] = format;
        final manufacturer = raw['manufacturer']?.toString().trim() ?? '';
        if (manufacturer.isNotEmpty) out['manufacturer'] = manufacturer;
        final category = raw['category']?.toString().trim() ?? '';
        if (category.isNotEmpty) out['category'] = category;

        normalized.add(out);
      }
      return normalized;
    } on PlatformException catch (e) {
      _logError('scanPlugins', e);
      return <Map<String, dynamic>>[];
    }
  }

  static Future<String> exportMix(
    String outPath, {
    String format = 'wav',
    int sampleRate = 44100,
    int wavBitDepth = 16,
    bool wavDithering = true,
    int mp3BitrateKbps = 192,
  }) async {
    try {
      final result = await _ch.invokeMethod<String>(
        'exportMix',
        {
          'outPath': outPath,
          'format': format,
          'sampleRate': sampleRate,
          'wavBitDepth': wavBitDepth,
          'wavDithering': wavDithering,
          'mp3BitrateKbps': mp3BitrateKbps,
        },
      );
      return result ?? '';
    } on PlatformException catch (e) {
      _logError('exportMix', e);
      return '';
    }
  }

  static Future<String> exportTrack(
    int track,
    String outPath, {
    String format = 'wav',
    int sampleRate = 44100,
    int wavBitDepth = 16,
    bool wavDithering = true,
    int mp3BitrateKbps = 192,
  }) async {
    try {
      final result = await _ch.invokeMethod<String>(
        'exportTrack',
        {
          'track': track,
          'outPath': outPath,
          'format': format,
          'sampleRate': sampleRate,
          'wavBitDepth': wavBitDepth,
          'wavDithering': wavDithering,
          'mp3BitrateKbps': mp3BitrateKbps,
        },
      );
      return result ?? '';
    } on PlatformException catch (e) {
      _logError('exportTrack', e);
      return '';
    }
  }

  static Future<String> renderInstrumentClip({
    required String outPath,
    required String instrumentId,
    required String instrumentName,
    required double bpm,
    required List<Map<String, dynamic>> notes,
    required Map<String, double> params,
  }) async {
    try {
      final result = await _ch.invokeMethod<String>(
        'renderInstrumentClip',
        {
          'outPath': outPath,
          'instrumentId': instrumentId,
          'instrumentName': instrumentName,
          'bpm': bpm,
          'notes': notes,
          'params': params,
        },
      );
      return result ?? '';
    } on PlatformException catch (e) {
      _logError('renderInstrumentClip', e);
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

  static Future<bool> supportsLiveMidiClipPlayback() async {
    try {
      final supported =
          await _ch.invokeMethod<bool>('supportsLiveMidiClipPlayback');
      return supported ?? false;
    } on PlatformException catch (e) {
      _logError('supportsLiveMidiClipPlayback', e);
      return false;
    }
  }

  static Future<bool> loadMidiClip(
    int clipIndex,
    int rowId, {
    required String instrumentId,
    required String instrumentName,
    required List<Map<String, dynamic>> notes,
    required Map<String, double> params,
    required double sourceTempoBpm,
    double startSec = 0.0,
    double lengthSec = 0.0,
    double inFileOffsetSec = 0.0,
  }) async {
    try {
      final ok = await _ch.invokeMethod<bool>('loadMidiClip', {
        'clip': clipIndex,
        'rowId': rowId,
        'row': rowId, // backward compatibility
        'instrumentId': instrumentId,
        'instrumentName': instrumentName,
        'notes': notes,
        'params': params,
        'sourceTempoBpm': sourceTempoBpm,
        'startSec': startSec,
        'lengthSec': lengthSec,
        'inFileOffsetSec': inFileOffsetSec,
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      _logError('loadMidiClip', e);
      return false;
    }
  }

  static Future<bool> updateMidiClipEvents(
    int clipIndex, {
    required String instrumentId,
    required String instrumentName,
    required List<Map<String, dynamic>> notes,
    required Map<String, double> params,
    required double sourceTempoBpm,
  }) async {
    try {
      final ok = await _ch.invokeMethod<bool>('updateMidiClipEvents', {
        'clip': clipIndex,
        'instrumentId': instrumentId,
        'instrumentName': instrumentName,
        'notes': notes,
        'params': params,
        'sourceTempoBpm': sourceTempoBpm,
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      _logError('updateMidiClipEvents', e);
      return false;
    }
  }

  static Future<bool> setLiveMidiInputTargetClip(int clipIndex) async {
    try {
      final ok = await _ch.invokeMethod<bool>('setLiveMidiInputTargetClip', {
        'clip': clipIndex,
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      _logError('setLiveMidiInputTargetClip', e);
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> consumeLiveMidiInputEvents() async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>(
        'consumeLiveMidiInputEvents',
      );
      if (raw == null) return <Map<String, dynamic>>[];
      return raw
          .map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
          .toList();
    } on PlatformException catch (e) {
      _logError('consumeLiveMidiInputEvents', e);
      return <Map<String, dynamic>>[];
    }
  }

  static Future<List<Map<String, String>>>
      getConnectedMidiInputDevices() async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>(
        'getConnectedMidiInputDevices',
      );
      if (raw == null) return <Map<String, String>>[];
      return raw
          .map((entry) {
            final map =
                Map<String, dynamic>.from(entry as Map<dynamic, dynamic>);
            final id = (map['id'] as String?)?.trim() ?? '';
            final name = (map['name'] as String?)?.trim() ?? id;
            return <String, String>{
              'id': id,
              'name': name,
            };
          })
          .where((entry) => (entry['id'] ?? '').isNotEmpty)
          .toList();
    } on PlatformException catch (e) {
      _logError('getConnectedMidiInputDevices', e);
      return <Map<String, String>>[];
    }
  }

  // ===============================
  // NEW CLIP-LEVEL API
  // ===============================
  static Future<void> loadClip(
    int clipIndex,
    int rowId,
    String path, {
    double startSec = 0.0,
    double lengthSec = 0.0,
    double inFileOffsetSec = 0.0,
  }) async {
    try {
      await _ch.invokeMethod('loadClip', {
        'clip': clipIndex,
        'rowId': rowId,
        'row': rowId, // backward compatibility
        'path': path,
        'startSec': startSec,
        'lengthSec': lengthSec,
        'inFileOffsetSec': inFileOffsetSec,
      });
    } on PlatformException catch (e) {
      _logError('loadClip', e);
    }
  }

  static Future<void> unloadClip(int clipIndex) async {
    try {
      await _ch.invokeMethod('unloadClip', {'clip': clipIndex});
    } on PlatformException catch (e) {
      _logError('unloadClip', e);
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

  static Future<void> setClipPitch(int clipIndex, double semitones) async {
    try {
      await _ch.invokeMethod('setClipPitch', {
        'clip': clipIndex,
        'semitones': semitones,
      });
    } on PlatformException catch (e) {
      _logError('setClipPitch', e);
    }
  }

  static Future<void> setClipStretchOptions(
    int clipIndex, {
    required double tempoRatio,
    required bool preservePitch,
  }) async {
    try {
      await _ch.invokeMethod('setClipStretchOptions', {
        'clip': clipIndex,
        'tempoRatio': tempoRatio,
        'preservePitch': preservePitch,
      });
    } on PlatformException catch (e) {
      _logError('setClipStretchOptions', e);
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

  static Future<void> moveClipToRow(int clipIndex, int newRowId) async {
    try {
      await _ch.invokeMethod('moveClipToRow', {
        'clip': clipIndex,
        'rowId': newRowId,
        'row': newRowId, // backward compatibility
      });
    } on PlatformException catch (e) {
      _logError('moveClipToRow', e);
    }
  }

  static Future<void> setClipTime(
    int clipIndex, {
    required double startSec,
    required double lengthSec,
    double inFileOffsetSec = 0.0,
  }) async {
    try {
      await _ch.invokeMethod('setClipTime', {
        'clip': clipIndex,
        'startSec': startSec,
        'lengthSec': lengthSec,
        'inFileOffsetSec': inFileOffsetSec,
      });
    } on PlatformException catch (e) {
      _logError('setClipTime', e);
    }
  }

  static Future<int> addRow(String name, {int iconId = 0}) async {
    try {
      final id = await _ch.invokeMethod<int>('addRow', {
        'name': name,
        'iconId': iconId,
      });
      return id ?? -1;
    } on PlatformException catch (e) {
      _logError('addRow', e);
      return -1;
    }
  }

  static Future<int> insertRowAbove(int referenceRowId, String name,
      {int iconId = 0}) async {
    try {
      final id = await _ch.invokeMethod<int>('insertRowAbove', {
        'referenceRowId': referenceRowId,
        'name': name,
        'iconId': iconId,
      });
      return id ?? -1;
    } on PlatformException catch (e) {
      _logError('insertRowAbove', e);
      return -1;
    }
  }

  static Future<int> insertRowBelow(int referenceRowId, String name,
      {int iconId = 0}) async {
    try {
      final id = await _ch.invokeMethod<int>('insertRowBelow', {
        'referenceRowId': referenceRowId,
        'name': name,
        'iconId': iconId,
      });
      return id ?? -1;
    } on PlatformException catch (e) {
      _logError('insertRowBelow', e);
      return -1;
    }
  }

  static Future<bool> removeRow(int rowId) async {
    try {
      final ok = await _ch.invokeMethod<bool>('removeRow', {'rowId': rowId});
      return ok ?? false;
    } on PlatformException catch (e) {
      _logError('removeRow', e);
      return false;
    }
  }

  static Future<bool> moveRowOrder(int fromIndex, int toIndex) async {
    try {
      final ok = await _ch.invokeMethod<bool>('moveRowOrder', {
        'from': fromIndex,
        'to': toIndex,
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      _logError('moveRowOrder', e);
      return false;
    }
  }

  static Future<bool> renameRow(int rowId, String name) async {
    try {
      final ok = await _ch.invokeMethod<bool>('renameRow', {
        'rowId': rowId,
        'name': name,
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      _logError('renameRow', e);
      return false;
    }
  }

  static Future<bool> setRowIcon(int rowId, int iconId) async {
    try {
      final ok = await _ch.invokeMethod<bool>('setRowIcon', {
        'rowId': rowId,
        'iconId': iconId,
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      _logError('setRowIcon', e);
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getRows() async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('getRows');
      if (raw == null) return <Map<String, dynamic>>[];
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on PlatformException catch (e) {
      _logError('getRows', e);
      return <Map<String, dynamic>>[];
    }
  }

  // ===============================
  // NEW ROW (TRACK BUS) API
  // ===============================
  static Future<void> insertTrackEffect(int row, String path) async {
    try {
      final ok = await _ch.invokeMethod<bool>('insertTrackEffect', {
        'row': row,
        'path': path,
      });
      if (ok == false) {
        throw PlatformException(
          code: 'insert_track_effect_failed',
          message: 'Native insertTrackEffect returned false',
          details: {'row': row, 'path': path},
        );
      }
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

  static Future<List<String>> getTrackEffectIdsForRow(int row) async {
    try {
      final list = await _ch.invokeListMethod<String>(
        'getTrackEffectIdsForRow',
        {'row': row},
      );
      return list ?? <String>[];
    } on PlatformException catch (e) {
      _logError('getTrackEffectIdsForRow', e);
      return <String>[];
    }
  }

  static Future<List<String>> getTrackEffectInstanceIdsForRow(int row) async {
    try {
      final list = await _ch.invokeListMethod<String>(
        'getTrackEffectInstanceIdsForRow',
        {'row': row},
      );
      return list ?? <String>[];
    } on PlatformException catch (e) {
      _logError('getTrackEffectInstanceIdsForRow', e);
      return <String>[];
    }
  }

  static Future<void> setTrackEffect(
      int row, int effectIndex, String paramId, dynamic value) async {
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

  static Future<void> bypassRowEffect(
      int row, int effectIndex, bool bypass) async {
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

  /// points: `List<Map<String, double>>` with keys like
  /// `{ "timeSeconds": double, "value": double }`
  static Future<void> setTrackAutomationPoints(
      int row, List<Map<String, dynamic>> points) async {
    try {
      await _ch.invokeMethod('setTrackAutomationPoints', {
        'row': row,
        'points': points,
      });
    } on PlatformException catch (e) {
      _logError('setTrackAutomationPoints', e);
    }
  }

  static Future<void> setTrackEffectAutomationPoints(
    int row,
    int effectIndex,
    String paramId,
    double minValue,
    double maxValue,
    List<Map<String, dynamic>> points,
  ) async {
    try {
      await _ch.invokeMethod('setTrackEffectAutomationPoints', {
        'row': row,
        'effect': effectIndex,
        'paramId': paramId,
        'min': minValue,
        'max': maxValue,
        'points': points,
      });
    } on PlatformException catch (e) {
      _logError('setTrackEffectAutomationPoints', e);
    }
  }

  static Future<void> clearTrackEffectAutomationForRow(int row) async {
    try {
      await _ch.invokeMethod('clearTrackEffectAutomationForRow', {
        'row': row,
      });
    } on PlatformException catch (e) {
      _logError('clearTrackEffectAutomationForRow', e);
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
      final ok =
          await _ch.invokeMethod<bool>('insertMasterEffect', {'path': path});
      if (ok == false) {
        throw PlatformException(
          code: 'insert_master_effect_failed',
          message: 'Native insertMasterEffect returned false',
          details: {'path': path},
        );
      }
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

  static Future<List<String>> getMasterEffectIds() async {
    try {
      final list = await _ch.invokeListMethod<String>('getMasterEffectIds');
      return list ?? <String>[];
    } on PlatformException catch (e) {
      _logError('getMasterEffectIds', e);
      return <String>[];
    }
  }

  static Future<void> setMasterEffect(
      int effectIndex, String paramId, dynamic value) async {
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

  static Future<Map<String, double>> analyzeAudioStereo16k(String path) async {
    try {
      final raw = await _ch.invokeMapMethod<String, dynamic>(
        'analyzeAudioStereo16k',
        {'path': path},
      );
      if (raw == null) return const {};
      return raw.map((k, v) {
        if (v is num) return MapEntry(k, v.toDouble());
        return MapEntry(k, 0.0);
      });
    } on MissingPluginException {
      return const {};
    } on PlatformException catch (e) {
      _logError('analyzeAudioStereo16k', e);
      return const {};
    } catch (_) {
      return const {};
    }
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

  // ===============================
  // MASTER METER
  // ===============================
  static Future<void> setMasterMeterEnabled(bool enabled) async {
    try {
      await _ch.invokeMethod('setMasterMeterEnabled', {'enabled': enabled});
    } on PlatformException catch (e) {
      _logError('setMasterMeterEnabled', e);
    }
  }

  // returns [peakL, peakR, rmsL, rmsR]
  static Future<List<double>> getMasterMeterValues() async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('getMasterMeterValues');
      if (raw == null) return [0, 0, 0, 0];
      return raw.map((e) => (e as num).toDouble()).toList();
    } on PlatformException catch (e) {
      _logError('getMasterMeterValues', e);
      return [0, 0, 0, 0];
    }
  }

  static Future<bool> getMasterClipLatched() async {
    try {
      final v = await _ch.invokeMethod<bool>('getMasterClipLatched');
      return v ?? false;
    } on PlatformException catch (e) {
      _logError('getMasterClipLatched', e);
      return false;
    }
  }

  static Future<void> clearMasterClipLatched() async {
    try {
      await _ch.invokeMethod('clearMasterClipLatched');
    } on PlatformException catch (e) {
      _logError('clearMasterClipLatched', e);
    }
  }

// ===============================
// ROW METERS
// ===============================
  static Future<void> setRowMetersEnabled(bool enabled) async {
    try {
      await _ch.invokeMethod('setRowMetersEnabled', {'enabled': enabled});
    } on PlatformException catch (e) {
      _logError('setRowMetersEnabled', e);
    }
  }

// returns [peakL, peakR, rmsL, rmsR]
  static Future<List<double>> getRowMeterValues(int row) async {
    try {
      final raw = await _ch
          .invokeMethod<List<dynamic>>('getRowMeterValues', {'row': row});
      if (raw == null) return [0, 0, 0, 0];
      return raw.map((e) => (e as num).toDouble()).toList();
    } on PlatformException catch (e) {
      _logError('getRowMeterValues', e);
      return [0, 0, 0, 0];
    }
  }

  static Future<List<double>> getAllMeterValues() async {
    final dynamic res = await _ch.invokeMethod('getAllMeterValues');

    // Native should return List<num> (NSNumber in iOS)
    if (res is List) {
      return res.map((e) => (e as num).toDouble()).toList(growable: false);
    }

    return const <double>[];
  }

// ===============================
// COMPRESSOR METER STRIPS
// returns [inRmsL, inRmsR, grDb, outRmsL, outRmsR]
// ===============================
  static Future<List<double>> getClipCompressorMeter(
      int clip, int effect) async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>(
        'getClipCompressorMeter',
        {'clip': clip, 'effect': effect},
      );
      if (raw == null) return [0, 0, 0, 0, 0];
      return raw.map((e) => (e as num).toDouble()).toList();
    } on PlatformException catch (e) {
      _logError('getClipCompressorMeter', e);
      return [0, 0, 0, 0, 0];
    }
  }

  static Future<List<double>> getRowCompressorMeter(int row, int effect) async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>(
        'getRowCompressorMeter',
        {'row': row, 'effect': effect},
      );
      if (raw == null) return [0, 0, 0, 0, 0];
      return raw.map((e) => (e as num).toDouble()).toList();
    } on PlatformException catch (e) {
      _logError('getRowCompressorMeter', e);
      return [0, 0, 0, 0, 0];
    }
  }

  static Future<List<double>> getMasterCompressorMeter(int effect) async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>(
        'getMasterCompressorMeter',
        {'effect': effect},
      );
      if (raw == null) return [0, 0, 0, 0, 0];
      return raw.map((e) => (e as num).toDouble()).toList();
    } on PlatformException catch (e) {
      _logError('getMasterCompressorMeter', e);
      return [0, 0, 0, 0, 0];
    }
  }

  static Future<double> getHostSampleRate() async {
    try {
      final sr = await _ch.invokeMethod<double>('getHostSampleRate');
      if (sr == null || sr <= 1000.0) return 44100.0;
      return sr;
    } on PlatformException catch (e) {
      _logError('getHostSampleRate', e);
      return 44100.0;
    }
  }

  static Future<List<double>> getRowEqWaveform(
    int row,
    int effect, {
    int sampleCount = 1024,
  }) async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>(
        'getRowEqWaveform',
        {'row': row, 'effect': effect, 'sampleCount': sampleCount},
      );
      if (raw == null) return const <double>[];
      return raw.map((e) => (e as num).toDouble()).toList(growable: false);
    } on PlatformException catch (e) {
      _logError('getRowEqWaveform', e);
      return const <double>[];
    }
  }

  static Future<List<double>> getMasterEqWaveform(
    int effect, {
    int sampleCount = 1024,
  }) async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>(
        'getMasterEqWaveform',
        {'effect': effect, 'sampleCount': sampleCount},
      );
      if (raw == null) return const <double>[];
      return raw.map((e) => (e as num).toDouble()).toList(growable: false);
    } on PlatformException catch (e) {
      _logError('getMasterEqWaveform', e);
      return const <double>[];
    }
  }
}
