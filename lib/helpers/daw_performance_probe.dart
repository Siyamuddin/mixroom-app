import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/scheduler.dart';

typedef DawPerformanceLogger = void Function(String message);

/// Compile-time gate so the probe is absent from normal builds. Enable it with
/// `--dart-define=PRO17_PERF=true` in profile mode.
const bool kDawPerformanceMetricsEnabled = bool.fromEnvironment('PRO17_PERF');

class DawPerformanceContext {
  const DawPerformanceContext({
    required this.projectId,
    required this.projectName,
    required this.rowCount,
    required this.clipCount,
  });

  final String projectId;
  final String projectName;
  final int rowCount;
  final int clipCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'project_id': projectId,
    'project_name': projectName,
    'rows': rowCount,
    'clips': clipCount,
  };
}

/// Temporary PRO-17 instrumentation for detecting DAW mutation latency and
/// UI-thread stalls in profile builds. All output is single-line JSON prefixed
/// with [PRO17_PERF] so a run can be captured with a simple log filter.
class DawPerformanceProbe {
  DawPerformanceProbe({
    required bool Function() isEnabled,
    required DawPerformanceContext Function() context,
    DawPerformanceLogger? logger,
    File? logFile,
    this.instrumentationBuildEnabled = kDawPerformanceMetricsEnabled,
    this.slowFrameThreshold = const Duration(milliseconds: 32),
    this.stallThreshold = const Duration(milliseconds: 150),
    this.stallPollInterval = const Duration(milliseconds: 50),
  }) : _isEnabled = isEnabled,
       _context = context,
       _logger = logger ?? _developerLog,
       _logFile = logFile;

  final bool Function() _isEnabled;
  final DawPerformanceContext Function() _context;
  final DawPerformanceLogger _logger;
  final File? _logFile;
  final bool instrumentationBuildEnabled;
  final Duration slowFrameThreshold;
  final Duration stallThreshold;
  final Duration stallPollInterval;

  final Stopwatch _clock = Stopwatch()..start();
  final String sessionId =
      'pro17-${DateTime.now().toUtc().microsecondsSinceEpoch}';
  Future<void> _logWriteQueue = Future<void>.value();
  Timer? _stallTimer;
  Duration _lastStallTick = Duration.zero;
  int _operationSerial = 0;
  bool _frameCallbackRegistered = false;

  bool get enabled => instrumentationBuildEnabled && _isEnabled();

  void startMonitoring() {
    if (!enabled || _stallTimer != null) return;
    _lastStallTick = _clock.elapsed;
    _stallTimer = Timer.periodic(stallPollInterval, (_) {
      final now = _clock.elapsed;
      final interval = now - _lastStallTick;
      _lastStallTick = now;
      if (!enabled || interval < stallThreshold) return;
      emit('event_loop_stall', <String, Object?>{
        'interval_ms': _milliseconds(interval),
        'expected_ms': _milliseconds(stallPollInterval),
        'stall_ms': _milliseconds(interval - stallPollInterval),
      });
    });
    if (!_frameCallbackRegistered) {
      SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
      _frameCallbackRegistered = true;
    }
    emit('monitoring_started', <String, Object?>{
      'slow_frame_threshold_ms': _milliseconds(slowFrameThreshold),
      'stall_threshold_ms': _milliseconds(stallThreshold),
      if (_logFile != null) 'log_path': _logFile.path,
    });
  }

  void stopMonitoring() {
    _stallTimer?.cancel();
    _stallTimer = null;
    if (_frameCallbackRegistered) {
      SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
      _frameCallbackRegistered = false;
    }
  }

  Future<void> flushLogs() => _logWriteQueue;

  DawPerformanceSpan beginOperation(
    String operation, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    if (!enabled) return DawPerformanceSpan.disabled();
    _operationSerial += 1;
    return DawPerformanceSpan._(
      probe: this,
      operation: operation,
      operationId: _operationSerial,
      contextAtStart: _context(),
      metadata: metadata,
    );
  }

  void emit(String event, [Map<String, Object?> fields = const {}]) {
    if (!enabled) return;
    _write(<String, Object?>{
      'event': event,
      ..._context().toJson(),
      ...fields,
    });
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (!enabled) return;
    for (final timing in timings) {
      if (timing.totalSpan < slowFrameThreshold) continue;
      emit('slow_frame', <String, Object?>{
        'total_ms': _milliseconds(timing.totalSpan),
        'build_ms': _milliseconds(timing.buildDuration),
        'raster_ms': _milliseconds(timing.rasterDuration),
        'vsync_overhead_ms': _milliseconds(timing.vsyncOverhead),
      });
    }
  }

