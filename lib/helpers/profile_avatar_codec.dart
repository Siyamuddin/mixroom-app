import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class ProfileAvatarCodecException implements Exception {
  const ProfileAvatarCodecException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Compresses a picked photo into a square JPEG the avatar API will accept.
class ProfileAvatarCodec {
  static const int maxBytes = 512 * 1024;
  static const int outputSide = 512;
  static const int fallbackSide = 384;
  static const int minSourceSide = 128;
  static const List<int> qualities = <int>[85, 70, 55];

  static Uint8List encodeJpeg(List<int> sourceBytes) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(Uint8List.fromList(sourceBytes));
    } catch (_) {
      decoded = null;
    }
    if (decoded == null) {
      throw const ProfileAvatarCodecException("Couldn't read that image.");
    }

    decoded = img.bakeOrientation(decoded);
    final square = _centerSquare(decoded);
    if (square.width < minSourceSide || square.height < minSourceSide) {
      throw const ProfileAvatarCodecException("Couldn't read that image.");
    }

    var jpeg = _encodeAtSide(square, outputSide);
    if (jpeg.length > maxBytes) {
      jpeg = _encodeAtSide(square, fallbackSide);
    }
    if (jpeg.length > maxBytes) {
      throw const ProfileAvatarCodecException(
        'This photo is too large. Try another one.',
      );
    }

    if (kDebugMode) {
      debugPrint('[profile_avatar] jpeg bytes=${jpeg.length}');
    }
    return jpeg;
  }

  /// Isolate-safe wrapper so UI does not freeze on a large photo.
  static Map<String, Object?> encodeJpegIsolate(List<int> sourceBytes) {
    try {
      return <String, Object?>{'bytes': encodeJpeg(sourceBytes)};
    } on ProfileAvatarCodecException catch (error) {
      return <String, Object?>{'error': error.message};
    } catch (_) {
      return const <String, Object?>{'error': "Couldn't read that image."};
    }
  }

  static img.Image _centerSquare(img.Image source) {
    if (source.width == source.height) return source;
    final side = source.width < source.height ? source.width : source.height;
    final x = (source.width - side) ~/ 2;
    final y = (source.height - side) ~/ 2;
    return img.copyCrop(source, x: x, y: y, width: side, height: side);
  }

  static Uint8List _encodeAtSide(img.Image square, int side) {
    final resized = (square.width == side && square.height == side)
        ? square
        : img.copyResize(
            square,
            width: side,
            height: side,
            interpolation: img.Interpolation.cubic,
          );
    for (final quality in qualities) {
      final bytes = Uint8List.fromList(
        img.encodeJpg(resized, quality: quality),
      );
      if (bytes.length <= maxBytes) return bytes;
    }
    return Uint8List.fromList(img.encodeJpg(resized, quality: qualities.last));
  }
}
