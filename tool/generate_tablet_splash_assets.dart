import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as image;

const int _figmaStatusBarHeightPx = 37;
final image.Color _launchBlack = image.ColorRgba8(2, 4, 2, 255);

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/generate_tablet_splash_assets.dart '
      '<figma-screenshot.png>',
    );
    exitCode = 64;
    return;
  }

  final sourceFile = File(args.single);
  final source = image.decodePng(sourceFile.readAsBytesSync());
  if (source == null) {
    stderr.writeln('Could not decode PNG: ${sourceFile.path}');
    exitCode = 65;
    return;
  }

  image.fillRect(
    source,
    x1: 0,
    y1: 0,
    x2: source.width,
    y2: math.min(_figmaStatusBarHeightPx, source.height),
    color: _launchBlack,
  );

  _writeSplash(
    source: source,
    width: 2732,
    height: 2048,
    outputPath:
        'ios/Runner/Assets.xcassets/LaunchBackground.imageset/background-ipad.png',
  );
  _writeSplash(
    source: source,
    width: 2560,
    height: 1600,
    outputPath: 'android/app/src/main/res/drawable-land/background.png',
  );
}

void _writeSplash({
  required image.Image source,
  required int width,
  required int height,
  required String outputPath,
}) {
  final outputFile = File(outputPath);
  outputFile.parent.createSync(recursive: true);
  final splash = _coverResize(source, width, height);
  outputFile.writeAsBytesSync(image.encodePng(splash, level: 6));
  stdout.writeln('Wrote ${outputFile.path} (${width}x$height)');
}

image.Image _coverResize(image.Image source, int width, int height) {
  final sourceAspect = source.width / source.height;
  final targetAspect = width / height;

  var cropWidth = source.width;
  var cropHeight = source.height;
  if (sourceAspect > targetAspect) {
    cropWidth = (source.height * targetAspect).round();
  } else if (sourceAspect < targetAspect) {
    cropHeight = (source.width / targetAspect).round();
  }

  final cropX = ((source.width - cropWidth) / 2).round();
  final cropY = ((source.height - cropHeight) / 2).round();
  final cropped = image.copyCrop(
    source,
    x: cropX,
    y: cropY,
    width: cropWidth,
    height: cropHeight,
  );

  return image.copyResize(
    cropped,
    width: width,
    height: height,
    interpolation: image.Interpolation.cubic,
  );
}
