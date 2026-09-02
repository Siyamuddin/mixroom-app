const List<String> kMixroomBuiltInEffects = <String>[
  'Gain',
  'EQ 3-Band',
  'Compressor',
  'Dynamic Softener',
  'Transient Shaper',
  'Limiter',
  'Clipper',
  'De-Esser',
  'Distortion',
  'Degrade',
  'Delay',
  'Reverb',
  'EQ Parametric',
  'Pitch Shift',
  'Pitch Corrector',
  'Chorus',
  'Vibrato',
];

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
  'Dynamic Softener': <String>[
    'Mode',
    'Depth',
    'Focus',
    'Attack',
    'Release',
    'Cut Limit',
    'Process Trim',
    'Mix',
    'Output',
    'Delta',
    'Low Range',
    'High Range',
  ],
  'Transient Shaper': <String>[
    'Attack',
    'Pump',
    'Sustain',
    'Speed',
    'Clip',
  ],
  'Limiter': <String>['Threshold', 'Release', 'Ceiling'],
  'Clipper': <String>['Threshold', 'Ceiling'],
  'De-Esser': <String>[
    'Threshold',
    'Frequency',
    'Attack',
    'Release',
    'Stereo',
    'Wide Band',
  ],
  'Distortion': <String>[
    'Drive',
    'Volume',
    'Mix',
    'Anger',
    'DC Offset',
    'HPF Frequency',
    'LPF Frequency',
    'Pre Shape',
    'Shape Tilt',
    'Distortion Type',
  ],
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
  'Pitch Shift': <String>['Semitones', 'Mix'],
  'Pitch Corrector': <String>[
    'Key',
    'Scale',
    'Correction',
    'Retune Speed',
    'Mix',
  ],
  'Chorus': <String>['Rate', 'Depth', 'Centre Delay', 'Feedback', 'Mix'],
  'Vibrato': <String>['Rate', 'Depth', 'Centre Delay', 'Mix'],
};

/// Verified user-facing names that refer to one exact native control.
/// Keep this deliberately small: semantic or fuzzy substitutions are unsafe.
const Map<String, Map<String, String>> kExposedEffectParameterAliases =
    <String, Map<String, String>>{
  'Distortion': <String, String>{
    'Offset': 'DC Offset',
    'Shape': 'Pre Shape',
  },
  'Chorus': <String, String>{'Center Delay': 'Centre Delay'},
  'Vibrato': <String, String>{'Center Delay': 'Centre Delay'},
};

/// Resolves an exact built-in effect identity without semantic or fuzzy
/// matching. Case-insensitive matching is accepted because effect IDs are
/// otherwise authoritative and unique.
String? canonicalMixroomBuiltInEffectId(String submittedId) {
  final trimmed = submittedId.trim();
  if (kMixroomBuiltInEffects.contains(trimmed)) return trimmed;
  final normalized = trimmed.toLowerCase();
  final matches = kMixroomBuiltInEffects
      .where((candidate) => candidate.toLowerCase() == normalized)
      .toList(growable: false);
  return matches.length == 1 ? matches.single : null;
}

String _normalizedEffectParameterSpelling(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');

String? canonicalExposedEffectParameterName(
  String effectName,
  String submittedName,
  Iterable<String> authoritativeNames,
) {
  final exactNames = authoritativeNames.toSet();
  if (exactNames.contains(submittedName)) return submittedName;

  final normalized = _normalizedEffectParameterSpelling(submittedName);
  final normalizedMatches = exactNames
      .where(
        (candidate) =>
            _normalizedEffectParameterSpelling(candidate) == normalized,
      )
      .toList(growable: false);
  if (normalizedMatches.length == 1) return normalizedMatches.single;

  final aliases = kExposedEffectParameterAliases[effectName.trim()];
  if (aliases == null) return null;
  final aliasMatches = aliases.entries
      .where(
        (entry) =>
            _normalizedEffectParameterSpelling(entry.key) == normalized &&
            exactNames.contains(entry.value),
      )
      .map((entry) => entry.value)
      .toSet();
  return aliasMatches.length == 1 ? aliasMatches.single : null;
}

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
