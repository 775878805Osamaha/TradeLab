/// Formats price-axis and chart drawing numbers without altering broker
/// values or the legacy visible punctuation/decimal precision.
///
/// The original candle painter instantiated a new RegExp for EVERY axis
/// price label and order pill during EVERY pan/pinch frame. Keep exactly
/// the same thousands-separator pattern but compile it once for all paints.
abstract final class ChartPriceTextFormatter {
  static final RegExp _thousands =
      RegExp(r'\B(?=(\d{3})+(?!\d))');

  static String price(double value, int digits) {
    final parts = value.toStringAsFixed(digits).split('.');
    final integer = parts.first.replaceAllMapped(
      _thousands, (_) => ',');
    return digits == 0 ? integer : '$' + 'integer.' + '${parts.last}';
  }
}
