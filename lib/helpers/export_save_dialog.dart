import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class ExportSaveDialog {
  const ExportSaveDialog._();
  static const MethodChannel _savedExportsChannel =
      MethodChannel('mixroom/saved_exports');

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

    if (Platform.isAndroid) {
      final expectedExtension = _resolveExpectedExtension(
        suggestedFileName: suggestedFileName,
        sourceFilePath: sourceFilePath,
      );
      final mimeType = _resolveMimeType(expectedExtension);
      try {
        final savedPath = await _savedExportsChannel.invokeMethod<String>(
          'saveExportedFile',
          <String, dynamic>{
            'sourceFilePath': sourceFilePath,
            'suggestedFileName': suggestedFileName,
            'mimeType': mimeType,
          },
        );
        final trimmed = savedPath?.trim();
        if (trimmed != null && trimmed.isNotEmpty) {
          return trimmed;
        }
      } catch (_) {
        return null;
      }
      return null;
    }

    if (Platform.isIOS) {
      final params = SaveFileDialogParams(
        sourceFilePath: sourceFilePath,
        fileName: suggestedFileName,
      );
      final savedPath = await FlutterFileDialog.saveFile(params: params);
      if (savedPath == null || savedPath.isEmpty) {
        return savedPath;
      }
      return savedPath;
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

  static String _resolveExpectedExtension({
    required String suggestedFileName,
    required String sourceFilePath,
  }) {
    String extensionFrom(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return '';
      final slash = trimmed.lastIndexOf(RegExp(r'[\\/]'));
      final fileName = slash >= 0 ? trimmed.substring(slash + 1) : trimmed;
      final dot = fileName.lastIndexOf('.');
      if (dot <= 0 || dot == fileName.length - 1) return '';
      return fileName.substring(dot + 1).trim().toLowerCase();
    }

    final fromSuggested = extensionFrom(suggestedFileName);
    if (fromSuggested.isNotEmpty) {
      return fromSuggested;
    }
    return extensionFrom(sourceFilePath);
  }

  static String _resolveMimeType(String extension) {
    switch (extension.trim().toLowerCase()) {
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/x-wav';
      case 'm4a':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'flac':
        return 'audio/flac';
      case 'ogg':
        return 'audio/ogg';
      default:
        return '*/*';
    }
  }

  static String? resolveSavedDisplayName(String? rawPath) {
    final input = rawPath?.trim();
    if (input == null || input.isEmpty) return null;

    String decoded = input;
    try {
      decoded = Uri.decodeFull(input);
    } catch (_) {}

    String? fromDocumentId(String value) {
      final marker = value.indexOf('/document/');
      if (marker >= 0) {
        final id = value.substring(marker + '/document/'.length);
        if (id.contains('/')) return id.split('/').last.trim();
        return id.trim();
      }
      if (value.startsWith('document/')) {
        final id = value.substring('document/'.length);
        if (id.contains('/')) return id.split('/').last.trim();
        return id.trim();
      }
      return null;
    }

    final documentName = fromDocumentId(decoded);
    if (documentName != null && documentName.isNotEmpty) {
      return documentName;
    }

    final uri = Uri.tryParse(decoded);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final last = uri.pathSegments.last.trim();
      if (last.isNotEmpty) return last;
    }

    final base = p.basename(decoded).trim();
    if (base.isNotEmpty && base != '.') {
      return base;
    }
    return null;
  }

  static Future<String?> resolveSavedDisplayNameFromPlatform(
    String? rawPath,
  ) async {
    final fallback = resolveSavedDisplayName(rawPath);
    if (kIsWeb || !Platform.isAndroid) {
      return fallback;
    }
    final input = rawPath?.trim();
    if (input == null || input.isEmpty) {
      return fallback;
    }
    try {
      final resolved = await _savedExportsChannel.invokeMethod<String>(
        'resolveSavedExportDisplayName',
        <String, dynamic>{'path': input},
      );
      final normalized = resolved?.trim();
      if (normalized != null && normalized.isNotEmpty) {
        return normalized;
      }
    } catch (_) {
      // Fall back to parsing if native lookup is unavailable.
    }
    return fallback;
  }

  static Future<String?> materializeSavedPreviewPathFromPlatform(
    String? rawPath,
  ) async {
    final input = rawPath?.trim();
    if (input == null || input.isEmpty) {
      return null;
    }
    if (kIsWeb || !Platform.isAndroid) {
      return input;
    }
    try {
      final resolved = await _savedExportsChannel.invokeMethod<String>(
        'materializeSavedExportForPreview',
        <String, dynamic>{'path': input},
      );
      final normalized = resolved?.trim();
      if (normalized != null && normalized.isNotEmpty) {
        return normalized;
      }
    } catch (_) {
      // Fall back to the raw path if native preview materialization is unavailable.
    }
    return null;
  }

  static Future<bool> shareSavedExportFromPlatform(String? rawPath) async {
    final input = rawPath?.trim();
    if (input == null ||
        input.isEmpty ||
        kIsWeb ||
        (!Platform.isAndroid && !Platform.isIOS)) {
      return false;
    }
    try {
      final shared = await _savedExportsChannel.invokeMethod<bool>(
        'shareSavedExport',
        <String, dynamic>{'path': input},
      );
      return shared == true;
    } catch (_) {
      return false;
    }
  }
}
