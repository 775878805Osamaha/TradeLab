import 'candle_period.dart';
import 'market_api.dart';

/// A local archive can contain several verified pages separated by uncovered
/// time. Never join unrelated pages into a seemingly continuous Replay chart.
/// Closed-market gaps are deliberately fetched from the provider, not guessed.
class MarketBarContinuity {
  static List<MarketBar> cachedPredecessors({
    required List<MarketBar> cached,
    required int nextOpenMs,
    required String timeframe,
  }) {
    final preceding = cached.where((bar) => bar.timestamp < nextOpenMs).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final contiguous = <MarketBar>[];
    var next = nextOpenMs;
    for (var index = preceding.length - 1; index >= 0; index--) {
      final bar = preceding[index];
      if (candlePeriodEndMs(bar.timestamp, timeframe) != next) break;
      contiguous.add(bar);
      next = bar.timestamp;
    }
    return List<MarketBar>.unmodifiable(contiguous.reversed);
  }

  static List<MarketBar> joinLatest({
    required List<MarketBar> cached,
    required List<MarketBar> provider,
    required String timeframe,
  }) {
    if (provider.isEmpty) return List<MarketBar>.unmodifiable(cached);
    final newestPage = provider.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final preceding = cachedPredecessors(
      cached: cached,
      nextOpenMs: newestPage.first.timestamp,
      timeframe: timeframe,
    );
    return List<MarketBar>.unmodifiable([...preceding, ...newestPage]);
  }
}
