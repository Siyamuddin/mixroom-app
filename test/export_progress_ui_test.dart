import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/export_progress_ui.dart';

void main() {
  test('normalizes exporting labels without trailing dots', () {
    expect(
      ExportProgressUi.normalizedExportingLabel('Exporting...'),
      'Exporting',
    );
    expect(
      ExportProgressUi.normalizedExportingLabel('Exporting\u2026'),
      'Exporting',
    );
    expect(ExportProgressUi.normalizedExportingLabel('   '), 'Exporting');
  });

  test('cycles animated dots and clamps progress labels', () {
    expect(ExportProgressUi.animatedDots(0), '.');
    expect(ExportProgressUi.animatedDots(1), '..');
    expect(ExportProgressUi.animatedDots(2), '...');
    expect(ExportProgressUi.animatedDots(3), '.');

    expect(ExportProgressUi.progressPercentLabel(-1), '0%');
    expect(ExportProgressUi.progressPercentLabel(0.424), '42%');
    expect(ExportProgressUi.progressPercentLabel(2), '100%');
  });
}