  void _write(Map<String, Object?> payload) {
    final message =
        '[PRO17_PERF] ${jsonEncode(<String, Object?>{'session_id': sessionId, 'timestamp_utc': DateTime.now().toUtc().toIso8601String(), 'monotonic_ms': _milliseconds(_clock.elapsed), ...payload})}';
    _logger(message);
    final logFile = _logFile;
    if (logFile == null) return;
    _logWriteQueue = _logWriteQueue
        .then((_) async {
          await logFile.parent.create(recursive: true);
          await logFile.writeAsString(
            '$message\n',
            mode: FileMode.append,
            flush: true,
          );
        })
        .catchError((Object error, StackTrace stackTrace) {
          developer.log(
            'Failed to append PRO-17 metrics: $error',
            name: 'PRO17_PERF',
            error: error,
            stackTrace: stackTrace,
          );
        });
  }

  static double _milliseconds(Duration duration) =>
      duration.inMicroseconds / 1000.0;

  static void _developerLog(String message) {
    developer.log(message, name: 'PRO17_PERF');
  }
}

class DawPerformanceSpan {
  DawPerformanceSpan._({
    required DawPerformanceProbe probe,
    required this.operation,
    required this.operationId,
    required this.contextAtStart,
    required Map<String, Object?> metadata,
  }) : _probe = probe,
       _metadata = Map<String, Object?>.from(metadata),
       _stopwatch = Stopwatch()..start(),
       _phaseStart = Duration.zero,
       _timelineTask = developer.TimelineTask() {
    _timelineTask!.start(
      'PRO17 $operation',
      arguments: <String, Object?>{
        'operation_id': operationId,
        ...contextAtStart.toJson(),
        ...metadata,
      },
    );
    _write('operation_start', metadata);
  }

  DawPerformanceSpan.disabled()
    : _probe = null,
      operation = '',
      operationId = -1,
      contextAtStart = const DawPerformanceContext(
        projectId: '',
        projectName: '',
        rowCount: 0,
        clipCount: 0,
      ),
      _metadata = const <String, Object?>{},
      _stopwatch = null,
      _phaseStart = Duration.zero,
      _timelineTask = null;

  final DawPerformanceProbe? _probe;
  final String operation;
  final int operationId;
  final DawPerformanceContext contextAtStart;
  final Map<String, Object?> _metadata;
  final Stopwatch? _stopwatch;
  Duration _phaseStart;
  final developer.TimelineTask? _timelineTask;
  bool _finished = false;

  bool get enabled => _probe != null;

  void checkpoint(
    String phase, {
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    final stopwatch = _stopwatch;
    if (stopwatch == null || _finished) return;
    final elapsed = stopwatch.elapsed;
    final phaseElapsed = elapsed - _phaseStart;
    _phaseStart = elapsed;
    _timelineTask?.instant(
      phase,
      arguments: <String, Object?>{
        'elapsed_ms': DawPerformanceProbe._milliseconds(elapsed),
        'phase_ms': DawPerformanceProbe._milliseconds(phaseElapsed),
        ...fields,
      },
    );
    _write('operation_phase', <String, Object?>{
      'phase': phase,
      'elapsed_ms': DawPerformanceProbe._milliseconds(elapsed),
      'phase_ms': DawPerformanceProbe._milliseconds(phaseElapsed),
      ...fields,
    });
  }

  void finish({
    String result = 'success',
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    final stopwatch = _stopwatch;
    if (stopwatch == null || _finished) return;
    _finished = true;
    final elapsed = stopwatch.elapsed;
    _timelineTask?.finish(arguments: <String, Object?>{'result': result});
    _write('operation_end', <String, Object?>{
      'result': result,
      'elapsed_ms': DawPerformanceProbe._milliseconds(elapsed),
      'start_rows': contextAtStart.rowCount,
      'start_clips': contextAtStart.clipCount,
      ...fields,
    });

    SchedulerBinding.instance.addPostFrameCallback((_) {
      stopwatch.stop();
      _write('operation_visible_frame', <String, Object?>{
        'elapsed_ms': DawPerformanceProbe._milliseconds(stopwatch.elapsed),
        'result': result,
      });
    });
  }

  void fail(Object error) {
    finish(result: 'error', fields: <String, Object?>{'error': '$error'});
  }

  void _write(String event, Map<String, Object?> fields) {
    final probe = _probe;
    if (probe == null) return;
    probe._write(<String, Object?>{
      'event': event,
      'operation': operation,
      'operation_id': operationId,
      ...contextAtStart.toJson(),
      ..._metadata,
      ...fields,
    });
  }
}
