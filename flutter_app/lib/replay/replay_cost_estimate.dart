/// Explicit, user-supplied *round-trip* execution cost per base-asset unit,
/// expressed in the chart's QUOTE currency (the same units as OHLC prices).
/// It may combine spread, commissions converted to quote units, and slippage.
/// A missing estimate is different from assuming zero costs.
class ReplayCostEstimate {
  const ReplayCostEstimate({required this.roundTripPriceUnits});

  final double roundTripPriceUnits;

  void validate() {
    if (!roundTripPriceUnits.isFinite || roundTripPriceUnits < 0) {
      throw const FormatException(
        'التكلفة التقديرية الكاملة للدخول والخروج يجب ألا تكون سالبة.');
    }
  }

  /// Convert the estimated monetary cost to the trade's initial risk units.
  double netR({required double grossR, required double riskPerUnit}) {
    validate();
    if (!riskPerUnit.isFinite || riskPerUnit <= 0 || !grossR.isFinite) {
      throw const FormatException('لا يمكن احتساب الصافي دون مخاطرة صالحة.');
    }
    return grossR - roundTripPriceUnits / riskPerUnit;
  }
}
