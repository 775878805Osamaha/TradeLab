import 'package:flutter/foundation.dart' show compute, kIsWeb;

import 'market_api.dart';
import 'market_history_budget.dart';
import 'ctrader_candle_stitcher.dart';
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
    MarketHistoryBudget.requireCapacity(bars.length);
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

/// An overlap-only closed-bar poll needs no new chart arrays. This is
/// distinct from an accepted append that must publish every array atomically.
class ClosedCandleRefreshResult {
  const ClosedCandleRefreshResult({
    required this.appended,
    required this.snapshot,
  });

  final int appended;
  final VerifiedMarketHistorySnapshot? snapshot;
}

class VerifiedClosedCandleRefresh {
  const VerifiedClosedCandleRefresh._();
  /// Source-validated cTrader refresh. The existing stitcher continues to
  /// reject revised historical OHLC and late broker backfills.
  static ClosedCandleRefreshResult appendVerified({
    required List<MarketBar> existing,
    required List<MarketBar> recent,
  }) {
    // The chart publishes only authenticated, verified historical archives.
    // Avoid validating 120k older bars on each closed-candle refresh.
    final combined =
        CTraderCandleStitcher.appendPreviouslyVerified(existing, recent);
    final appended = combined.length - existing.length;
    return ClosedCandleRefreshResult(
      appended: appended,
      snapshot: appended == 0
          ? null : VerifiedMarketHistorySnapshot.fromVerified(combined),
    );
  }

  static Future<ClosedCandleRefreshResult> appendVerifiedAsync({
    required List<MarketBar> existing,
    required List<MarketBar> recent,
  }) async {
    if (!VerifiedMarketHistorySnapshot.shouldOffload(
        existing.length + recent.length)) {
      return appendVerified(existing: existing, recent: recent);
    }
    // A no-new-close poll is the common case. Check the small fresh page
    // against the verified archive before transferring 120k+ bars into a
    // worker isolate. Keep the existing chart arrays and repaint untouched.
    if (CTraderCandleStitcher.countNewFromVerifiedHistory(
            existing, recent) == 0) {
      return const ClosedCandleRefreshResult(
          appended: 0, snapshot: null);
    }
    return compute<_VerifiedClosedAppendInput, ClosedCandleRefreshResult>(
      _appendClosedWorker,
      (existing: existing, recent: recent),
      debugLabel: 'tradelab-ctrader-closed-candle-refresh');
  }
}

typedef _VerifiedClosedAppendInput = ({
  List<MarketBar> existing,
  List<MarketBar> recent,
});

ClosedCandleRefreshResult _appendClosedWorker(
    _VerifiedClosedAppendInput input) =>
    VerifiedClosedCandleRefresh.appendVerified(
      existing: input.existing, recent: input.recent);

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
