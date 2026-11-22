import 'dart:ui';

/// A dark phone theme cannot paint the panel's legacy default black ruler
/// labels on a dark canvas: they become effectively invisible even though
/// authenticated prices and candle geometry are available.
///
/// This render-only contrast guard affects ONLY the default black label
/// preference on a dark background. An explicitly chosen other color stays
/// unchanged; no broker price, quote, candle or Replay timeline is touched.
class ChartAxisContrast {
  const ChartAxisContrast._();

  static Color readableAxisLabel({
    required Color background,
    required int configuredArgb,
  }) {
    if (configuredArgb != 0xFF000000) return Color(configuredArgb);
    final luminance = background.computeLuminance();
    if (luminance < .09) return const Color(0xFFCBD5E1);
    if (luminance < .18) return const Color(0xFFFFFFFF);
    return const Color(0xFF000000);
  }
}
