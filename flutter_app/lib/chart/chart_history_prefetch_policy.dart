import 'dart:math' as math;

/// Begin a broker/cache older-page request before the pan reaches the
/// historical edge of the currently loaded source candles.
///
/// This only determines *when* to ask; the caller still authenticates every
/// cTrader/Binance page, enforces loading/exhaustion/error guards and disables
/// prefetch entirely during Replay. Never infer missing market candles.
///
/// Two visible chart widths give a bounded lead on 320/390dp Android screens.
/// Cap to 256 candles so extreme zooms do not trigger excessive early broker
/// requests; keep the original minimum 25-candle lead.
abstract final class ChartHistoryPrefetchPolicy {
  static const double screensAhead = 2.0;
  static const double minimumLeadBars = 25.0;
  static const double maximumLeadBars = 256.0;

  static bool shouldPrefetch({
    required double scrollBars,
    required int loadedBars,
    required double plotWidth,
    required double barWidth,
  }) {
    if (loadedBars <= 0 || !scrollBars.isFinite ||
        !plotWidth.isFinite || plotWidth <= 0 ||
        !barWidth.isFinite || barWidth <= 0 ||
        scrollBars <= 0) {
      return false;
    }
    final barsOnScreen = plotWidth / barWidth;
    if (!barsOnScreen.isFinite || barsOnScreen <= 0) return false;
    final lead = math.max(minimumLeadBars,
        math.min(maximumLeadBars, barsOnScreen * screensAhead));
    return scrollBars > loadedBars - barsOnScreen - lead;
  }
}
