import 'dart:math' as math;

import 'package:flutter/material.dart';

class DbfsMeterVisuals {
  static const double floorDb = -60.0;
  static const double halfScaleDb = -15.0;
  static const double warningDb = -10.0;
  static const double hotDb = -3.0;
  static const double peakDb = 0.0;

  static double ampToDbfs(double amp01) {
    final amp = amp01.clamp(0.0, 1.0).toDouble();
    if (amp <= 0.000001) return double.negativeInfinity;
    return 20 * math.log(amp) / math.ln10;
  }

  static double dbfsToUnit(double dbfs) {
    if (!dbfs.isFinite || dbfs <= floorDb) return 0.0;
    if (dbfs >= peakDb) return 1.0;

    if (dbfs <= halfScaleDb) {
      final t = (dbfs - floorDb) / (halfScaleDb - floorDb);
      return (0.5 * t).clamp(0.0, 0.5).toDouble();
    }

    final t = (dbfs - halfScaleDb) / (peakDb - halfScaleDb);
    return (0.5 + (0.5 * t)).clamp(0.5, 1.0).toDouble();
  }

  static double ampToUnit(double amp01) => dbfsToUnit(ampToDbfs(amp01));

  static List<double> gradientStops() {
    return <double>[
      0.0,
      dbfsToUnit(warningDb),
      dbfsToUnit(hotDb),
      1.0,
    ];
  }

  static LinearGradient horizontalGradient({double opacity = 1.0}) {
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: <Color>[
        const Color(0xFF2EC96D).withValues(alpha: opacity),
        const Color(0xFFF5D24D).withValues(alpha: opacity),
        const Color(0xFFF39A3A).withValues(alpha: opacity),
        const Color(0xFFE55A5A).withValues(alpha: opacity),
      ],
      stops: gradientStops(),
    );
  }

  static LinearGradient verticalGradient({double opacity = 1.0}) {
    return LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: <Color>[
        const Color(0xFF2EC96D).withValues(alpha: opacity),
        const Color(0xFFF5D24D).withValues(alpha: opacity),
        const Color(0xFFF39A3A).withValues(alpha: opacity),
        const Color(0xFFE55A5A).withValues(alpha: opacity),
      ],
      stops: gradientStops(),
    );
  }

  static Color statusColor(double dbfs) {
    if (dbfs >= peakDb - 0.1) return const Color(0xFFE55A5A);
    if (dbfs >= hotDb) return const Color(0xFFF39A3A);
    if (dbfs >= warningDb) return const Color(0xFFF5D24D);
    if (dbfs >= -18.0) return const Color(0xFF7FD96B);
    return const Color(0xFF58BE84);
  }
}
