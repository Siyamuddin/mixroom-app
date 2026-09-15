import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/v3/ai_v3_midi_boundary.dart';

void main() {
  test('shared boundary vectors match backend microsecond decisions', () {
    final vectors = jsonDecode(File('backend/llm_proxy/tests/fixtures/midi_boundary_v1.json').readAsStringSync()) as List;
    for (final v in vectors) {
      double n(String key) => (v[key] as num).toDouble();
      final result = aiV3ExtendedMidiLength(original: n('original'),
          current: n('current'), end: n('end'), bpm: n('bpm'));
      expect(result > n('current'), v['extended']);
      expect((result * (60000000.0 / n('bpm'))).round(), v['expected_us']);
    }
  });
  test('execution requires unchanged bounds, tempo, and computed final length', () {
    final length = aiV3ExtendedMidiLength(original: 31.9986,
        current: 31.9986, end: 32, bpm: 108);
    bool matches(double current, double tempo, double finalLength) =>
        aiV3MidiBoundaryExecutionMatches(original: 31.9986, expected: 31.9986,
            current: current, end: 32, finalLength: finalLength, bpm: 108,
            currentBpm: tempo);
    expect(matches(31.9986, 108, length), isTrue);
    expect(matches(31.99, 108, length), isFalse);
    expect(matches(31.9986, 120, length), isFalse);
    expect(matches(31.9986, 108, 33), isFalse);
  });
}
