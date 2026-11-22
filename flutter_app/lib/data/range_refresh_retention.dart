import 'market_api.dart';
import 'range_bar_timeline.dart';
import 'range_size_reuse.dart';

/// Keep an ALREADY verified cTrader BID/Range snapshot visible while the same
/// account/symbol/range-distance is refreshed. An unavailable broker should
/// not erase authentic candles that were already displayed on the phone.
///
/// This only preserves read-only chart history, never certifies it as a
/// newly downloaded page. A different account, symbol, distance, or Replay
/// session must invalidate the old source without displaying it even briefly.
class RangeRefreshRetention {
  const RangeRefreshRetention._();

  static bool canKeep({
    required String? connectedAccount,
    required String? snapshotAccount,
    required String connectedSymbol,
    required String? snapshotSymbol,
    required int rangePoints,
    required double? pointSize,
    required List<MarketTick> verifiedTicks,
    required RangeBarTimeline? timeline,
    required bool sourceReady,
    required bool replayActive,
  }) {
    if (!sourceReady || replayActive ||
        connectedAccount == null || connectedAccount.isEmpty ||
        connectedAccount != snapshotAccount ||
        connectedSymbol.isEmpty || connectedSymbol != snapshotSymbol ||
        pointSize == null ||
        !RangeSizeReuse.canRebuild(
          verifiedTicks: verifiedTicks,
          previousTimeline: timeline,
          pointSize: pointSize,
          nextRangePoints: rangePoints,
          sourceReady: true,
        )) {
      return false;
    }
    // A same-account width switch must NOT temporarily show the previous
    // 25-point aggregation under a new 1000-point label. All source events,
    // original price distance and bar/end-event indices must still agree.
    return timeline!.priceDistance == rangePoints * pointSize;
  }
}
