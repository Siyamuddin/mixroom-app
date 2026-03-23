const bool kUseLearnedMagnitudePredictor = bool.fromEnvironment(
  'MIXROOM_USE_LEARNED_MAGNITUDES',
  defaultValue: true,
);

const String kMixApplyClassifierAsset = String.fromEnvironment(
  'MIXROOM_MIX_APPLY_MODEL_ASSET',
  defaultValue: 'assets/models/mix_apply_classifier2.onnx',
);

const String kMixMagnitudeRegressorAsset = String.fromEnvironment(
  'MIXROOM_MIX_MAGNITUDE_MODEL_ASSET',
  defaultValue: 'assets/models/mix_magnitude_regressor2.onnx',
);
