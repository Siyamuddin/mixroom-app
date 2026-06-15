enum TopBarVisualizerMode {
  spectrum,
  bars,
  meter,
  scope,
  waveform,
}

extension TopBarVisualizerModeUi on TopBarVisualizerMode {
  TopBarVisualizerMode get next {
    return switch (this) {
      TopBarVisualizerMode.spectrum => TopBarVisualizerMode.bars,
      TopBarVisualizerMode.bars => TopBarVisualizerMode.meter,
      TopBarVisualizerMode.meter => TopBarVisualizerMode.scope,
      TopBarVisualizerMode.scope => TopBarVisualizerMode.waveform,
      TopBarVisualizerMode.waveform => TopBarVisualizerMode.spectrum,
    };
  }

  String get label {
    return switch (this) {
      TopBarVisualizerMode.spectrum => 'EQ analyzer',
      TopBarVisualizerMode.bars => 'Spectrum bars',
      TopBarVisualizerMode.meter => 'dB meter',
      TopBarVisualizerMode.scope => 'Vectorscope',
      TopBarVisualizerMode.waveform => 'Oscilloscope',
    };
  }

  String get shortLabel {
    return switch (this) {
      TopBarVisualizerMode.spectrum => 'EQ',
      TopBarVisualizerMode.bars => 'Bars',
      TopBarVisualizerMode.meter => 'Meter',
      TopBarVisualizerMode.scope => 'Scope',
      TopBarVisualizerMode.waveform => 'Wave',
    };
  }

  String get semanticValue => label;

  String get nextSemanticHint => 'Switch to ${next.label}';
}
