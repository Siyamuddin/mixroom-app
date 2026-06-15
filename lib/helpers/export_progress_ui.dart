class ExportProgressUi {
  static const String unicodeEllipsis = '\u2026';

  static String normalizedExportingLabel(String rawLabel) {
    var label = rawLabel.trimRight();
    while (label.endsWith('.') || label.endsWith(unicodeEllipsis)) {
      label = label.substring(0, label.length - 1).trimRight();
    }
    return label.isEmpty ? 'Exporting' : label;
  }

  static String animatedDots(int step) {
    final normalizedStep = step % 3;
    return '.' * (normalizedStep + 1);
  }

  static String progressPercentLabel(double progress) {
    final clamped = progress.clamp(0.0, 1.0).toDouble();
    return '${(clamped * 100).round()}%';
  }
}
