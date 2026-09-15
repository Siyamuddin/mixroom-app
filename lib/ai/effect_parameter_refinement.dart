/// Resolve a deferred model scalar only after the engine exposes the parameter.
/// [proposal] has already gone through the normal action clamps and quantization.
double applyDeferredParameterRefinement({
  required double current,
  required double proposal,
  required Map<String, dynamic> parameter,
  required Map<String, dynamic> action,
}) {
  final raw = action['refinement_scale'];
  if (parameter['type'] != 'float' || raw is! num || !raw.isFinite) {
    return proposal;
  }
  final low = parameter['min'];
  final high = parameter['max'];
  if (low is! num ||
      high is! num ||
      !low.isFinite ||
      !high.isFinite ||
      high <= low) {
    return proposal;
  }
  var value = (current + (proposal - current) * raw.clamp(0, 3))
      .clamp(low, high)
      .toDouble();
  final hardLow = action['clamp_min'];
  final hardHigh = action['clamp_max'];
  if (hardLow is num && hardLow.isFinite && value < hardLow) {
    value = hardLow.toDouble();
  }
  if (hardHigh is num && hardHigh.isFinite && value > hardHigh) {
    value = hardHigh.toDouble();
  }
  value = value.clamp(low, high).toDouble();
  final interval = parameter['interval'];
  if (interval is num && interval.isFinite && interval > 0) {
    value = (low + ((value - low) / interval).round() * interval)
        .clamp(low, high)
        .toDouble();
  }
  return value;
}
