import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const ffmpegMethodChannel = MethodChannel('flutter.arthenica.com/ffmpeg_kit');
const ffmpegEventMethodChannel = MethodChannel(
  'flutter.arthenica.com/ffmpeg_kit_event',
);

class FakeFfmpegKit {
  FakeFfmpegKit(this._binaryMessenger);

  final TestDefaultBinaryMessenger _binaryMessenger;
  final Map<int, List<String>> _sessionArgs = <int, List<String>>{};
  final Map<int, int> _sessionReturnCodes = <int, int>{};
  final List<List<String>> executedCommands = <List<String>>[];
  int _nextSessionId = 1;
  int failRemaining = 0;

  void failNext([int count = 1]) {
    failRemaining += count;
  }

  void install() {
    _binaryMessenger.setMockMethodCallHandler(
      ffmpegMethodChannel,
      _handleMethodCall,
    );
    _binaryMessenger.setMockMethodCallHandler(
      ffmpegEventMethodChannel,
      _handleEventCall,
    );
  }

  void uninstall() {
    _binaryMessenger.setMockMethodCallHandler(ffmpegMethodChannel, null);
    _binaryMessenger.setMockMethodCallHandler(ffmpegEventMethodChannel, null);
  }

  Future<Object?> _handleEventCall(MethodCall call) async {
    if (call.method == 'listen' || call.method == 'cancel') {
      return null;
    }
    throw MissingPluginException(
      'Unhandled ffmpeg event method ${call.method}',
    );
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'getLogLevel':
        return 0;
      case 'getPlatform':
        return 'test';
      case 'getArch':
        return 'x86_64';
      case 'getPackageName':
        return 'mock-package';
      case 'enableRedirection':
        return null;
      case 'isLTSBuild':
        return false;
      case 'setLogLevel':
        return null;
      case 'ffmpegSession':
        final args = ((call.arguments as Map)['arguments'] as List)
            .cast<String>();
        final sessionId = _nextSessionId++;
        _sessionArgs[sessionId] = List<String>.from(args);
        return <String, Object>{
          'sessionId': sessionId,
          'createTime': DateTime.now().millisecondsSinceEpoch,
          'startTime': DateTime.now().millisecondsSinceEpoch,
          'command': args.join(' '),
        };
      case 'ffmpegSessionExecute':
        final sessionId = (call.arguments as Map)['sessionId'] as int;
        final args = _sessionArgs[sessionId];
        if (args == null) {
          throw StateError('Missing mock ffmpeg session $sessionId');
        }
        executedCommands.add(List<String>.from(args));
        if (failRemaining > 0) {
          failRemaining--;
          _sessionReturnCodes[sessionId] = 1;
          return null;
        }
        await _executeFfmpegCommand(args);
        _sessionReturnCodes[sessionId] = 0;
        return null;
      case 'abstractSessionGetReturnCode':
        final sessionId = (call.arguments as Map)['sessionId'] as int;
        return _sessionReturnCodes[sessionId] ?? 0;
    }

    throw MissingPluginException('Unhandled ffmpeg method ${call.method}');
  }

  Future<void> _executeFfmpegCommand(List<String> args) async {
    final inputFlagIndex = args.indexOf('-i');
    if (inputFlagIndex < 0 || inputFlagIndex + 1 >= args.length) {
      throw StateError('Mock ffmpeg command missing input: $args');
    }
    final inputPath = args[inputFlagIndex + 1];
    final outputPath = args.last;
    await File(outputPath).parent.create(recursive: true);
    await File(inputPath).copy(outputPath);
  }
}
