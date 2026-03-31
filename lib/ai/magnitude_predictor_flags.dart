const bool kUseLearnedMagnitudePredictor = bool.fromEnvironment(
  'MIXROOM_USE_LEARNED_MAGNITUDES',
  defaultValue: true,
);

const String kMixApplyClassifierAsset = String.fromEnvironment(
  'MIXROOM_MIX_APPLY_MODEL_ASSET',
  defaultValue:
      'assets/models/mix_apply_classifier_official_sessions_20260330_seed1.onnx',
);

const String kMixMagnitudeRegressorAsset = String.fromEnvironment(
  'MIXROOM_MIX_MAGNITUDE_MODEL_ASSET',
  defaultValue:
      'assets/models/mix_magnitude_regressor_official_sessions_20260330_seed1.onnx',
);

const bool kMixPreferBundledMagnitudeModels = bool.fromEnvironment(
  'MIXROOM_PREFER_BUNDLED_MAGNITUDE_MODELS',
  defaultValue: false,
);

const String kMixMagnitudeModelManifestUrl = String.fromEnvironment(
  'MIXROOM_MAGNITUDE_MODEL_MANIFEST_URL',
  defaultValue: 'https://d22u50embnfa6f.cloudfront.net/magnitude/manifest.json',
);

const int kMixMagnitudeModelManifestTimeoutSeconds = int.fromEnvironment(
  'MIXROOM_MAGNITUDE_MODEL_MANIFEST_TIMEOUT_SECONDS',
  defaultValue: 4,
);

const int kMixMagnitudeModelRefreshIntervalHours = int.fromEnvironment(
  'MIXROOM_MAGNITUDE_MODEL_REFRESH_INTERVAL_HOURS',
  defaultValue: 6,
);
