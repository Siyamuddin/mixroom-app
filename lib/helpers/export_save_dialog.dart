import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';

class ExportSaveDialog {
  const ExportSaveDialog._();

  static String buildSuggestedFileName({
    required String baseName,
    required String extension,
  }) {
    final normalizedBase = baseName
        .trim()
        .replaceAll(RegExp(r'[\u0000-\u001F]'), ' ')
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[. ]+$'), '')
        .trim();
    final safeBase = normalizedBase.isEmpty ? 'Mixroom Export' : normalizedBase;
    final safeExtension = extension.trim().replaceFirst(RegExp(r'^\.+'), '');
    if (safeExtension.isEmpty) {
      return safeBase;
    }
    return '$safeBase.$safeExtension';
  }

  static Future<String?> saveExportedFile({
    required String sourceFilePath,
    required String suggestedFileName,
    String? desktopDialogTitle,
  }) async {
    if (kIsWeb) return null;

    if (Platform.isAndroid || Platform.isIOS) {
      final params = SaveFileDialogParams(
        sourceFilePath: sourceFilePath,
        fileName: suggestedFileName,
      );
      return FlutterFileDialog.saveFile(params: params);
    }

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: desktopDialogTitle ?? 'Save export',
      fileName: suggestedFileName,
      lockParentWindow: true,
    );
    if (savePath == null || savePath.isEmpty) {
      return null;
    }

    final source = File(sourceFilePath);
    if (!await source.exists()) {
      return null;
    }

    final output = File(savePath);
    await output.parent.create(recursive: true);
    await output.writeAsBytes(await source.readAsBytes(), flush: true);
    return output.path;
  }
}
