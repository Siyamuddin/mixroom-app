import 'dart:io';

import 'package:accessing_security_scoped_resource/accessing_security_scoped_resource.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mixroom/helpers/platform_capabilities.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/widgets/profile_avatar_crop_screen.dart';

class ProfileAvatarPicker {
  static Future<Uint8List?> pickAndCrop(BuildContext context) async {
    final sourceBytes = PlatformCapabilities.current.isDesktop
        ? await pickFromFiles()
        : await _pickFromMobile(context);
    if (sourceBytes == null || sourceBytes.isEmpty || !context.mounted) {
      return null;
    }

    return Navigator.of(context, rootNavigator: true).push<Uint8List>(
      MaterialPageRoute<Uint8List>(
        fullscreenDialog: true,
        builder: (_) => ProfileAvatarCropScreen(imageBytes: sourceBytes),
      ),
    );
  }

  static Future<Uint8List?> pickFromFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null) return null;
    if (file.bytes != null && file.bytes!.isNotEmpty) {
      return file.bytes;
    }
    final path = file.path;
    if (path == null || path.isEmpty) return null;
    return _readPathBytes(path);
  }

  static Future<Uint8List?> _readPathBytes(String path) async {
    final useScoped = !kIsWeb && (Platform.isMacOS || Platform.isIOS);
    if (!useScoped) {
      final bytes = await File(path).readAsBytes();
      return bytes.isEmpty ? null : bytes;
    }

    final scoped = AccessingSecurityScopedResource();
    var started = false;
    try {
      started = await scoped.startAccessingSecurityScopedResourceWithFilePath(
        path,
      );
      final bytes = await File(path).readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } finally {
      if (started) {
        await scoped.stopAccessingSecurityScopedResourceWithFilePath(path);
      }
    }
  }

  static Future<Uint8List?> _pickFromMobile(BuildContext context) async {
    final choice = await showCupertinoModalPopup<ImageSource>(
      context: context,
      builder: (sheetContext) {
        return CupertinoActionSheet(
          actions: [
            CupertinoActionSheetAction(
              onPressed: () =>
                  Navigator.of(sheetContext).pop(ImageSource.camera),
              child: Text(L10n.translate(context, 'Camera')),
            ),
            CupertinoActionSheetAction(
              onPressed: () =>
                  Navigator.of(sheetContext).pop(ImageSource.gallery),
              child: Text(L10n.translate(context, 'Photo Library')),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: Text(L10n.translate(context, 'Cancel')),
          ),
        );
      },
    );
    if (choice == null) return null;
    return pickFromImageSource(choice);
  }

  static Future<Uint8List?> pickFromImageSource(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source,
      imageQuality: 90,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (file == null) return null;
    return file.readAsBytes();
  }

  static String? messageForPickerError(Object error, ImageSource? source) {
    if (error is! PlatformException) return null;
    final code = error.code.toLowerCase();
    if (code.contains('camera')) {
      return 'Camera access is needed to take a profile picture.';
    }
    if (code.contains('photo') ||
        code.contains('gallery') ||
        code.contains('permission')) {
      return 'Photo access is needed to set a profile picture.';
    }
    return null;
  }
}
