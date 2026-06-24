import 'package:flutter/services.dart';

class DesktopSliderWheelSensitivity {
  const DesktopSliderWheelSensitivity({
    required this.normal,
    required this.fine,
    required this.mediumFine,
    required this.coarse,
  });

  static const DesktopSliderWheelSensitivity defaults =
      DesktopSliderWheelSensitivity(
    normal: 1.0,
    fine: 0.1,
    mediumFine: 0.25,
    coarse: 5.0,
  );

  final double normal;
  final double fine;
  final double mediumFine;
  final double coarse;

  DesktopSliderWheelSensitivity copyWith({
    double? normal,
    double? fine,
    double? mediumFine,
    double? coarse,
  }) {
    return DesktopSliderWheelSensitivity.sanitized(
      normal: normal ?? this.normal,
      fine: fine ?? this.fine,
      mediumFine: mediumFine ?? this.mediumFine,
      coarse: coarse ?? this.coarse,
    );
  }

  factory DesktopSliderWheelSensitivity.sanitized({
    required double normal,
    required double fine,
    required double mediumFine,
    required double coarse,
  }) {
    return DesktopSliderWheelSensitivity(
      normal: normal.clamp(0.05, 8.0).toDouble(),
      fine: fine.clamp(0.01, 2.0).toDouble(),
      mediumFine: mediumFine.clamp(0.02, 4.0).toDouble(),
      coarse: coarse.clamp(1.0, 20.0).toDouble(),
    );
  }

  factory DesktopSliderWheelSensitivity.fromJson(Map<String, dynamic> json) {
    return DesktopSliderWheelSensitivity.sanitized(
      normal: (json['normal'] as num?)?.toDouble() ?? defaults.normal,
      fine: (json['fine'] as num?)?.toDouble() ?? defaults.fine,
      mediumFine:
          (json['mediumFine'] as num?)?.toDouble() ?? defaults.mediumFine,
      coarse: (json['coarse'] as num?)?.toDouble() ?? defaults.coarse,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'normal': normal,
        'fine': fine,
        'mediumFine': mediumFine,
        'coarse': coarse,
      };

  double multiplierForKeyboard(HardwareKeyboard keyboard) {
    if (keyboard.isMetaPressed || keyboard.isControlPressed) return coarse;
    if (keyboard.isShiftPressed) return fine;
    if (keyboard.isAltPressed) return mediumFine;
    return normal;
  }
}

class DesktopSliderWheelSensitivityStore {
  DesktopSliderWheelSensitivityStore._();

  static DesktopSliderWheelSensitivity _current =
      DesktopSliderWheelSensitivity.defaults;

  static DesktopSliderWheelSensitivity get current => _current;

  static set current(DesktopSliderWheelSensitivity value) {
    _current = DesktopSliderWheelSensitivity.sanitized(
      normal: value.normal,
      fine: value.fine,
      mediumFine: value.mediumFine,
      coarse: value.coarse,
    );
  }

  static double multiplierForKeyboard(HardwareKeyboard keyboard) =>
      _current.multiplierForKeyboard(keyboard);

  static void reset() {
    _current = DesktopSliderWheelSensitivity.defaults;
  }
}
