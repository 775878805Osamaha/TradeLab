import 'package:flutter/foundation.dart' show compute, kIsWeb;

import 'market_api.dart';
import 'market_candle_store.dart';
import 'tradelab_data.dart';

/// A coherent snapshot of broker-verified bars and the two arrays chart
/// painters read. Never publish OHLC, candle and timestamp arrays from
/// different source history revisions.
class VerifiedMarketHistorySnapshot {
  const VerifiedMarketHistorySnapshot(
    this.bars,
    this.candles,
    this.timestamps,
  );

  final List<MarketBar> bars;
  final List<TradeCandle> candles;
  final List<int> timestamps;

  static const minOffloadBars = 5000;

  static bool shouldOffload(int barCount) =>
      !kIsWeb && barCount >= minOffloadBars;

  static VerifiedMarketHistorySnapshot fromVerified(
      List<MarketBar> bars) {
    // MarketCandleStore.read() and the broker request already strictly
    // validated all source timestamps and OHLC. Mapping must not sort,
    // synthesize missing minutes, deduplicate or transform prices.
    final candles = List<TradeCandle>.generate(
      bars.length, (index) => bars[index].candle, growable: false);
    final timestamps = List<int>.generate(
      bars.length, (index) => bars[index].timestamp, growable: false);
    return VerifiedMarketHistorySnapshot(bars, candles, timestamps);
  }

  static Future<VerifiedMarketHistorySnapshot> fromVerifiedAsync(
      List<MarketBar> bars) async {
    if (!shouldOffload(bars.length)) return fromVerified(bars);
    return compute<List<MarketBar>, VerifiedMarketHistorySnapshot>(
      _snapshotWorker, bars,
      debugLabel: 'tradelab-initial-ohlc-axis-snapshot');
  }

  /// The existing source-overlap policy remains authoritative: identical
  /// historical timestamps preserve one bar; conflicting broker OHLC throws.
  /// Prepare the merge AND its aligned canvas arrays on a background worker
  /// for a large cached cTrader history instead of blocking Android touch.
  static VerifiedMarketHistorySnapshot mergeVerified({
    required List<MarketBar> cached,
    required List<MarketBar> fetched,
  }) => fromVerified(MarketCandleStore.mergeVerified(cached, fetched));

  static Future<VerifiedMarketHistorySnapshot> mergeVerifiedAsync({
    required List<MarketBar> cached,
    required List<MarketBar> fetched,
  }) async {
    if (!shouldOffload(cached.length + fetched.length)) {
      return mergeVerified(cached: cached, fetched: fetched);
    }
    return compute<_VerifiedMarketMergeInput, VerifiedMarketHistorySnapshot>(
      _mergeSnapshotWorker,
      (cached: cached, fetched: fetched),
      debugLabel: 'tradelab-verified-ohlc-merge-and-axis');
  }
}

typedef _VerifiedMarketMergeInput = ({
  List<MarketBar> cached,
  List<MarketBar> fetched,
});

VerifiedMarketHistorySnapshot _snapshotWorker(List<MarketBar> bars) =>
    VerifiedMarketHistorySnapshot.fromVerified(bars);

VerifiedMarketHistorySnapshot _mergeSnapshotWorker(
    _VerifiedMarketMergeInput input) =>
    VerifiedMarketHistorySnapshot.mergeVerified(
      cached: input.cached, fetched: input.fetched);
