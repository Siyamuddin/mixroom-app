const Map<String, List<String>> kExposedEffectParameterNames =
    <String, List<String>>{
  'Reverb': <String>['Room Size', 'Mix', 'Predelay'],
  'Compressor': <String>[
    'Threshold',
    'Attack',
    'Release',
    'Ratio',
    'Makeup',
    'Mix',
  ],
  'Limiter': <String>['Threshold', 'Release', 'Ceiling'],
  'Clipper': <String>['Threshold', 'Ceiling'],
  'EQ Parametric': <String>[
    'HPF Frequency',
    'HPF Slope',
    'Band 1 Frequency',
    'Band 1 Gain',
    'Band 1 Q',
    'Band 2 Frequency',
    'Band 2 Gain',
    'Band 2 Q',
    'Band 3 Frequency',
    'Band 3 Gain',
    'Band 3 Q',
    'Band 4 Frequency',
    'Band 4 Gain',
    'Band 4 Q',
    'LPF Slope',
    'LPF Frequency',
  ],
  'EQ 3-Band': <String>['Low Gain', 'Mid Gain', 'High Gain'],
  'Degrade': <String>['Mode', 'Tone', 'Depth', 'Spread'],
  'Delay': <String>['Delay Time', 'Feedback', 'Mix'],
  'Stereo': <String>['Width', 'Low Bypass', 'Mono'],
  'Stereo Pro': <String>['Gain', 'Width', 'Asymmetry', 'Rotation'],
  'Volume Shaper': <String>[
    'Shape',
    'Rate',
    'Phase',
    'Depth',
    'Smooth',
    'Swing',
    'Mix',
  ],
  'Time Shaper': <String>[
    'Pattern',
    'Rate',
    'Phase',
    'Amount',
    'Smooth',
    'Swing',
    'Mix',
  ],
  'Gain': <String>['Volume'],
};

bool hasCanonicalExposedEffectParameters(String effectName) {
  return kExposedEffectParameterNames.containsKey(effectName.trim());
}

List<Map<String, dynamic>> exposedEffectParameters(
  String effectName,
  List<Map<String, dynamic>> params,
) {
  final allowedNames = kExposedEffectParameterNames[effectName.trim()];
  if (allowedNames == null) return params;

  final byName = <String, Map<String, dynamic>>{};
  for (final param in params) {
    final name = (param['name'] ?? '').toString().trim();
    if (name.isEmpty || byName.containsKey(name)) continue;
    byName[name] = param;
  }
  return allowedNames
      .where(byName.containsKey)
      .map((name) => byName[name]!)
      .toList(growable: false);
}

Map<String, dynamic> exposedEffectParameterValues(
  String effectName,
  List<Map<String, dynamic>> params,
) {
  return <String, dynamic>{
    for (final param in exposedEffectParameters(effectName, params))
      if ((param['name'] ?? '').toString().trim().isNotEmpty)
        (param['name'] ?? '').toString().trim(): param['value'],
  };
}

Map<String, dynamic> exposedEffectParameterValueMap(
  String effectName,
  Map<String, dynamic> values,
) {
  final allowedNames = kExposedEffectParameterNames[effectName.trim()];
  if (allowedNames == null) return values;

  return <String, dynamic>{
    for (final name in allowedNames)
      if (values.containsKey(name)) name: values[name],
  };
}
