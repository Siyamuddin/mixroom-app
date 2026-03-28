import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ai_debug.dart';

Future<String> materializeOnnxAsset({
  required String assetKey,
  required String scope,
}) async {
  final byteData = await rootBundle.load(assetKey);
  final bytes = byteData.buffer.asUint8List(
    byteData.offsetInBytes,
    byteData.lengthInBytes,
  );

  final supportDir = await getApplicationSupportDirectory();
  final onnxDir = Directory(p.join(supportDir.path, 'onnx_models'));
  await onnxDir.create(recursive: true);

  final fileName = assetKey.split('/').last;
  final targetFile = File(p.join(onnxDir.path, fileName));
  final tempFile = File('${targetFile.path}.part');

  aiDebugLog(
    scope,
    'materializing asset="$assetKey" bytes=${bytes.length} target="${targetFile.path}"',
  );

  if (await tempFile.exists()) {
    await tempFile.delete();
  }
  await tempFile.writeAsBytes(bytes, flush: true);
  if (await targetFile.exists()) {
    await targetFile.delete();
  }
  await tempFile.rename(targetFile.path);
  return targetFile.path;
}

Future<OrtSession> createCpuSessionFromAsset({
  required OnnxRuntime runtime,
  required String assetKey,
  required String scope,
  int intraOpNumThreads = 1,
  int interOpNumThreads = 1,
  bool useArena = true,
}) async {
  final modelPath = await materializeOnnxAsset(
    assetKey: assetKey,
    scope: scope,
  );

  final options = OrtSessionOptions(
    intraOpNumThreads: intraOpNumThreads,
    interOpNumThreads: interOpNumThreads,
    providers: <OrtProvider>[OrtProvider.CPU],
    useArena: useArena,
  );

  aiDebugLog(
    scope,
    'creating cpu session asset="$assetKey" path="$modelPath" intra=$intraOpNumThreads inter=$interOpNumThreads arena=$useArena',
  );

  final session = await runtime.createSession(modelPath, options: options);
  if (session.inputNames.isEmpty || session.outputNames.isEmpty) {
    await session.close();
    throw StateError(
      'Invalid ONNX model I/O for $assetKey: inputs=${session.inputNames.length} outputs=${session.outputNames.length}',
    );
  }

  aiDebugLog(
    scope,
    'session ready asset="$assetKey" inputs=${session.inputNames} outputs=${session.outputNames}',
  );

  return session;
}
