const bool kUseLearnedMagnitudePredictor = bool.fromEnvironment(
  'MIXROOM_USE_LEARNED_MAGNITUDES',
  defaultValue: false,
);

const String kMixApplyClassifierAsset =
    'assets/models/mix_apply_classifier.onnx';
const String kMixMagnitudeRegressorAsset =
    'assets/models/mix_magnitude_regressor.onnx';
