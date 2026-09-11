import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _between(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start);
  expect(start, greaterThanOrEqualTo(0));
  expect(end, greaterThan(start));
  return source.substring(start, end);
}

void main() {
  const roots = <String>[
    'juce_audio_engine/ios/Classes',
    'juce_audio_engine/android/src/main/cpp',
  ];

  for (final root in roots) {
    test('row post processor preserves the established DSP order: $root', () {
      final header = File('$root/JuceEngine.h').readAsStringSync();
      final rowPost = _between(
        header,
        'class RowPostProcessor final',
        '// dummy node before a track/row',
      );
      final processBlock = _between(
        rowPost,
        'void processBlock(',
        'bool isBusesLayoutSupported(',
      );

      expect(
        RegExp(
          r'automation\.processBlock\(buffer, midi\);\s*'
          r'gain\.processBlock\(buffer, midi\);\s*'
          r'pan\.processBlock\(buffer, midi\);\s*'
          r'meterTap\.processBlock\(buffer, midi\);',
        ).hasMatch(processBlock),
        isTrue,
      );
      expect(processBlock, isNot(contains('make_unique')));
      expect(processBlock, isNot(contains('new ')));
      expect(processBlock, isNot(contains('mutex')));
      expect(processBlock, isNot(contains('lock_guard')));
    });

    test('live rows use two fixed graph nodes: $root', () {
      final header = File('$root/JuceEngine.h').readAsStringSync();
      final source = File('$root/JuceEngine.cpp').readAsStringSync();
      final rowState = _between(
        header,
        'struct RowState',
        'struct AutomationParameterTarget',
      );
      final attach = _between(
        source,
        'void JuceEngine::attachRowBusNodes(',
        'void JuceEngine::ensureRowBusNodesAttached(',
      );

      expect(rowState, contains('Node::Ptr inputNode;'));
      expect(rowState, contains('Node::Ptr postNode;'));
      for (final removed in <String>[
        'automationNode',
        'gainNode',
        'panNode',
        'meterTapNode',
      ]) {
        expect(rowState, isNot(contains(removed)));
      }
      expect(attach, contains('std::make_unique<TrackInputProcessor>'));
      expect(attach, contains('std::make_unique<RowPostProcessor>'));
      expect(attach, isNot(contains('std::make_unique<SimpleGainProcessor>')));
      expect(attach, isNot(contains('std::make_unique<StereoPanProcessor>')));
      expect(
        attach,
        isNot(contains('std::make_unique<VolumeAutomationProcessor>')),
      );
      expect(attach, isNot(contains('std::make_unique<MeterTapProcessor>')));
    });

    test('offline export and automation retain the compact node: $root', () {
      final header = File('$root/JuceEngine.h').readAsStringSync();
      final source = File('$root/JuceEngine.cpp').readAsStringSync();
      final automationTarget = _between(
        header,
        'struct AutomationParameterTarget',
        'struct AutomationEffectLaneSnapshot',
      );
      final offline = _between(
        source,
        'bool buildOfflineExportContext(',
        'void applyOfflineAutomationAtTimeSeconds(',
      );
      final snapshot = _between(
        source,
        'void JuceEngine::publishAutomationSnapshotLocked()',
        'void JuceEngine::applyTrackEffectAutomationAtTimeSeconds(',
      );

      expect(offline, contains('std::make_unique<RowPostProcessor>'));
      expect(offline, contains('row.postNode'));
      expect(automationTarget, contains('embeddedProcessor'));
      expect(
        snapshot,
        contains('rowSnapshot.gainTarget.node = rowState.postNode'),
      );
      expect(snapshot, contains('rowSnapshot.gainTarget.embeddedProcessor'));
      expect(
        snapshot,
        contains('rowSnapshot.panTarget.node = rowState.postNode'),
      );
      expect(snapshot, contains('rowSnapshot.panTarget.embeddedProcessor'));
    });

    test('playback routing validation takes one graph snapshot: $root', () {
      final header = File('$root/JuceEngine.h').readAsStringSync();
      final source = File('$root/JuceEngine.cpp').readAsStringSync();
      final validation = _between(
        source,
        'void JuceEngine::ensureMasterOutputRouting()',
        '\nnamespace\n{',
      );

      expect(
        RegExp(r'graph\.getConnections\(\)').allMatches(validation),
        hasLength(1),
      );
      expect(validation, contains('stereoConnections'));
      expect(validation, contains('isStereoConnectionPresent'));
      expect(validation, contains('rewireMasterFxChain'));
      expect(source, isNot(contains('isGraphConnectionPresent')));
      expect(header, isNot(contains('isGraphConnectionPresent')));
    });
  }

  test('Apple and Android row post processor definitions stay aligned', () {
    String definition(String root) {
      final header = File('$root/JuceEngine.h').readAsStringSync();
      final start = header.indexOf('class RowPostProcessor final');
      final end = header.indexOf('\n};', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      return header.substring(start, end + 3);
    }

    expect(definition(roots[0]), definition(roots[1]));
  });
}
