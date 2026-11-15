import 'dart:math' as math;

import '../data/market_api.dart';

/// Presentation-only evidence about verified quote and candle timestamps.
///
/// A fresh cTrader BID/ASK quote can be newer than the most recent *closed*
/// OHLC bar. Never synthesize a new bar or move the user's historical viewport
/// to make the two prices appear equal.
abstract final class ChartFeedHealth {
  static int? intervalMinutes(String timeframe) => switch (timeframe) {
    '1m' => 1,
    '2m' => 2,
    '3m' => 3,
    '5m' => 5,
    '15m' => 15,
    '30m' => 30,
    '1h' => 60,
    '4h' => 240,
    '1D' => 1440,
    '1W' => 10080,
    '1M' => 43200,
    _ => null,
  };

  /// True if a new, verified quote revision warrants repainting its labels.
  /// cTrader account invalidation returns null; the old quote then disappears.
  static bool quoteChanged(MarketQuote? previous, MarketQuote? next) =>
      previous?.symbol != next?.symbol ||
      previous?.source != next?.source ||
      previous?.timestampMs != next?.timestampMs ||
      previous?.bid != next?.bid ||
      previous?.ask != next?.ask;

  /// A closed-bar open can be older than the current BID without being wrong:
  /// the newest forming bar has deliberately NOT been appended. Only flag
  /// a lag beyond three frame intervals (minimum ten minutes).
  ///
  /// The caller must supply a fresh broker quote (if available); otherwise
  /// the wall-clock is used for the existing chart-staleness badge. Broker
  /// calendar frames keep the same conservative threshold as before.
  static bool closedCandlesLagging({
    required int? latestClosedOpenMs,
    required String timeframe,
    required int nowMs,
    int? freshQuoteTimestampMs,
  }) {
    final frameMinutes = intervalMinutes(timeframe);
    if (latestClosedOpenMs == null || latestClosedOpenMs <= 0 ||
        frameMinutes == null) return false;
    final reference = freshQuoteTimestampMs ?? nowMs;
    if (reference <= latestClosedOpenMs) return false;
    return reference - latestClosedOpenMs >
        math.max(frameMinutes * 3, 10) * Duration.millisecondsPerMinute;
  }
}
