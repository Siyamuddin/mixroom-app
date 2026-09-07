const List<String> kInstrumentPickerOrderedCategories = <String>[
  'Tools',
  'On Device',
  'Keys',
  'Guitars',
  'Strings',
  'Woodwinds',
  'Brass',
  'Percussion',
  'Drums',
  'Pads',
  'Leads',
  'Bass',
  'Plucks',
  'Synths',
  'Other',
];

String normalizeInstrumentPickerCategory(String raw) {
  final key = raw.trim().toLowerCase();
  switch (key) {
    case 'tool':
    case 'tools':
    case 'editor':
    case 'utility':
    case 'utilities':
      return 'Tools';
    case 'on device':
    case 'device':
    case 'hosted':
    case 'plugin':
    case 'plugins':
      return 'On Device';
    case 'key':
    case 'keys':
      return 'Keys';
    case 'guitar':
    case 'guitars':
      return 'Guitars';
    case 'string':
    case 'strings':
      return 'Strings';
    case 'woodwind':
    case 'woodwinds':
      return 'Woodwinds';
    case 'brass':
      return 'Brass';
    case 'percussion':
      return 'Percussion';
    case 'drum':
    case 'drums':
      return 'Drums';
    case 'pad':
    case 'pads':
      return 'Pads';
    case 'lead':
    case 'leads':
      return 'Leads';
    case 'bass':
      return 'Bass';
    case 'pluck':
    case 'plucks':
      return 'Plucks';
    case 'synth':
    case 'synths':
      return 'Synths';
    case 'other':
      return 'Other';
    default:
      return 'Other';
  }
}

String instrumentPickerCategoryForValues({
  String? explicitPickerCategory,
  String? declaredCategory,
  String? instrumentId,
  String? instrumentName,
}) {
  final explicit = explicitPickerCategory?.trim() ?? '';
  if (explicit.isNotEmpty) {
    return normalizeInstrumentPickerCategory(explicit);
  }

  final declared = (declaredCategory ?? '').trim().toLowerCase();
  final rawText = '$declared ${instrumentId ?? ''} ${instrumentName ?? ''}'
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final text = ' $rawText ';

  bool hasWord(String word) => text.contains(' $word ');

  if (hasWord('guitar') || hasWord('guitars')) {
    return 'Guitars';
  }
  if (hasWord('string') ||
      hasWord('strings') ||
      hasWord('violin') ||
      hasWord('cello')) {
    return 'Strings';
  }
  if (hasWord('woodwind') ||
      hasWord('woodwinds') ||
      hasWord('flute') ||
      hasWord('clarinet') ||
      hasWord('oboe') ||
      hasWord('bassoon') ||
      hasWord('piccolo')) {
    return 'Woodwinds';
  }
  if (hasWord('brass') ||
      hasWord('horn') ||
      hasWord('trumpet') ||
      hasWord('tuba') ||
      hasWord('trombone')) {
    return 'Brass';
  }
  if (hasWord('percussion') ||
      hasWord('marimba') ||
      hasWord('glock') ||
      hasWord('glockenspiel') ||
      hasWord('timp') ||
      hasWord('tubular') ||
      hasWord('xylophone') ||
      hasWord('xylo')) {
    return 'Percussion';
  }
  if (declared == 'drum' ||
      hasWord('drum') ||
      hasWord('drums') ||
      hasWord('kick') ||
      hasWord('snare') ||
      hasWord('hat') ||
      hasWord('clap') ||
      hasWord('cymbal') ||
      hasWord('tom') ||
      hasWord('kit') ||
      hasWord('808') ||
      hasWord('breakbeat') ||
      hasWord('trap') ||
      hasWord('dnb')) {
    return 'Drums';
  }
  if (hasWord('bass') || hasWord('sub') || hasWord('reese')) {
    return 'Bass';
  }
  if (hasWord('pad') ||
      hasWord('pads') ||
      hasWord('ambient') ||
      hasWord('cinematic')) {
    return 'Pads';
  }
  if (hasWord('pluck') ||
      hasWord('plucks') ||
      hasWord('bell') ||
      hasWord('bells')) {
    return 'Plucks';
  }
  if (hasWord('key') ||
      hasWord('keys') ||
      hasWord('piano') ||
      hasWord('organ') ||
      hasWord('ep')) {
    return 'Keys';
  }
  if (hasWord('lead') ||
      hasWord('leads') ||
      hasWord('saw') ||
      hasWord('wavetable') ||
      hasWord('wave')) {
    return 'Leads';
  }
  if (hasWord('synth') || hasWord('synths') || hasWord('harmonic')) {
    return 'Synths';
  }
  return 'Other';
}

String instrumentPickerCategoryForSpec(Map<String, dynamic> spec) {
  return instrumentPickerCategoryForValues(
    explicitPickerCategory: spec['pickerCategory'] as String?,
    declaredCategory: spec['category'] as String?,
    instrumentId: spec['id'] as String?,
    instrumentName: spec['name'] as String?,
  );
}

Map<String, dynamic> normalizeInstrumentPickerSpec(Map<String, dynamic> spec) {
  final next = Map<String, dynamic>.from(spec);
  next['pickerCategory'] = instrumentPickerCategoryForSpec(next);
  return next;
}
