import 'market_api.dart';
import 'range_tick_store.dart';

/// Retains a broker-verified rolling window without downloading its already
/// covered history. The caller must obtain [newTicks] from an independently
/// verified, *exclusive* cTrader interval (cached.toMs + 1 .. newToMs).
class RangeTickRollforward {
  static const maxWindowTicks = 1000000;

  static List<MarketTick> merge({
    required VerifiedBidWindow cached,
    required List<MarketTick> newTicks,
    required int newFromMs,
    required int newToMs,
  }) {
    final suffixFrom = cached.toMs + 1;
    if (newToMs - newFromMs !=
            RangeTickStore.verifiedWindowDuration.inMilliseconds ||
        newFromMs < cached.fromMs ||
        newFromMs > suffixFrom ||
        newToMs < suffixFrom) {
      throw ArgumentError('Missing verified tick coverage for rolling window');
    }
    final retained = <MarketTick>[];
    for (final tick in cached.ticks) {
      if (tick.timestamp >= newFromMs && tick.timestamp <= cached.toMs) {
        retained.add(tick);
        if (retained.length > maxWindowTicks) {
          throw StateError('Rolling BID tick window exceeds safe limit');
        }
      }
    }
    var last = cached.toMs;
    for (final tick in newTicks) {
      if (tick.timestamp < suffixFrom ||
          tick.timestamp > newToMs ||
          tick.timestamp < last ||
          !tick.bid.isFinite || tick.bid <= 0) {
        throw ArgumentError('Invalid or overlapping cTrader BID suffix');
      }
      retained.add(tick);
      if (retained.length > maxWindowTicks) {
        throw StateError('Rolling BID tick window exceeds safe limit');
      }
      last = tick.timestamp;
    }
    return retained;
  }
}
