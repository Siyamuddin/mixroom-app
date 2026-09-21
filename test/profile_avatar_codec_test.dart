import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mixroom/helpers/profile_avatar_codec.dart';

void main() {
  group('ProfileAvatarCodec', () {
    test('rejects bytes that are not an image', () {
      expect(
        () => ProfileAvatarCodec.encodeJpeg(<int>[1, 2, 3, 4, 5]),
        throwsA(
          isA<ProfileAvatarCodecException>().having(
            (error) => error.message,
            'message',
            "Couldn't read that image.",
          ),
        ),
      );
    });

    test('rejects images smaller than 128px', () {
      final tiny = img.Image(width: 32, height: 32);
      img.fill(tiny, color: img.ColorRgb8(40, 80, 200));
      final bytes = Uint8List.fromList(img.encodePng(tiny));

      expect(
        () => ProfileAvatarCodec.encodeJpeg(bytes),
        throwsA(isA<ProfileAvatarCodecException>()),
      );
    });

    test('encodes a square JPEG under 512 KB at 512px', () {
      final source = img.Image(width: 900, height: 700);
      img.fill(source, color: img.ColorRgb8(210, 90, 40));
      for (var y = 0; y < source.height; y += 12) {
        img.drawLine(
          source,
          x1: 0,
          y1: y,
          x2: source.width - 1,
          y2: y,
          color: img.ColorRgb8(20, 20, 20),
        );
      }
      final bytes = Uint8List.fromList(img.encodePng(source));

      final jpeg = ProfileAvatarCodec.encodeJpeg(bytes);
      expect(jpeg.length, lessThanOrEqualTo(ProfileAvatarCodec.maxBytes));

      final decoded = img.decodeJpg(jpeg);
      expect(decoded, isNotNull);
      expect(decoded!.width, ProfileAvatarCodec.outputSide);
      expect(decoded.height, ProfileAvatarCodec.outputSide);
    });

    test('bakes EXIF orientation 6 into a square JPEG', () {
      final source = img.Image(width: 400, height: 200);
      img.fill(source, color: img.ColorRgb8(10, 200, 40));
      source.exif.imageIfd.orientation = 6;
      final bytes = Uint8List.fromList(img.encodeJpg(source, quality: 90));

      final jpeg = ProfileAvatarCodec.encodeJpeg(bytes);
      final decoded = img.decodeJpg(jpeg);
      expect(decoded, isNotNull);
      expect(decoded!.width, ProfileAvatarCodec.outputSide);
      expect(decoded.height, ProfileAvatarCodec.outputSide);
    });

    test('encodeJpegIsolate returns an error map for garbage bytes', () {
      final result = ProfileAvatarCodec.encodeJpegIsolate(<int>[1, 2, 3, 4, 5]);
      expect(result['bytes'], isNull);
      expect(result['error'], "Couldn't read that image.");
    });
  });
}
