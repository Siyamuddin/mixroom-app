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

class JuceEngineDiagnostics {
  const JuceEngineDiagnostics({
    required this.sampleRate,
    required this.bufferSize,
    required this.cpuUsage,
    required this.pluginsScanned,
    required this.knownPluginCount,
    required this.pluginScanFailureCount,
    required this.pluginScanFailures,
    required this.rowCount,
    required this.clipCount,
    required this.inputDeviceName,
    required this.outputDeviceName,
    required this.inputChannelCount,
    required this.outputChannelCount,
    this.realtimeCallbackCount = 0,
    this.realtimeCallbackLastMs = 0.0,
    this.realtimeCallbackMaxMs = 0.0,
    this.realtimeCallbackAvgMs = 0.0,
    this.realtimeCallbackBudgetMs = 0.0,
    this.realtimeCallbackOverBudgetCount = 0,
    this.realtimeCallbackMaxSamples = 0,
    this.realtimeGraphRebuildCommittedCount = 0,
    this.realtimeGraphRebuildImmediateCount = 0,
    this.realtimeGraphRebuildDeferredCount = 0,
    this.realtimeGraphRebuildBatchCommitCount = 0,
    this.realtimeGraphRebuildProjectLoadCommitCount = 0,
  });

  final double sampleRate;
  final int bufferSize;
  final double cpuUsage;
  final bool pluginsScanned;
  final int knownPluginCount;
  final int pluginScanFailureCount;
  final List<String> pluginScanFailures;
  final int rowCount;
  final int clipCount;
  final String inputDeviceName;
  final String outputDeviceName;
  final int inputChannelCount;
  final int outputChannelCount;
  final int realtimeCallbackCount;
  final double realtimeCallbackLastMs;
  final double realtimeCallbackMaxMs;
  final double realtimeCallbackAvgMs;
  final double realtimeCallbackBudgetMs;
  final int realtimeCallbackOverBudgetCount;
  final int realtimeCallbackMaxSamples;
  final int realtimeGraphRebuildCommittedCount;
  final int realtimeGraphRebuildImmediateCount;
  final int realtimeGraphRebuildDeferredCount;
  final int realtimeGraphRebuildBatchCommitCount;
  final int realtimeGraphRebuildProjectLoadCommitCount;

  factory JuceEngineDiagnostics.fromMap(Map<String, dynamic> map) {
    return JuceEngineDiagnostics(
      sampleRate: (map['sampleRate'] as num?)?.toDouble() ?? 0.0,
      bufferSize: (map['bufferSize'] as num?)?.toInt() ?? 0,
      cpuUsage: (map['cpuUsage'] as num?)?.toDouble() ?? 0.0,
      pluginsScanned: map['pluginsScanned'] == true,
      knownPluginCount: (map['knownPluginCount'] as num?)?.toInt() ?? 0,
      pluginScanFailureCount:
          (map['pluginScanFailureCount'] as num?)?.toInt() ?? 0,
      pluginScanFailures:
          ((map['pluginScanFailures'] as List?) ?? const <Object?>[])
              .whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false),
      rowCount: (map['rowCount'] as num?)?.toInt() ?? 0,
      clipCount: (map['clipCount'] as num?)?.toInt() ?? 0,
      inputDeviceName: map['inputDeviceName']?.toString() ?? '',
      outputDeviceName: map['outputDeviceName']?.toString() ?? '',
      inputChannelCount: (map['inputChannelCount'] as num?)?.toInt() ?? 0,
      outputChannelCount: (map['outputChannelCount'] as num?)?.toInt() ?? 0,
      realtimeCallbackCount:
          (map['realtimeCallbackCount'] as num?)?.toInt() ?? 0,
      realtimeCallbackLastMs:
          (map['realtimeCallbackLastMs'] as num?)?.toDouble() ?? 0.0,
      realtimeCallbackMaxMs:
          (map['realtimeCallbackMaxMs'] as num?)?.toDouble() ?? 0.0,
      realtimeCallbackAvgMs:
          (map['realtimeCallbackAvgMs'] as num?)?.toDouble() ?? 0.0,
      realtimeCallbackBudgetMs:
          (map['realtimeCallbackBudgetMs'] as num?)?.toDouble() ?? 0.0,
      realtimeCallbackOverBudgetCount:
          (map['realtimeCallbackOverBudgetCount'] as num?)?.toInt() ?? 0,
      realtimeCallbackMaxSamples:
          (map['realtimeCallbackMaxSamples'] as num?)?.toInt() ?? 0,
      realtimeGraphRebuildCommittedCount:
          (map['realtimeGraphRebuildCommittedCount'] as num?)?.toInt() ?? 0,
      realtimeGraphRebuildImmediateCount:
          (map['realtimeGraphRebuildImmediateCount'] as num?)?.toInt() ?? 0,
      realtimeGraphRebuildDeferredCount:
          (map['realtimeGraphRebuildDeferredCount'] as num?)?.toInt() ?? 0,
      realtimeGraphRebuildBatchCommitCount:
          (map['realtimeGraphRebuildBatchCommitCount'] as num?)?.toInt() ?? 0,
      realtimeGraphRebuildProjectLoadCommitCount:
          (map['realtimeGraphRebuildProjectLoadCommitCount'] as num?)
                  ?.toInt() ??
              0,
    );
  }
}

enum AudioRouteKind {
  unknown,
  speaker,
  earpiece,
  wired,
  usb,
  bluetoothOutput,
  bluetoothHeadsetMic,
}

AudioRouteKind _audioRouteKindFromString(String value) {
  switch (value) {
    case 'speaker':
      return AudioRouteKind.speaker;
    case 'earpiece':
      return AudioRouteKind.earpiece;
    case 'wired':
      return AudioRouteKind.wired;
    case 'usb':
      return AudioRouteKind.usb;
    case 'bluetoothOutput':
      return AudioRouteKind.bluetoothOutput;
    case 'bluetoothHeadsetMic':
      return AudioRouteKind.bluetoothHeadsetMic;
    default:
      return AudioRouteKind.unknown;
  }
}

class AudioRouteInfo {
  const AudioRouteInfo({
    required this.outputRouteKind,
    required this.outputRouteName,
    required this.inputDeviceName,
    required this.inputIsBluetoothHeadset,
  });

  final AudioRouteKind outputRouteKind;
  final String outputRouteName;
  final String inputDeviceName;
  final bool inputIsBluetoothHeadset;

  bool get isBluetoothOutput =>
      outputRouteKind == AudioRouteKind.bluetoothOutput;

  factory AudioRouteInfo.fromMap(Map<String, dynamic> map) {
    return AudioRouteInfo(
      outputRouteKind: _audioRouteKindFromString(
        map['outputRouteKind']?.toString() ?? '',
      ),
      outputRouteName: map['outputRouteName']?.toString() ?? '',
      inputDeviceName: map['inputDeviceName']?.toString() ?? '',
      inputIsBluetoothHeadset: map['inputIsBluetoothHeadset'] == true,
    );
  }

  static const unknown = AudioRouteInfo(
    outputRouteKind: AudioRouteKind.unknown,
    outputRouteName: '',
    inputDeviceName: '',
    inputIsBluetoothHeadset: false,
  );
}

