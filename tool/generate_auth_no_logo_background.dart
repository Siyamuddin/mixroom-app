import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as image;

const String _sourcePath = 'assets/auth/sign_in_background_tile.png';
const String _outputPath = 'assets/auth/launch_background_no_logo_tablet.png';

const int _outputWidth = 2732;
const int _outputHeight = 2048;
const double _figmaWidth = 1024.0;
const double _figmaHeight = 768.0;
const double _stripWidth = 811.513;
const double _stripHeight = 277.4;
const double _imageWidthCrop = 1.3502;
const double _imageHeightCrop = 1.0002;
const double _imageLeftCrop = 0.1751;
const double _statusBarHeight = 37.0;

final image.Color _launchBlack = image.ColorRgba8(2, 4, 2, 255);

void main() {
  final sourceFile = File(_sourcePath);
  final source = image.decodePng(sourceFile.readAsBytesSync());
  if (source == null) {
    stderr.writeln('Could not decode PNG: $_sourcePath');
    exitCode = 65;
    return;
  }

  final output = image.Image(
    width: _outputWidth,
    height: _outputHeight,
    numChannels: 4,
  );
  image.fill(output, color: _launchBlack);

  final scaleX = _outputWidth / _figmaWidth;
  final scaleY = _outputHeight / _figmaHeight;
  final stripTargetWidth = (_stripWidth * scaleX).round();
  final stripTargetHeight = (_stripHeight * scaleY).round();
  final childWidth = stripTargetHeight;
  final childHeight = stripTargetWidth;

  final paintedSource = image.copyResize(
    source,
    width: (childWidth * _imageWidthCrop).round(),
    height: (childHeight * _imageHeightCrop).round(),
    interpolation: image.Interpolation.cubic,
  );
  final child = image.copyCrop(
    paintedSource,
    x: math.max(0, (childWidth * _imageLeftCrop).round()),
    y: 0,
    width: childWidth,
    height: childHeight,
  );
  final strip = image.copyRotate(
    child,
    angle: 90,
    interpolation: image.Interpolation.cubic,
  );

  for (final centerOffset in const <double>[
    -554.8,
    -277.4,
    0.0,
    277.4,
    554.8
  ]) {
    final centerX = (_figmaWidth / 2.0) * scaleX;
    final centerY = ((_figmaHeight / 2.0) + centerOffset) * scaleY;
    image.compositeImage(
      output,
      strip,
      dstX: (centerX - (strip.width / 2.0)).round(),
      dstY: (centerY - (strip.height / 2.0)).round(),
    );
  }

  image.fillRect(
    output,
    x1: 0,
    y1: 0,
    x2: output.width,
    y2: math.min((_statusBarHeight * scaleY).round(), output.height),
    color: _launchBlack,
  );

  final landscapeOutput = _coverResize(
    image.copyRotate(
      output,
      angle: 90,
      interpolation: image.Interpolation.cubic,
    ),
    _outputWidth,
    _outputHeight,
  );

  final outputFile = File(_outputPath);
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsBytesSync(image.encodePng(landscapeOutput, level: 6));
  stdout.writeln(
    'Wrote $_outputPath (${landscapeOutput.width}x${landscapeOutput.height})',
  );
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
