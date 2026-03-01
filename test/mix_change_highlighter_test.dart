import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/mix_change_highlighter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MixChangeHighlighter', () {
    test('trigger with empty keys clears active highlights', () {
      final highlighter = MixChangeHighlighter();
      final key = HaloKey('tutorial:timeline');

      highlighter.trigger([key], duration: const Duration(seconds: 5));
      expect(highlighter.active.value, contains(key));

      highlighter.trigger(const []);
      expect(highlighter.active.value, isEmpty);

      highlighter.dispose();
    });

    test('clear removes active highlights directly', () {
      final highlighter = MixChangeHighlighter();
      final keyA = HaloKey('tutorial:timeline');
      final keyB = HaloKey('tutorial:toolbar');

      highlighter.trigger([keyA, keyB], duration: const Duration(seconds: 5));
      expect(highlighter.active.value.length, 2);

      highlighter.clear();
      expect(highlighter.active.value, isEmpty);

      highlighter.dispose();
    });
  });
}
