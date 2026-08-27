import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _between(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'Missing: $start');
  expect(endIndex, greaterThan(startIndex), reason: 'Missing: $end');
  return source.substring(startIndex, endIndex);
}

void main() {
  const editorPath = 'lib/screens/audio_editor.dart';

  test('V2 monitoring UI is truthfully unavailable without native support', () {
    final editor = File(editorPath).readAsStringSync();
    final routingSheet = _between(
      editor,
      'Future<void> _showAudioRoutingSheet() async {',
      'Widget _buildAudioRoutingLauncher()',
    );

    expect(
      routingSheet,
      contains('final monitoringAvailable = !_isBluetoothV2Session;'),
    );
    expect(
      routingSheet,
      contains(
        'final monitoringEnabled =\n'
        '                monitoringAvailable &&',
      ),
    );
    expect(routingSheet, contains('onChanged: monitoringAvailable'));
    expect(
      routingSheet,
      contains('Monitoring is unavailable for the current audio route.'),
    );
  });

  test(
    'legacy monitoring action remains wired to the existing engine path',
    () {
      final editor = File(editorPath).readAsStringSync();
      final routingSheet = _between(
        editor,
        'Future<void> _showAudioRoutingSheet() async {',
        'Widget _buildAudioRoutingLauncher()',
      );
      final monitoringAction = _between(
        editor,
        'Future<void> _setRoutingSheetMonitoring(bool enabled) async {',
        'Future<void> _showAudioRoutingSheet() async {',
      );

      expect(routingSheet, contains('_setRoutingSheetMonitoring('));
      expect(
        monitoringAction,
        contains('JuceAudioEngine.setLiveInputMonitoringEnabled(enabled)'),
      );
      expect(monitoringAction, contains('if (_isBluetoothV2Session)'));
    },
  );
}
