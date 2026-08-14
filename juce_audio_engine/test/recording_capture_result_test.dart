import 'package:flutter_test/flutter_test.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';

void main() {
  test('recording stop result remains forward compatible', () {
    final result = RecordingCaptureResult.fromMap(<String, dynamic>{
      'success': true,
      'diagnosticCode': 'ok',
      'attemptedSamples': 48000,
      'acceptedSamples': 48000,
      'droppedSamples': 0,
      'actualSampleRate': 48000,
      'channelCount': 1,
      'futureField': 'ignored',
    });

    expect(result.success, isTrue);
    expect(result.diagnosticCode, 'ok');
    expect(result.attemptedSamples, 48000);
    expect(result.acceptedSamples, 48000);
    expect(result.droppedSamples, 0);
    expect(result.actualSampleRate, 48000.0);
    expect(result.channelCount, 1);
  });

  test('missing recording stop facts fail closed', () {
    final result = RecordingCaptureResult.fromMap(<String, dynamic>{});
    expect(result.success, isFalse);
    expect(result.diagnosticCode, 'writer_finalize_failed');
  });
}
