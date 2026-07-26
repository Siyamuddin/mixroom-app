import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/ai_gain_units.dart';

void main() {
  test('row gain conversion preserves the fader dB scale', () {
    expect(rowGainUiToDb(0.0), -60.0);
    expect(rowGainUiToDb(2.0), 0.0);
    expect(rowGainUiToDb(3.0), 6.0);
    expect(rowGainDbToUi(-2.0), closeTo(1.9333333333, 1e-9));
  });

  test('relative dB adjustment operates in the fader domain', () {
    final adjusted = adjustRowGainUiByDb(2.0, -2.0);
    expect(adjusted, closeTo(1.9333333333, 1e-9));
    expect(rowGainUiToDb(adjusted), closeTo(-2.0, 1e-9));
  });

  test('relative adjustment clamps to the supported dB range', () {
    expect(adjustRowGainUiByDb(0.0, -3.0), 0.0);
    expect(adjustRowGainUiByDb(3.0, 3.0), 3.0);
  });
}
