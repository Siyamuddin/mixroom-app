class AutomationEffectDisplayLabel {
  final String baseName;
  final int ordinal;
  final int totalCount;
  final String displayName;

  const AutomationEffectDisplayLabel({
    required this.baseName,
    required this.ordinal,
    required this.totalCount,
    required this.displayName,
  });

  bool get isDuplicate => totalCount > 1;
}

List<AutomationEffectDisplayLabel> buildAutomationEffectDisplayLabels({
  required List<String> effectNames,
  List<String>? fallbackIds,
}) {
  final ids = fallbackIds ?? const <String>[];

  String baseNameForIndex(int index) {
    final name = (index < effectNames.length ? effectNames[index] : '').trim();
    if (name.isNotEmpty) return name;
    final fallback = (index < ids.length ? ids[index] : '').trim();
    if (fallback.isNotEmpty) return fallback;
    return 'Effect';
  }

  final countByBaseName = <String, int>{};
  for (int i = 0; i < effectNames.length; i++) {
    final baseName = baseNameForIndex(i);
    countByBaseName.update(baseName, (value) => value + 1, ifAbsent: () => 1);
  }

  final seenByBaseName = <String, int>{};
  final labels = <AutomationEffectDisplayLabel>[];
  for (int i = 0; i < effectNames.length; i++) {
    final baseName = baseNameForIndex(i);
    final ordinal = seenByBaseName.update(
      baseName,
      (value) => value + 1,
      ifAbsent: () => 0,
    );
    final totalCount = countByBaseName[baseName] ?? 1;
    labels.add(
      AutomationEffectDisplayLabel(
        baseName: baseName,
        ordinal: ordinal,
        totalCount: totalCount,
        displayName: totalCount > 1 ? '$baseName #${ordinal + 1}' : baseName,
      ),
    );
  }
  return labels;
}
