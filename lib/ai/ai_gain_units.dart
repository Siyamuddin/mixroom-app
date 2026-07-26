double rowGainUiToDb(double value) {
  const dbMin = -60.0;
  const dbMax = 6.0;
  const uiUnity = 2.0;
  const uiMax = 3.0;
  final clamped = value.clamp(0.0, uiMax).toDouble();
  if (clamped <= uiUnity) {
    return dbMin + ((0.0 - dbMin) * (clamped / uiUnity));
  }
  return dbMax * ((clamped - uiUnity) / (uiMax - uiUnity));
}

double rowGainDbToUi(double db) {
  const dbMin = -60.0;
  const dbMax = 6.0;
  const uiUnity = 2.0;
  const uiMax = 3.0;
  final clamped = db.clamp(dbMin, dbMax).toDouble();
  if (clamped <= 0.0) {
    return uiUnity * ((clamped - dbMin) / (0.0 - dbMin));
  }
  return uiUnity + ((uiMax - uiUnity) * (clamped / dbMax));
}

double adjustRowGainUiByDb(double currentValue, double deltaDb) =>
    rowGainDbToUi(rowGainUiToDb(currentValue) + deltaDb);
