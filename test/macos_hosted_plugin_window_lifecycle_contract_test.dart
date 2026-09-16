import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _between(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, isNonNegative, reason: 'Missing start marker: $start');
  expect(endIndex, greaterThan(startIndex), reason: 'Missing end marker: $end');
  return source.substring(startIndex, endIndex);
}

void main() {
  late String engineHeader;
  late String engineSource;
  late String bridge;
  late String runnerTests;

  setUpAll(() {
    engineHeader = File(
      'juce_audio_engine/ios/Classes/JuceEngine.h',
    ).readAsStringSync();
    engineSource = File(
      'juce_audio_engine/ios/Classes/JuceEngine.cpp',
    ).readAsStringSync();
    bridge = File(
      'juce_audio_engine/ios/Classes/JuceBridge.mm',
    ).readAsStringSync();
    runnerTests = File(
      'macos/RunnerTests/RunnerTests.swift',
    ).readAsStringSync();
  });

  test('normal close destroys the editor after owner-scoped cleanup', () {
    final windowClass = _between(
      engineHeader,
      'class HostedPluginEditorWindow : public juce::DocumentWindow',
      'class HostedPluginEditorShell final',
    );
    final closeHandler = _between(
      windowClass,
      'void closeButtonPressed() override',
      'private:',
    );

    expect(
      windowClass,
      contains(
        'requestCloseFromHost()\n    {\n        requestDestroyFromHost();',
      ),
    );
    expect(
      closeHandler,
      contains('mixroomCloseHostedPluginNativeWindowsForOwner('),
    );
    expect(
      closeHandler.indexOf('mixroomCloseHostedPluginNativeWindowsForOwner('),
      lessThan(closeHandler.indexOf('setVisible(false);')),
    );
    expect(closeHandler, contains('onClose();'));
    expect(windowClass, isNot(contains('destroyOnClose')));
  });

  test('capture is owner-scoped and does not reject JUCE auxiliaries', () {
    final attributionPolicy = _between(
      bridge,
      'static BOOL mixroomShouldTrackAttributedPluginWindow(',
      'static BOOL mixroomTrackAttributedPluginWindow(',
    );
    final captureImplementation = bridge.substring(
      bridge.indexOf('@interface MixroomHostedPluginWindowCapture'),
    );
    final beginCapture = _between(
      captureImplementation,
      'extern "C" bool mixroomBeginHostedPluginWindowCapture(',
      'extern "C" bool mixroomEndHostedPluginWindowCapture(',
    );

    expect(attributionPolicy, isNot(contains('hasPrefix:@"JUCEWindow_"')));
    expect(attributionPolicy, contains('window == hostWindow'));
    expect(
      beginCapture,
      contains('rejected nested or duplicate editor capture'),
    );
    expect(beginCapture, contains('return began == YES;'));
    expect(bridge, isNot(contains('mixroomAdoptHostedPluginAuxiliaryWindows')));
  });

  test('editor creation uses an exception-safe capture scope', () {
    final captureScope = _between(
      engineSource,
      'class ScopedHostedPluginWindowCapture final',
      '} // namespace\n\nbool JuceEngine::openPluginEditorWindowForNode(',
    );
    final targetOpen = _between(
      engineSource,
      'bool JuceEngine::openPluginEditorWindowForTarget(',
      'void JuceEngine::closePluginEditorWindowForNode(',
    );

    expect(captureScope, contains('~ScopedHostedPluginWindowCapture()'));
    expect(captureScope, contains('mixroomEndHostedPluginWindowCapture('));
    expect(
      captureScope,
      contains('mixroomCloseHostedPluginNativeWindowsForOwner('),
    );
    expect(captureScope, contains('mixroomReleaseHostedPluginWindowCapture('));
    expect(targetOpen, contains('ScopedHostedPluginWindowCapture capture('));
    expect(
      targetOpen.indexOf('ScopedHostedPluginWindowCapture capture('),
      lessThan(targetOpen.indexOf('hasEditor()')),
    );
    expect(targetOpen, contains('createEditor()'));
    expect(targetOpen, isNot(contains('graphRenderMutex')));
  });

  test('entrypoints retain processor targets across the graph lock', () {
    final midiOpen = _between(
      engineSource,
      'bool JuceEngine::openMidiClipPluginEditor(int clipId)',
      'void JuceEngine::setMidiClipPluginParameter(',
    );
    final trackOpen = _between(
      engineSource,
      'bool JuceEngine::openTrackPluginEditor(int trackRow, int effectIndex)',
      'void JuceEngine::setTrackEffectParameter(',
    );
    final masterOpen = _between(
      engineSource,
      'bool JuceEngine::openMasterPluginEditor(int effectIndex)',
      'void JuceEngine::setMasterEffectParameter(',
    );

    expect(midiOpen, contains('liveProcessorSharedForClip(clip)'));
    expect(
      trackOpen,
      contains('juce::AudioProcessorGraph::Node::Ptr pluginNode'),
    );
    expect(
      masterOpen,
      contains('juce::AudioProcessorGraph::Node::Ptr pluginNode'),
    );
    for (final entrypoint in [midiOpen, trackOpen, masterOpen]) {
      expect(
        entrypoint.indexOf('renderLock(graphRenderMutex)'),
        lessThan(entrypoint.indexOf('openPluginEditorWindowFor')),
      );
    }
  });

  test('shutdown destroys editors before graph mutation', () {
    final closeAll = _between(
      engineSource,
      'void JuceEngine::closeAllHostedPluginEditorWindows()',
      '#if MIXROOM_ENABLE_TEST_HOOKS && JUCE_MAC',
    );
    final shutdown = _between(
      engineSource,
      'void JuceEngine::shutdownEngine()',
      '// ============================================================\n// Helper: Build bus graph',
    );

    expect(closeAll, contains('prepareForImmediateDestruction()'));
    expect(closeAll, contains('hostedPluginEditorWindows.clear();'));
    expect(
      shutdown.indexOf('closeAllHostedPluginEditorWindows();'),
      lessThan(shutdown.indexOf('GraphMutationScope renderLock')),
    );
    expect(
      shutdown.indexOf('closeAllHostedPluginEditorWindows();'),
      lessThan(shutdown.indexOf('graph.clear();')),
    );
  });

  test('native probes cover JUCE attribution and exception cleanup', () {
    expect(
      bridge,
      contains('mixroomRunHostedPluginWindowCaptureRegressionProbe'),
    );
    expect(bridge, contains('PRO-76 JUCE auxiliary'));
    expect(bridge, contains('rejectedNestedCapture'));
    expect(bridge, contains('PRO-76 close-driven modal'));
    expect(bridge, contains('mixroomEndMatchingHostedPluginModalForWindow('));
    expect(engineSource, contains('caughtProbeException'));
    expect(runnerTests, contains('0x1ff'));
    expect(runnerTests, contains('0x1f'));
  });
}
