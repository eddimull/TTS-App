/// Multiplier <-> percent-delta helpers (1.1 <-> +10%).
double multiplierToPercent(double m) =>
    double.parse(((m - 1) * 100).toStringAsFixed(2));

double percentToMultiplier(double pct) =>
    double.parse((1 + pct / 100).toStringAsFixed(4));

/// "+10%", "-20%", "0%" for a multiplier.
String formatMultiplier(double m) {
  final pct = multiplierToPercent(m);
  final text = pct == pct.roundToDouble()
      ? pct.toStringAsFixed(0)
      : pct.toString();
  if (pct > 0) return '+$text%';
  return '$text%';
}

/// Plain number text without a trailing ".0".
String trimNumber(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