class AudioInputDeviceInfo {
  const AudioInputDeviceInfo({
    required this.name,
    required this.isBluetoothInput,
    required this.isBuiltIn,
    required this.isDefault,
    required this.transport,
  });

  final String name;
  final bool isBluetoothInput;
  final bool isBuiltIn;
  final bool isDefault;
  final String transport;

  factory AudioInputDeviceInfo.fromMap(Map<String, dynamic> map) {
    return AudioInputDeviceInfo(
      name: map['name']?.toString() ?? '',
      isBluetoothInput: map['isBluetoothInput'] == true,
      isBuiltIn: map['isBuiltIn'] == true,
      isDefault: map['isDefault'] == true,
      transport: map['transport']?.toString() ?? 'unknown',
    );
  }
}

class JuceAudioEngine {
  static const _ch = MethodChannel('juce_audio_engine');
  static const _eventCh = EventChannel('juce_audio_engine/events');

  static Stream<Map<String, dynamic>> get _events => _eventCh
      .receiveBroadcastStream()
      .cast<Map<dynamic, dynamic>>()
      .map((e) => Map<String, dynamic>.from(e));

  static Stream<Map<String, dynamic>> get eventsStream => _events;

  static void initialiseEventListeners() {
    try {
      _events.listen(
        (event) {
          if (event['event'] == 'pluginLoaded') {
            final track = event['track'] as int;
            final path = event['path'] as String;
            final success = event['success'] as bool;
            debugPrint("Plugin loaded: $success for $path on track $track");
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (error is MissingPluginException || error is PlatformException) {
            _logError('initialiseEventListeners', error);
            return;
          }
          _logError('initialiseEventListeners', error);
        },
      );
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      _logError('initialiseEventListeners', e);
    }
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

  static Future<String?> renderPitchLabAudio({
    required String sourcePath,
    required String outPath,
    required double trimStartMs,
    required double trimEndMs,
    required double sourceTimelineDurationMs,
    required double outputDurationMs,
    required List<Map<String, double>> suppressedRanges,
    required List<Map<String, double>> segments,
  }) async {
    try {
      return await _ch.invokeMethod<String>('renderPitchLabAudio', {
        'sourcePath': sourcePath,
        'outPath': outPath,
        'trimStartMs': trimStartMs,
        'trimEndMs': trimEndMs,
        'sourceTimelineDurationMs': sourceTimelineDurationMs,
        'outputDurationMs': outputDurationMs,
        'suppressedRanges': suppressedRanges,
        'segments': segments,
      });
    } on PlatformException catch (e) {
      _logError('renderPitchLabAudio', e);
      return null;
    } on MissingPluginException catch (e) {
      _logError('renderPitchLabAudio', e);
      return null;
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

  static Future<bool> play() async {
    try {
      final res = await _ch.invokeMethod<bool>('play');
      return res ?? true;
    } on PlatformException catch (e) {
      _logError('play', e);
      return false;
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
    } on MissingPluginException catch (e) {
      _logError('getPluginParameters', e);
      return <Map<String, dynamic>>[];
    } on PlatformException catch (e) {
      _logError('getPluginParameters', e);
      return <Map<String, dynamic>>[];
    }
  }

  static Future<List<Map<String, dynamic>>> getTrackPluginParameters(
    int row,
    int effectIndex, {
    bool forceIndividualRow = false,
  }) async {
    try {
      final rawList = await _ch.invokeMethod<List<dynamic>>(
        'getTrackPluginParameters',
        {
          'row': row,
          'effect': effectIndex,
          if (forceIndividualRow) 'forceIndividualRow': true,
        },
      );
      if (rawList == null) return [];

      return rawList.map((item) {
        return Map<String, dynamic>.from(item as Map);
      }).toList();
    } on MissingPluginException catch (e) {
      _logError('getTrackPluginParameters', e);
      return <Map<String, dynamic>>[];
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
    } on MissingPluginException catch (e) {
      _logError('getMasterPluginParameters', e);
      return <Map<String, dynamic>>[];
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
          nativePluginEditor: true,
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

  static Future<List<Map<String, dynamic>>> scanPlugins({
    List<String>? searchPaths,
  }) async {
    try {
      final result = await _ch.invokeMethod<List<dynamic>>('scanPlugins', {
        if (searchPaths != null) 'searchPaths': searchPaths,
      });
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
        if (raw['isInstrument'] is bool) {
          out['isInstrument'] = raw['isInstrument'] == true;
        }
        if (raw['quarantined'] is bool) {
          out['quarantined'] = raw['quarantined'] == true;
        }

        normalized.add(out);
      }
      return normalized;
    } on MissingPluginException catch (e) {
      _logError('scanPlugins', e);
      return <Map<String, dynamic>>[];
    } on PlatformException catch (e) {
      _logError('scanPlugins', e);
      return <Map<String, dynamic>>[];
    }
  }

  static Future<List<Map<String, dynamic>>> rescanPlugins({
    List<String>? searchPaths,
  }) async {
    try {
      final result = await _ch.invokeMethod<List<dynamic>>('rescanPlugins', {
        if (searchPaths != null) 'searchPaths': searchPaths,
      });
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
        if (raw['isInstrument'] is bool) {
          out['isInstrument'] = raw['isInstrument'] == true;
        }
        if (raw['quarantined'] is bool) {
          out['quarantined'] = raw['quarantined'] == true;
        }

        normalized.add(out);
      }
      return normalized;
    } on MissingPluginException catch (e) {
      _logError('rescanPlugins', e);
      return <Map<String, dynamic>>[];
    } on PlatformException catch (e) {
      _logError('rescanPlugins', e);
      return <Map<String, dynamic>>[];
    }
  }

  static Future<List<Map<String, dynamic>>> getQuarantinedPlugins() async {
    try {
      final result =
          await _ch.invokeMethod<List<dynamic>>('getQuarantinedPlugins');
      if (result == null) return <Map<String, dynamic>>[];
      return result
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    } on MissingPluginException catch (e) {
      _logError('getQuarantinedPlugins', e);
      return <Map<String, dynamic>>[];
    } on PlatformException catch (e) {
      _logError('getQuarantinedPlugins', e);
      return <Map<String, dynamic>>[];
    }
  }

  static Future<bool> isPluginQuarantined(String pluginId) async {
    final trimmed = pluginId.trim();
    if (trimmed.isEmpty) return false;
    try {
      final result = await _ch.invokeMethod<bool>('isPluginQuarantined', {
        'pluginId': trimmed,
      });
      return result == true;
    } on MissingPluginException catch (e) {
      _logError('isPluginQuarantined', e);
      return false;
    } on PlatformException catch (e) {
      _logError('isPluginQuarantined', e);
      return false;
    }
  }

  static Future<void> clearPluginQuarantine(String pluginId) async {
    final trimmed = pluginId.trim();
    if (trimmed.isEmpty) return;
    try {
      await _ch.invokeMethod<void>('clearPluginQuarantine', {
        'pluginId': trimmed,
      });
    } on MissingPluginException catch (e) {
      _logError('clearPluginQuarantine', e);
    } on PlatformException catch (e) {
      _logError('clearPluginQuarantine', e);
    }
  }

  static Future<void> clearAllPluginQuarantines() async {
    try {
      await _ch.invokeMethod<void>('clearAllPluginQuarantines');
    } on MissingPluginException catch (e) {
      _logError('clearAllPluginQuarantines', e);
    } on PlatformException catch (e) {
      _logError('clearAllPluginQuarantines', e);
    }
  }

  static Future<JuceEngineDiagnostics> getEngineDiagnostics() async {
    try {
      final raw = await _ch.invokeMethod<Map<dynamic, dynamic>>(
        'getEngineDiagnostics',
      );
      if (raw == null) {
        return const JuceEngineDiagnostics(
          sampleRate: 0.0,
          bufferSize: 0,
          cpuUsage: 0.0,
          pluginsScanned: false,
          knownPluginCount: 0,
          pluginScanFailureCount: 0,
          pluginScanFailures: <String>[],
          rowCount: 0,
          clipCount: 0,
          inputDeviceName: '',
          outputDeviceName: '',
          inputChannelCount: 0,
          outputChannelCount: 0,
        );
      }
      return JuceEngineDiagnostics.fromMap(Map<String, dynamic>.from(raw));
    } on MissingPluginException catch (e) {
      _logError('getEngineDiagnostics', e);
      return const JuceEngineDiagnostics(
        sampleRate: 0.0,
        bufferSize: 0,
        cpuUsage: 0.0,
        pluginsScanned: false,
        knownPluginCount: 0,
        pluginScanFailureCount: 0,
        pluginScanFailures: <String>[],
        rowCount: 0,
        clipCount: 0,
        inputDeviceName: '',
        outputDeviceName: '',
        inputChannelCount: 0,
        outputChannelCount: 0,
      );
    } on PlatformException catch (e) {
      _logError('getEngineDiagnostics', e);
      return const JuceEngineDiagnostics(
        sampleRate: 0.0,
        bufferSize: 0,
        cpuUsage: 0.0,
        pluginsScanned: false,
        knownPluginCount: 0,
        pluginScanFailureCount: 0,
        pluginScanFailures: <String>[],
        rowCount: 0,
        clipCount: 0,
        inputDeviceName: '',
        outputDeviceName: '',
        inputChannelCount: 0,
        outputChannelCount: 0,
      );
    }
  }

  static Future<void> resetRealtimePerformanceStats() async {
    try {
      await _ch.invokeMethod<void>('resetRealtimePerformanceStats');
    } on MissingPluginException catch (e) {
      _logError('resetRealtimePerformanceStats', e);
    } on PlatformException catch (e) {
      _logError('resetRealtimePerformanceStats', e);
    }
  }

  static Future<Map<String, dynamic>> runEngineStressTest({
    int clipCount = 256,
    int blockCount = 1024,
    int blockSize = 512,
    double sampleRate = 48000.0,
  }) async {
    try {
      final raw = await _ch.invokeMethod<Map<dynamic, dynamic>>(
        'runEngineStressTest',
        <String, dynamic>{
          'clipCount': clipCount,
          'blockCount': blockCount,
          'blockSize': blockSize,
          'sampleRate': sampleRate,
        },
      );
      return raw == null ? <String, dynamic>{} : Map<String, dynamic>.from(raw);
    } on MissingPluginException catch (e) {
      _logError('runEngineStressTest', e);
      return <String, dynamic>{};
    } on PlatformException catch (e) {
      _logError('runEngineStressTest', e);
      return <String, dynamic>{};
    }
  }

  static Future<String> exportMix(
    String outPath, {
    String format = 'wav',
    int sampleRate = 44100,
    int wavBitDepth = 16,
    bool wavDithering = true,
    int mp3BitrateKbps = 192,
    String? clipSnapshotJson,
    bool dryClipRender = false,
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
          'dryClipRender': dryClipRender,
          if (clipSnapshotJson != null && clipSnapshotJson.isNotEmpty)
            'clipSnapshotJson': clipSnapshotJson,
        },
      );
      return result ?? '';
    } on PlatformException catch (e) {
      _logError('exportMix', e);
      return '';
    }
  }

  static Future<double> getExportProgress() async {
    try {
      final progress = await _ch.invokeMethod<double>('getExportProgress');
      return (progress ?? 0.0).clamp(0.0, 1.0);
    } on PlatformException catch (e) {
      _logError('getExportProgress', e);
      return 0.0;
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

  static Future<bool> setDesktopKeyboardMidiForwardingEnabled(
      bool enabled) async {
    try {
      final ok = await _ch.invokeMethod<bool>(
        'setDesktopKeyboardMidiForwardingEnabled',
        {'enabled': enabled},
      );
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      _logError('setDesktopKeyboardMidiForwardingEnabled', e);
      return false;
    }
  }

  static Future<bool> sendLiveMidiInputEvent({
    required bool noteOn,
    required int channel,
    required int pitch,
    required double velocity,
  }) async {
    try {
      final ok = await _ch.invokeMethod<bool>('sendLiveMidiInputEvent', {
        'noteOn': noteOn,
        'channel': channel.clamp(1, 16),
        'pitch': pitch.clamp(0, 127),
        'velocity': velocity.clamp(0.0, 1.0),
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      _logError('sendLiveMidiInputEvent', e);
      return false;
    }
  }

  static Future<bool> playPreviewMidiNote(
    int clipIndex, {
    required int pitch,
    required double velocity,
    int durationMs = 220,
  }) async {
    try {
      final ok = await _ch.invokeMethod<bool>('playPreviewMidiNote', {
        'clip': clipIndex,
        'pitch': pitch,
        'velocity': velocity.clamp(0.0, 1.0),
        'durationMs': durationMs,
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      _logError('playPreviewMidiNote', e);
      return false;
    }
  }

  static Future<bool> openMidiClipPluginEditor(int clipIndex) async {
    try {
      final opened = await _ch.invokeMethod<bool>('openMidiClipPluginEditor', {
        'clip': clipIndex,
      });
      return opened ?? false;
    } on MissingPluginException catch (e) {
      _logError('openMidiClipPluginEditor', e);
      return false;
    } on PlatformException catch (e) {
      _logError('openMidiClipPluginEditor', e);
      return false;
    }
  }

  static Future<void> setMidiClipPluginParameter(
    int clipIndex,
    String paramId,
    double normalizedValue,
  ) async {
    try {
      await _ch.invokeMethod('setMidiClipPluginParameter', {
        'clip': clipIndex,
        'paramId': paramId,
        'value': normalizedValue.clamp(0.0, 1.0),
      });
    } on PlatformException catch (e) {
      _logError('setMidiClipPluginParameter', e);
    }
  }

  static Future<void> setMidiClipPluginAutomationPoints(
    int clipIndex,
    String paramId,
    List<Map<String, dynamic>> points,
  ) async {
    try {
      await _ch.invokeMethod('setMidiClipPluginAutomationPoints', {
        'clip': clipIndex,
        'paramId': paramId,
        'points': points,
      });
    } on PlatformException catch (e) {
      _logError('setMidiClipPluginAutomationPoints', e);
    }
  }

  static Future<void> clearMidiClipPluginAutomation(int clipIndex) async {
    try {
      await _ch.invokeMethod('clearMidiClipPluginAutomation', {
        'clip': clipIndex,
      });
    } on PlatformException catch (e) {
      _logError('clearMidiClipPluginAutomation', e);
    }
  }

  static Future<String> getMidiClipPluginState(int clipIndex) async {
    try {
      final state = await _ch.invokeMethod<String>('getMidiClipPluginState', {
        'clip': clipIndex,
      });
      return state ?? '';
    } on MissingPluginException catch (e) {
      _logError('getMidiClipPluginState', e);
      return '';
    } on PlatformException catch (e) {
      _logError('getMidiClipPluginState', e);
      return '';
    }
  }

  static Future<bool> setMidiClipPluginState(
    int clipIndex, {
    required String stateBase64,
  }) async {
    try {
      final applied = await _ch.invokeMethod<bool>('setMidiClipPluginState', {
        'clip': clipIndex,
        'stateBase64': stateBase64,
      });
      return applied ?? false;
    } on MissingPluginException catch (e) {
      _logError('setMidiClipPluginState', e);
      return false;
    } on PlatformException catch (e) {
      _logError('setMidiClipPluginState', e);
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

  static Future<void> beginProjectClipLoad() async {
    try {
      await _ch.invokeMethod('beginProjectClipLoad');
    } on PlatformException catch (e) {
      _logError('beginProjectClipLoad', e);
    }
  }

  static Future<void> endProjectClipLoad() async {
    try {
      await _ch.invokeMethod('endProjectClipLoad');
    } on PlatformException catch (e) {
      _logError('endProjectClipLoad', e);
    }
  }

  static Future<void> beginGraphMutationBatch() async {
    try {
      await _ch.invokeMethod('beginGraphMutationBatch');
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      _logError('beginGraphMutationBatch', e);
    }
  }

  static Future<void> endGraphMutationBatch() async {
    try {
      await _ch.invokeMethod('endGraphMutationBatch');
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      _logError('endGraphMutationBatch', e);
    }
  }

  static Future<String?> getBundledInstrumentRootPath() async {
    try {
      return await _ch.invokeMethod<String>('getBundledInstrumentRootPath');
    } on PlatformException catch (e) {
      _logError('getBundledInstrumentRootPath', e);
      return null;
    }
  }

  static Future<List<String>> mountBundledSamplePacks() async {
    try {
      final raw =
          await _ch.invokeMethod<List<dynamic>>('mountBundledSamplePacks');
      if (raw == null) return const <String>[];
      return raw
          .map((entry) => entry?.toString().trim() ?? '')
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    } on PlatformException catch (e) {
      _logError('mountBundledSamplePacks', e);
      return const <String>[];
    }
  }

  // ===============================
  // NEW CLIP-LEVEL API
  // ===============================
  static Future<bool> loadClip(
    int clipIndex,
    int rowId,
    String path, {
    double startSec = 0.0,
    double lengthSec = 0.0,
    double inFileOffsetSec = 0.0,
  }) async {
    try {
      final ok = await _ch.invokeMethod<bool>('loadClip', {
        'clip': clipIndex,
        'rowId': rowId,
        'row': rowId, // backward compatibility
        'path': path,
        'startSec': startSec,
        'lengthSec': lengthSec,
        'inFileOffsetSec': inFileOffsetSec,
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      _logError('loadClip', e);
      return false;
    }
  }

  static Future<void> unloadClip(int clipIndex) async {
    try {
      await _ch.invokeMethod('unloadClip', {'clip': clipIndex});
    } on PlatformException catch (e) {
      _logError('unloadClip', e);
    }
  }

  static Future<int> unloadClips(Iterable<int> clipIndices) async {
    final clips = clipIndices.where((clip) => clip >= 0).toSet().toList();
    if (clips.isEmpty) return 0;
    try {
      final removed = await _ch.invokeMethod<int>('unloadClips', {
        'clips': clips,
      });
      return removed ?? 0;
    } on MissingPluginException {
      for (final clip in clips) {
        await unloadClip(clip);
      }
      return clips.length;
    } on PlatformException catch (e) {
      _logError('unloadClips', e);
      for (final clip in clips) {
        await unloadClip(clip);
      }
      return clips.length;
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

  static Future<void> setClipExtraGainLinear(
      int clipIndex, double gainLinear) async {
    try {
      await _ch.invokeMethod('setClipExtraGainLinear', {
        'clip': clipIndex,
        'gain': gainLinear,
      });
    } on PlatformException catch (e) {
      _logError('setClipExtraGainLinear', e);
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

  static Future<void> setClipReversed(int clipIndex, bool reversed) async {
    try {
      await _ch.invokeMethod('setClipReversed', {
        'clip': clipIndex,
        'reversed': reversed,
      });
    } on PlatformException catch (e) {
      _logError('setClipReversed', e);
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

  static Future<int> updateClipTimelineBatch(
    List<Map<String, dynamic>> updates,
  ) async {
    if (updates.isEmpty) return 0;
    try {
      final applied = await _ch.invokeMethod<int>('updateClipTimelineBatch', {
        'updates': updates,
      });
      return applied ?? 0;
    } on PlatformException catch (e) {
      _logError('updateClipTimelineBatch', e);
      return 0;
    }
  }

  static Future<void> setClipFades(
    int clipIndex, {
    required double fadeInSec,
    required double fadeOutSec,
    int fadeCurve = 0,
  }) async {
    try {
      await _ch.invokeMethod('setClipFades', {
        'clip': clipIndex,
        'fadeInSec': fadeInSec,
        'fadeOutSec': fadeOutSec,
        'fadeCurve': fadeCurve,
      });
    } on PlatformException catch (e) {
      _logError('setClipFades', e);
    }
  }

  static Future<int> updateClipFadesBatch(
    List<Map<String, dynamic>> updates,
  ) async {
    if (updates.isEmpty) return 0;
    try {
      final applied = await _ch.invokeMethod<int>('updateClipFadesBatch', {
        'updates': updates,
      });
      return applied ?? 0;
    } on MissingPluginException {
      for (final update in updates) {
        await setClipFades(
          (update['clip'] as num).toInt(),
          fadeInSec: (update['fadeInSec'] as num?)?.toDouble() ?? 0.0,
          fadeOutSec: (update['fadeOutSec'] as num?)?.toDouble() ?? 0.0,
          fadeCurve: (update['fadeCurve'] as num?)?.toInt() ?? 0,
        );
      }
      return updates.length;
    } on PlatformException catch (e) {
      _logError('updateClipFadesBatch', e);
      for (final update in updates) {
        await setClipFades(
          (update['clip'] as num).toInt(),
          fadeInSec: (update['fadeInSec'] as num?)?.toDouble() ?? 0.0,
          fadeOutSec: (update['fadeOutSec'] as num?)?.toDouble() ?? 0.0,
          fadeCurve: (update['fadeCurve'] as num?)?.toInt() ?? 0,
        );
      }
      return updates.length;
    }
  }

  static Future<int> addRow(
    String name, {
    int iconId = 0,
    int? preferredRowId,
  }) async {
    try {
      final id = await _ch.invokeMethod<int>('addRow', {
        'name': name,
        'iconId': iconId,
        if (preferredRowId != null) 'preferredRowId': preferredRowId,
      });
      return id ?? -1;
    } on PlatformException catch (e) {
      _logError('addRow', e);
      return -1;
    }
  }

  static Future<int> insertRowAbove(
    int referenceRowId,
    String name, {
    int iconId = 0,
    int? preferredRowId,
  }) async {
    try {
      final id = await _ch.invokeMethod<int>('insertRowAbove', {
        'referenceRowId': referenceRowId,
        'name': name,
        'iconId': iconId,
        if (preferredRowId != null) 'preferredRowId': preferredRowId,
      });
      return id ?? -1;
    } on PlatformException catch (e) {
      _logError('insertRowAbove', e);
      return -1;
    }
  }

  static Future<int> insertRowBelow(
    int referenceRowId,
    String name, {
    int iconId = 0,
    int? preferredRowId,
  }) async {
    try {
      final id = await _ch.invokeMethod<int>('insertRowBelow', {
        'referenceRowId': referenceRowId,
        'name': name,
        'iconId': iconId,
        if (preferredRowId != null) 'preferredRowId': preferredRowId,
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
  static Future<bool> insertTrackEffect(
    int row,
    String path, {
    bool forceIndividualRow = false,
  }) async {
    try {
      final ok = await _ch.invokeMethod<bool>('insertTrackEffect', {
        'row': row,
        'path': path,
        if (forceIndividualRow) 'forceIndividualRow': true,
      });
      return ok ?? false;
    } on MissingPluginException catch (e) {
      _logError('insertTrackEffect', e);
      return false;
    } on PlatformException catch (e) {
      _logError('insertTrackEffect', e);
      return false;
    }
  }

  static Future<void> removeTrackEffect(
    int row,
    int effectIndex, {
    bool forceIndividualRow = false,
  }) async {
    try {
      await _ch.invokeMethod('removeTrackEffect', {
        'row': row,
        'effect': effectIndex,
        if (forceIndividualRow) 'forceIndividualRow': true,
      });
    } on MissingPluginException catch (e) {
      _logError('removeTrackEffect', e);
    } on PlatformException catch (e) {
      _logError('removeTrackEffect', e);
    }
  }

  static Future<void> reorderTrackEffects(
    int row,
    int from,
    int to, {
    bool forceIndividualRow = false,
  }) async {
    try {
      await _ch.invokeMethod('reorderTrackEffects', {
        'row': row,
        'from': from,
        'to': to,
        if (forceIndividualRow) 'forceIndividualRow': true,
      });
    } on MissingPluginException catch (e) {
      _logError('reorderTrackEffects', e);
    } on PlatformException catch (e) {
      _logError('reorderTrackEffects', e);
    }
  }

  static Future<List<String>> getTrackEffectsForRow(
    int row, {
    bool forceIndividualRow = false,
  }) async {
    try {
      final list = await _ch.invokeListMethod<String>(
        'getTrackEffectsForRow',
        {
          'row': row,
          if (forceIndividualRow) 'forceIndividualRow': true,
        },
      );
      return list ?? <String>[];
    } on MissingPluginException catch (e) {
      _logError('getTrackEffectsForRow', e);
      return <String>[];
    } on PlatformException catch (e) {
      _logError('getTrackEffectsForRow', e);
      return <String>[];
    }
  }

  static Future<List<String>> getTrackEffectIdsForRow(
    int row, {
    bool forceIndividualRow = false,
  }) async {
    try {
      final list = await _ch.invokeListMethod<String>(
        'getTrackEffectIdsForRow',
        {
          'row': row,
          if (forceIndividualRow) 'forceIndividualRow': true,
        },
      );
      return list ?? <String>[];
    } on MissingPluginException catch (e) {
      _logError('getTrackEffectIdsForRow', e);
      return <String>[];
    } on PlatformException catch (e) {
      _logError('getTrackEffectIdsForRow', e);
      return <String>[];
    }
  }

  static Future<List<String>> getTrackEffectInstanceIdsForRow(
    int row, {
    bool forceIndividualRow = false,
  }) async {
    try {
      final list = await _ch.invokeListMethod<String>(
        'getTrackEffectInstanceIdsForRow',
        {
          'row': row,
          if (forceIndividualRow) 'forceIndividualRow': true,
        },
      );
      return list ?? <String>[];
    } on MissingPluginException catch (e) {
      _logError('getTrackEffectInstanceIdsForRow', e);
      return <String>[];
    } on PlatformException catch (e) {
      _logError('getTrackEffectInstanceIdsForRow', e);
      return <String>[];
    }
  }

  static Future<String> getTrackEffectState(
    int row,
    int effectIndex, {
    bool forceIndividualRow = false,
  }) async {
    try {
      final state = await _ch.invokeMethod<String>('getTrackEffectState', {
        'row': row,
        'effect': effectIndex,
        if (forceIndividualRow) 'forceIndividualRow': true,
      });
      return (state ?? '').trim();
    } on MissingPluginException catch (e) {
      _logError('getTrackEffectState', e);
      return '';
    } on PlatformException catch (e) {
      _logError('getTrackEffectState', e);
      return '';
    }
  }

  static Future<bool> setTrackEffectState(
    int row,
    int effectIndex, {
    required String stateBase64,
    bool forceIndividualRow = false,
  }) async {
    try {
      final applied = await _ch.invokeMethod<bool>('setTrackEffectState', {
        'row': row,
        'effect': effectIndex,
        'stateBase64': stateBase64,
        if (forceIndividualRow) 'forceIndividualRow': true,
      });
      return applied ?? false;
    } on MissingPluginException catch (e) {
      _logError('setTrackEffectState', e);
      return false;
    } on PlatformException catch (e) {
      _logError('setTrackEffectState', e);
      return false;
    }
  }

  static Future<bool> openTrackPluginEditor(int row, int effectIndex) async {
    try {
      final opened = await _ch.invokeMethod<bool>('openTrackPluginEditor', {
        'row': row,
        'effect': effectIndex,
      });
      return opened ?? false;
    } on MissingPluginException catch (e) {
      _logError('openTrackPluginEditor', e);
      return false;
    } on PlatformException catch (e) {
      _logError('openTrackPluginEditor', e);
      return false;
    }
  }

  static Future<void> setTrackEffect(
    int row,
    int effectIndex,
    String paramId,
    dynamic value, {
    bool forceIndividualRow = false,
  }) async {
    try {
      await _ch.invokeMethod('setTrackEffect', {
        'row': row,
        'effect': effectIndex,
        'paramId': paramId,
        'value': value,
        if (forceIndividualRow) 'forceIndividualRow': true,
      });
    } on MissingPluginException catch (e) {
      _logError('setTrackEffect', e);
    } on PlatformException catch (e) {
      _logError('setTrackEffect', e);
    }
  }

  static Future<void> bypassRowEffect(
    int row,
    int effectIndex,
    bool bypass, {
    bool forceIndividualRow = false,
  }) async {
    try {
      await _ch.invokeMethod('bypassRowEffect', {
        'row': row,
        'effect': effectIndex,
        'bypass': bypass,
        if (forceIndividualRow) 'forceIndividualRow': true,
      });
    } on MissingPluginException catch (e) {
      _logError('bypassRowEffect', e);
    } on PlatformException catch (e) {
      _logError('bypassRowEffect', e);
    }
  }

  static Future<bool> getRowEffectBypassState(
    int row,
    int effectIndex, {
    bool forceIndividualRow = false,
  }) async {
    try {
      final res = await _ch.invokeMethod<bool>(
        'getRowEffectBypassState',
        {
          'row': row,
          'effect': effectIndex,
          if (forceIndividualRow) 'forceIndividualRow': true,
        },
      );
      return res ?? false;
    } on MissingPluginException catch (e) {
      _logError('getRowEffectBypassState', e);
      return false;
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

  static Future<void> setRowGainAutomationPoints(
    int row,
    List<Map<String, dynamic>> points,
  ) async {
    try {
      await _ch.invokeMethod('setRowGainAutomationPoints', {
        'row': row,
        'points': points,
      });
    } on PlatformException catch (e) {
      _logError('setRowGainAutomationPoints', e);
    }
  }

  static Future<void> setRowPanAutomationPoints(
    int row,
    List<Map<String, dynamic>> points,
  ) async {
    try {
      await _ch.invokeMethod('setRowPanAutomationPoints', {
        'row': row,
        'points': points,
      });
    } on PlatformException catch (e) {
      _logError('setRowPanAutomationPoints', e);
    }
  }

  static Future<void> configureTrackGroups(
    List<Map<String, dynamic>> groups,
  ) async {
    try {
      await _ch.invokeMethod('configureTrackGroups', {'groups': groups});
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      _logError('configureTrackGroups', e);
    }
  }

  static Future<void> assignRowToGroup(int row, String? groupId) async {
    try {
      await _ch.invokeMethod('assignRowToGroup', {
        'row': row,
        'groupId': groupId ?? '',
      });
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      _logError('assignRowToGroup', e);
    }
  }

  static Future<void> setTrackGroupMixState({
    required String groupId,
    double? gain,
    double? pan,
    bool? muted,
    bool? soloed,
  }) async {
    try {
      await _ch.invokeMethod('setTrackGroupMixState', {
        'groupId': groupId,
        if (gain != null) 'gain': gain,
        if (pan != null) 'pan': pan,
        if (muted != null) 'muted': muted,
        if (soloed != null) 'soloed': soloed,
      });
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      _logError('setTrackGroupMixState', e);
    }
  }

  static Future<void> setTrackGroupEffects(
    String groupId,
    List<Map<String, dynamic>> effects,
  ) async {
    try {
      await _ch.invokeMethod('setTrackGroupEffects', {
        'groupId': groupId,
        'effects': effects,
      });
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      _logError('setTrackGroupEffects', e);
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
  static Future<bool> insertMasterEffect(String path) async {
    try {
      final ok =
          await _ch.invokeMethod<bool>('insertMasterEffect', {'path': path});
      return ok ?? false;
    } on MissingPluginException catch (e) {
      _logError('insertMasterEffect', e);
      return false;
    } on PlatformException catch (e) {
      _logError('insertMasterEffect', e);
      return false;
    }
  }

  static Future<void> removeMasterEffect(int effectIndex) async {
    try {
      await _ch.invokeMethod('removeMasterEffect', {
        'effect': effectIndex,
      });
    } on MissingPluginException catch (e) {
      _logError('removeMasterEffect', e);
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
    } on MissingPluginException catch (e) {
      _logError('reorderMasterEffects', e);
    } on PlatformException catch (e) {
      _logError('reorderMasterEffects', e);
    }
  }

  static Future<List<String>> getMasterEffects() async {
    try {
      final list = await _ch.invokeListMethod<String>('getMasterEffects');
      return list ?? <String>[];
    } on MissingPluginException catch (e) {
      _logError('getMasterEffects', e);
      return <String>[];
    } on PlatformException catch (e) {
      _logError('getMasterEffects', e);
      return <String>[];
    }
  }

  static Future<List<String>> getMasterEffectIds() async {
    try {
      final list = await _ch.invokeListMethod<String>('getMasterEffectIds');
      return list ?? <String>[];
    } on MissingPluginException catch (e) {
      _logError('getMasterEffectIds', e);
      return <String>[];
    } on PlatformException catch (e) {
      _logError('getMasterEffectIds', e);
      return <String>[];
    }
  }

  static Future<String> getMasterEffectState(int effectIndex) async {
    try {
      final state = await _ch.invokeMethod<String>('getMasterEffectState', {
        'effect': effectIndex,
      });
      return (state ?? '').trim();
    } on MissingPluginException catch (e) {
      _logError('getMasterEffectState', e);
      return '';
    } on PlatformException catch (e) {
      _logError('getMasterEffectState', e);
      return '';
    }
  }

  static Future<bool> setMasterEffectState(
    int effectIndex, {
    required String stateBase64,
  }) async {
    try {
      final applied = await _ch.invokeMethod<bool>('setMasterEffectState', {
        'effect': effectIndex,
        'stateBase64': stateBase64,
      });
      return applied ?? false;
    } on MissingPluginException catch (e) {
      _logError('setMasterEffectState', e);
      return false;
    } on PlatformException catch (e) {
      _logError('setMasterEffectState', e);
      return false;
    }
  }

  static Future<bool> openMasterPluginEditor(int effectIndex) async {
    try {
      final opened = await _ch.invokeMethod<bool>('openMasterPluginEditor', {
        'effect': effectIndex,
      });
      return opened ?? false;
    } on MissingPluginException catch (e) {
      _logError('openMasterPluginEditor', e);
      return false;
    } on PlatformException catch (e) {
      _logError('openMasterPluginEditor', e);
      return false;
    }
  }

  static Future<void> setHostedPluginWindowsDetached(bool detached) async {
    try {
      await _ch.invokeMethod(
        'setHostedPluginWindowsDetached',
        {'detached': detached},
      );
    } on MissingPluginException catch (e) {
      _logError('setHostedPluginWindowsDetached', e);
    } on PlatformException catch (e) {
      _logError('setHostedPluginWindowsDetached', e);
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
    } on MissingPluginException catch (e) {
      _logError('setMasterEffect', e);
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
    } on MissingPluginException catch (e) {
      _logError('bypassMasterEffect', e);
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
    } on MissingPluginException catch (e) {
      _logError('getMasterEffectBypassState', e);
      return false;
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

  static Future<void> setMasterGainAutomationPoints(
    List<Map<String, dynamic>> points,
  ) async {
    try {
      await _ch.invokeMethod('setMasterGainAutomationPoints', {
        'points': points,
      });
    } on PlatformException catch (e) {
      _logError('setMasterGainAutomationPoints', e);
    }
  }

  static Future<void> setMasterPanAutomationPoints(
    List<Map<String, dynamic>> points,
  ) async {
    try {
      await _ch.invokeMethod('setMasterPanAutomationPoints', {
        'points': points,
      });
    } on PlatformException catch (e) {
      _logError('setMasterPanAutomationPoints', e);
    }
  }

  static Future<void> setMasterEffectAutomationPoints(
    int effectIndex,
    String paramId,
    double minValue,
    double maxValue,
    List<Map<String, dynamic>> points,
  ) async {
    try {
      await _ch.invokeMethod('setMasterEffectAutomationPoints', {
        'effect': effectIndex,
        'paramId': paramId,
        'min': minValue,
        'max': maxValue,
        'points': points,
      });
    } on PlatformException catch (e) {
      _logError('setMasterEffectAutomationPoints', e);
    }
  }

  static Future<void> clearMasterEffectAutomation() async {
    try {
      await _ch.invokeMethod('clearMasterEffectAutomation');
    } on PlatformException catch (e) {
      _logError('clearMasterEffectAutomation', e);
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

  static Future<void> setMetronomeTimeSignature({
    required int numerator,
    required int denominator,
  }) async {
    try {
      await _ch.invokeMethod('setMetronomeTimeSignature', {
        'numerator': numerator,
        'denominator': denominator,
      });
    } on MissingPluginException catch (e) {
      _logError('setMetronomeTimeSignature', e);
    } on PlatformException catch (e) {
      _logError('setMetronomeTimeSignature', e);
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

  static Future<Float32List> decodeAudioMono16kForAnalysis(
    String path, {
    int maxOutputSamples = 480000,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return decodeAudioMono16k(path);
    }

    final List<dynamic> raw = await _ch.invokeMethod(
      'decodeAudioMono16kForAnalysis',
      {
        'path': path,
        'maxOutputSamples': maxOutputSamples,
      },
    );

    return Float32List.fromList(
      raw.map((e) => (e as num).toDouble()).toList(growable: false),
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

  static Future<Map<String, dynamic>> analyzeAudioForPrompt(
    String path, {
    double trimStartMs = 0.0,
    double? trimEndMs,
  }) async {
    try {
      final raw = await _ch.invokeMapMethod<String, dynamic>(
        'analyzeAudioForPrompt',
        {
          'path': path,
          'trimStartMs': trimStartMs,
          if (trimEndMs != null) 'trimEndMs': trimEndMs,
        },
      );
      return raw == null
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(raw);
    } on MissingPluginException {
      return const <String, dynamic>{};
    } on PlatformException catch (e) {
      _logError('analyzeAudioForPrompt', e);
      return const <String, dynamic>{};
    } catch (_) {
      return const <String, dynamic>{};
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

  static Future<List<String>> getOutputDevices() async {
    try {
      final res = await _ch.invokeMethod<List>('getOutputDevices');
      return (res ?? []).cast<String>();
    } on PlatformException catch (e) {
      _logError('getOutputDevices', e);
      return [];
    }
  }

  static Future<List<AudioInputDeviceInfo>> getInputDeviceInfos() async {
    try {
      final res = await _ch.invokeMethod<List>('getInputDeviceInfos');
      return (res ?? const [])
          .whereType<Map>()
          .map((map) => AudioInputDeviceInfo.fromMap(
                Map<String, dynamic>.from(map),
              ))
          .where((info) => info.name.trim().isNotEmpty)
          .toList(growable: false);
    } on MissingPluginException {
      return const [];
    } on PlatformException catch (e) {
      _logError('getInputDeviceInfos', e);
      return const [];
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

  static Future<bool> selectOutputDevice(String name) async {
    try {
      final res = await _ch.invokeMethod<bool>('selectOutputDevice', {
        'name': name,
      });
      return res ?? false;
    } on PlatformException catch (e) {
      _logError('selectOutputDevice', e);
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

  static Future<bool> prepareRecordingInputs(
    int desiredInputChannels, {
    String reason = 'dart',
  }) async {
    try {
      final res = await _ch.invokeMethod<bool>('prepareRecordingInputs', {
        'desiredInputChannels': desiredInputChannels,
        'reason': reason,
      });
      return res ?? false;
    } on PlatformException catch (e) {
      _logError('prepareRecordingInputs', e);
      return false;
    }
  }

  static Future<bool> configureAudioDevice({
    required int sampleRate,
    required int bufferSize,
    int desiredInputChannels = -1,
    String reason = 'dart',
  }) async {
    try {
      final res = await _ch.invokeMethod<bool>('configureAudioDevice', {
        'sampleRate': sampleRate,
        'bufferSize': bufferSize,
        'desiredInputChannels': desiredInputChannels,
        'reason': reason,
      });
      return res ?? false;
    } on PlatformException catch (e) {
      _logError('configureAudioDevice', e);
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  static Future<void> setMidiInputChannelFilter(int channel) async {
    try {
      await _ch.invokeMethod<void>('setMidiInputChannelFilter', {
        'channel': channel.clamp(0, 16).toInt(),
      });
    } on PlatformException catch (e) {
      _logError('setMidiInputChannelFilter', e);
    } on MissingPluginException catch (_) {}
  }

  static Future<int> getMidiInputChannelFilter() async {
    try {
      final res = await _ch.invokeMethod<int>('getMidiInputChannelFilter');
      return (res ?? 0).clamp(0, 16).toInt();
    } on PlatformException catch (e) {
      _logError('getMidiInputChannelFilter', e);
      return 0;
    } on MissingPluginException catch (_) {
      return 0;
    }
  }

  static Future<bool> preparePlaybackRoute({
    String reason = 'dart',
  }) async {
    try {
      final res = await _ch.invokeMethod<bool>('preparePlaybackRoute', {
        'reason': reason,
      });
      return res ?? false;
    } on PlatformException catch (e) {
      _logError('preparePlaybackRoute', e);
      return false;
    }
  }

  static Future<void> refreshAudioRoute({
    String reason = 'dart',
  }) async {
    try {
      await _ch.invokeMethod('refreshAudioRoute', {
        'reason': reason,
      });
    } on PlatformException catch (e) {
      _logError('refreshAudioRoute', e);
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

  static Future<String> getCurrentOutputDeviceName() async {
    try {
      final res = await _ch.invokeMethod<String>('getCurrentOutputDeviceName');
      return res ?? '';
    } on PlatformException catch (e) {
      _logError('getCurrentOutputDeviceName', e);
      return '';
    }
  }

  static Future<AudioRouteInfo> getAudioRouteInfo() async {
    try {
      final res =
          await _ch.invokeMapMethod<String, dynamic>('getAudioRouteInfo');
      if (res == null) return AudioRouteInfo.unknown;
      return AudioRouteInfo.fromMap(Map<String, dynamic>.from(res));
    } on MissingPluginException {
      return AudioRouteInfo.unknown;
    } on PlatformException catch (e) {
      _logError('getAudioRouteInfo', e);
      return AudioRouteInfo.unknown;
    }
  }

  static Future<void> setLiveInputMonitoringEnabled(bool enabled) async {
    try {
      await _ch.invokeMethod('setLiveInputMonitoringEnabled', {
        'enabled': enabled,
      });
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      _logError('setLiveInputMonitoringEnabled', e);
    }
  }

  static Future<void> setRowMonitorTarget({
    required int row,
    String inputDeviceName = '',
    int channelStart = 0,
    int channelCount = 1,
  }) async {
    try {
      await _ch.invokeMethod('setRowMonitorTarget', {
        'row': row,
        'inputDeviceName': inputDeviceName,
        'channelStart': channelStart,
        'channelCount': channelCount,
      });
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      _logError('setRowMonitorTarget', e);
    }
  }

  static Future<double> getEstimatedRecordingLatencyMs() async {
    try {
      final res = await _ch.invokeMethod<num>('getEstimatedRecordingLatencyMs');
      return (res ?? 0).toDouble();
    } on MissingPluginException {
      return 0.0;
    } on PlatformException catch (e) {
      _logError('getEstimatedRecordingLatencyMs', e);
      return 0.0;
    }
  }

  static Future<void> setClipWarpOptions({
    required int clipIndex,
    required String clipId,
    required String warpMode,
    required bool preservePitch,
    double? sourceTempoBpm,
    double? targetTempoBpm,
  }) async {
    try {
      await _ch.invokeMethod('setClipWarpOptions', {
        'clipIndex': clipIndex,
        'clipId': clipId,
        'warpMode': warpMode,
        'preservePitch': preservePitch,
        if (sourceTempoBpm != null) 'sourceTempoBpm': sourceTempoBpm,
        if (targetTempoBpm != null) 'targetTempoBpm': targetTempoBpm,
      });
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      _logError('setClipWarpOptions', e);
    }
  }

  static Future<String> renderEnhancedAudioCache({
    required String inputPath,
    required String outputPath,
    required String preset,
    Map<String, dynamic> options = const <String, dynamic>{},
  }) async {
    try {
      final res = await _ch.invokeMethod<String>('renderEnhancedAudioCache', {
        'inputPath': inputPath,
        'outputPath': outputPath,
        'preset': preset,
        'options': options,
      });
      return res ?? '';
    } on MissingPluginException {
      return '';
    } on PlatformException catch (e) {
      _logError('renderEnhancedAudioCache', e);
      return '';
    }
  }

  static Future<bool> preferNonBluetoothRecordingInput() async {
    try {
      final res =
          await _ch.invokeMethod<bool>('preferNonBluetoothRecordingInput');
      return res ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      _logError('preferNonBluetoothRecordingInput', e);
      return false;
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

  static Future<void> stopRecordingWithoutPlaybackRestore() async {
    try {
      await _ch.invokeMethod('stopRecordingWithoutPlaybackRestore');
    } on MissingPluginException {
      await stopRecording();
    } on PlatformException catch (e) {
      _logError('stopRecordingWithoutPlaybackRestore', e);
    }
  }

  static Future<void> restoreBluetoothPlaybackAfterRecordingStop() async {
    try {
      await _ch.invokeMethod('restoreBluetoothPlaybackAfterRecordingStop');
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      _logError('restoreBluetoothPlaybackAfterRecordingStop', e);
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

  static Future<List<double>> getRecentMasterWaveform({
    int sampleCount = 2048,
  }) async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>(
        'getRecentMasterWaveform',
        {'sampleCount': sampleCount},
      );
      if (raw == null) return const <double>[];
      return raw.map((e) => (e as num).toDouble()).toList(growable: false);
    } on PlatformException catch (e) {
      _logError('getRecentMasterWaveform', e);
      return const <double>[];
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

  static Future<List<double>> getRowStereoScope(
    int row,
    int effect, {
    int pointCount = 256,
  }) async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>(
        'getRowStereoScope',
        {'row': row, 'effect': effect, 'pointCount': pointCount},
      );
      if (raw == null) return const <double>[];
      return raw.map((e) => (e as num).toDouble()).toList(growable: false);
    } on PlatformException catch (e) {
      _logError('getRowStereoScope', e);
      return const <double>[];
    }
  }

  static Future<List<double>> getMasterStereoScope(
    int effect, {
    int pointCount = 256,
  }) async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>(
        'getMasterStereoScope',
        {'effect': effect, 'pointCount': pointCount},
      );
      if (raw == null) return const <double>[];
      return raw.map((e) => (e as num).toDouble()).toList(growable: false);
    } on PlatformException catch (e) {
      _logError('getMasterStereoScope', e);
      return const <double>[];
    }
  }

  static Future<List<double>> getRowShaperPreview(
    int row,
    int effect, {
    int pointCount = 192,
  }) async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>(
        'getRowShaperPreview',
        {'row': row, 'effect': effect, 'pointCount': pointCount},
      );
      if (raw == null) return const <double>[];
      return raw.map((e) => (e as num).toDouble()).toList(growable: false);
    } on PlatformException catch (e) {
      _logError('getRowShaperPreview', e);
      return const <double>[];
    }
  }

  static Future<List<double>> getMasterShaperPreview(
    int effect, {
    int pointCount = 192,
  }) async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>(
        'getMasterShaperPreview',
        {'effect': effect, 'pointCount': pointCount},
      );
      if (raw == null) return const <double>[];
      return raw.map((e) => (e as num).toDouble()).toList(growable: false);
    } on PlatformException catch (e) {
      _logError('getMasterShaperPreview', e);
      return const <double>[];
    }
  }

  static Future<List<double>> getRowDynamicSoftenerFrame(
    int row,
    int effect,
  ) async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>(
        'getRowDynamicSoftenerFrame',
        {'row': row, 'effect': effect},
      );
      if (raw == null) return const <double>[];
      return raw.map((e) => (e as num).toDouble()).toList(growable: false);
    } on PlatformException catch (e) {
      _logError('getRowDynamicSoftenerFrame', e);
      return const <double>[];
    }
  }

  static Future<List<double>> getMasterDynamicSoftenerFrame(
    int effect,
  ) async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>(
        'getMasterDynamicSoftenerFrame',
        {'effect': effect},
      );
      if (raw == null) return const <double>[];
      return raw.map((e) => (e as num).toDouble()).toList(growable: false);
    } on PlatformException catch (e) {
      _logError('getMasterDynamicSoftenerFrame', e);
      return const <double>[];
    }
  }

  static Future<List<double>> getRowTransientShaperVisual(
    int row,
    int effect, {
    int pointCount = 192,
  }) async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>(
        'getRowTransientShaperVisual',
        {'row': row, 'effect': effect, 'pointCount': pointCount},
      );
      if (raw == null) return const <double>[];
      return raw.map((e) => (e as num).toDouble()).toList(growable: false);
    } on PlatformException catch (e) {
      _logError('getRowTransientShaperVisual', e);
      return const <double>[];
    }
  }

  static Future<List<double>> getMasterTransientShaperVisual(
    int effect, {
    int pointCount = 192,
  }) async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>(
        'getMasterTransientShaperVisual',
        {'effect': effect, 'pointCount': pointCount},
      );
      if (raw == null) return const <double>[];
      return raw.map((e) => (e as num).toDouble()).toList(growable: false);
    } on PlatformException catch (e) {
      _logError('getMasterTransientShaperVisual', e);
      return const <double>[];
    }
  }
}
