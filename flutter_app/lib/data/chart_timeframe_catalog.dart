import 'tradelab_data.dart';

/// Source-specific broker candle intervals exposed by the chart picker.
/// Only list intervals supported by the corresponding verified provider:
/// cTrader Open API has M2, but no native H2 trendbars; Binance has 2h,
/// but no 2m klines. Never synthesize a timeframe from adjacent OHLC.
class ChartTimeframeCatalog {
  const ChartTimeframeCatalog._();

  static const ctrader = <String>[
    '1m', '2m', '3m', '5m', '15m', '30m', '1h', '4h',
    '1D', '1W', '1M',
  ];

  static const binance = <String>[
    '1m', '3m', '5m', '15m', '30m', '1h', '2h', '4h',
    '1D', '1W', '1M',
  ];

  static List<String> forSource(TradeSource source) =>
      source == TradeSource.ctrader ? ctrader : binance;

  /// Nominal verified source open-time step. Months are variable length.
  /// This does NOT prove there was market trading in a missing interval;
  /// it only decides if a cached older page may join the displayed history
  /// without skipping a period whose broker data was never cached.
  static int? fixedOpenStepMs(String timeframe) => switch (timeframe) {
    '1m' => 60000,
    '2m' => 120000,
    '3m' => 180000,
    '5m' => 300000,
    '15m' => 900000,
    '30m' => 1800000,
    '1h' => 3600000,
    '2h' => 7200000,
    '4h' => 14400000,
    '1D' => 86400000,
    '1W' => 604800000,
    _ => null,
  };

  /// Arabic UI label for a native market-provider interval. The machine
  /// timeframe remains unchanged for authenticated broker requests/Replay.
  /// Use a single mapping in both the chart and Replay toolbar.
  static String displayLabel(String timeframe) => switch (timeframe) {
    '1m' => '1 دق',
    '2m' => '2 دق',
    '3m' => '3 دق',
    '5m' => '5 دق',
    '15m' => '15 دق',
    '30m' => '30 دق',
    '1h' => '1 ساعة',
    '2h' => 'ساعتان',
    '4h' => '4 ساعات',
    '1D' => 'يومي',
    '1W' => 'أسبوعي',
    '1M' => 'شهري',
    _ => timeframe,
  };

  static bool isSupported(TradeSource source, String timeframe) =>
      forSource(source).contains(timeframe);

  /// Switching between broker and crypto must never silently request an
  /// invalid interval. Choose a nearby NATIVE interval, not aggregated bars.
  static String compatibleOnSwitch(TradeSource source, String timeframe) {
    if (isSupported(source, timeframe)) return timeframe;
    if (timeframe == '2h') return '1h';
    if (timeframe == '2m') return '1m';
    return '1m';
  }
}
