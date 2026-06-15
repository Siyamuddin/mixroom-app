import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/top_bar_visualizer_mode.dart';

void main() {
  test('cycles through all master visualizer modes in UI order', () {
    expect(TopBarVisualizerMode.spectrum.next, TopBarVisualizerMode.bars);
    expect(TopBarVisualizerMode.bars.next, TopBarVisualizerMode.meter);
    expect(TopBarVisualizerMode.meter.next, TopBarVisualizerMode.scope);
    expect(TopBarVisualizerMode.scope.next, TopBarVisualizerMode.waveform);
    expect(TopBarVisualizerMode.waveform.next, TopBarVisualizerMode.spectrum);
  });

  test('exposes concise and accessible mode labels', () {
    expect(TopBarVisualizerMode.spectrum.shortLabel, 'EQ');
    expect(TopBarVisualizerMode.bars.label, 'Spectrum bars');
    expect(TopBarVisualizerMode.meter.semanticValue, 'dB meter');
    expect(TopBarVisualizerMode.scope.shortLabel, 'Scope');
    expect(TopBarVisualizerMode.waveform.label, 'Oscilloscope');
    expect(
      TopBarVisualizerMode.spectrum.nextSemanticHint,
      'Switch to Spectrum bars',
    );
  });
}
