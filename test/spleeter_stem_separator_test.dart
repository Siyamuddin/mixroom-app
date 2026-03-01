import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/spleeter_stem_separator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SpleeterStemSeparator framing', () {
    test('frameCountForSamples handles short and long clips', () {
      expect(SpleeterStemSeparator.frameCountForSamples(0), 1);
      expect(SpleeterStemSeparator.frameCountForSamples(3000), 1);
      expect(SpleeterStemSeparator.frameCountForSamples(4096), 1);
      expect(SpleeterStemSeparator.frameCountForSamples(4096 + 1024), 2);
    });

    test('paddedFrameCountForModel pads to 512-frame blocks', () {
      expect(SpleeterStemSeparator.paddedFrameCountForModel(1), 512);
      expect(SpleeterStemSeparator.paddedFrameCountForModel(512), 512);
      expect(SpleeterStemSeparator.paddedFrameCountForModel(513), 1024);
    });
  });

  group('SpleeterStemSeparator window', () {
    test('periodic hann window shape is valid', () {
      final window = SpleeterStemSeparator.periodicHannWindow(size: 4096);
      expect(window.length, 4096);
      expect(window.first, closeTo(0.0, 1e-8));
      expect(window[1024], closeTo(0.5, 1e-3));
      expect(window[2048], closeTo(1.0, 1e-3));
      expect(window.last, lessThan(0.01));
    });
  });
}
