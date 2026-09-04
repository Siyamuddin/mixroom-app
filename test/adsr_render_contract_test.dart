import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String editor;

  setUpAll(() {
    editor = File('lib/screens/audio_editor.dart').readAsStringSync();
  });

  String methodBody(String signature, String nextSignature) {
    final start = editor.indexOf(signature);
    final end = editor.indexOf(nextSignature, start + signature.length);
    expect(start, greaterThanOrEqualTo(0), reason: 'Missing $signature');
    expect(end, greaterThan(start), reason: 'Missing boundary $nextSignature');
    return editor.substring(start, end);
  }

  test('Granularizer offline envelope uses stored decay and sustain', () {
    final body = methodBody(
      'Future<bool> _renderInstrumentClipWithGranularizer({',
      'Future<bool> _renderInstrumentClipWithSfz({',
    );

    expect(body, contains("params['decayMs'] ?? 80.0"));
    expect(body, contains("params['sustainLevel'] ?? 0.92"));
    expect(body, contains('decaySec: decaySec'));
    expect(body, contains('sustainLevel: sustainLevel'));
    expect(body, isNot(contains('decaySec: 0.08')));
    expect(body, isNot(contains('sustainLevel: 0.92')));
  });

  test('SFZ offline envelope preserves an explicit zero attack', () {
    final body = methodBody(
      'Future<bool> _renderInstrumentClipWithSfz({',
      'Future<void> _renderInstrumentClipWithDartSynth({',
    );

    expect(body, contains("final attackOverrideMs = params['attackMs'];"));
    expect(
      body,
      contains('attackOverrideMs != null && attackOverrideMs.isFinite'),
    );
    expect(body, contains('attackOverrideSec ??'));
    expect(body, isNot(contains('attackOverrideSec > 0')));
  });
}
