import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/automation_point_sanitizer.dart';
import 'package:mixroom/models/models.dart';

void main() {
  test('sanitizing automation points preserves future timestamps', () {
    final sanitized = sanitizeAutomationPointsPreservingFutureTimes(
      <AutomationPoint>[
        AutomationPoint(x: 120000.0, volume: 0.8),
        AutomationPoint(x: -50.0, volume: 1.4),
        AutomationPoint(x: 5000.0, volume: -0.2),
      ],
    );

    expect(sanitized.map((point) => point.x), <double>[0.0, 5000.0, 120000.0]);
    expect(sanitized.map((point) => point.volume), <double>[1.0, 0.0, 0.8]);
  });

  test('sanitizing a single point does not move it to project start', () {
    final sanitized = sanitizeAutomationPointsPreservingFutureTimes(
      <AutomationPoint>[
        AutomationPoint(x: 45000.0, volume: 0.6),
      ],
    );

    expect(sanitized, hasLength(1));
    expect(sanitized.single.x, 45000.0);
    expect(sanitized.single.volume, 0.6);
  });

  test('automation clip length sanitizing has no project-duration cap', () {
    expect(sanitizeAutomationLengthMs(240000.0, minMs: 80.0), 240000.0);
    expect(sanitizeAutomationLengthMs(10.0, minMs: 80.0), 80.0);
  });
}
