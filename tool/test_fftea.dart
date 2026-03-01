import 'dart:math';
import 'package:fftea/fftea.dart';

void main() {
  const n = 4096;
  final fft = FFT(n);
  final x = List<double>.generate(
    n,
    (i) => sin(2 * pi * i / 64) + 0.25 * sin(2 * pi * i / 13),
  );
  final spec = fft.realFft(x);
  final y = fft.realInverseFft(spec);
  double maxErr = 0;
  for (int i = 0; i < n; i++) {
    final e = (x[i] - y[i]).abs();
    if (e > maxErr) maxErr = e;
  }
  print('maxErr=$maxErr');
}
