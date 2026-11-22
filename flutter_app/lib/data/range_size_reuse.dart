import 'market_api.dart';
import 'range_bar_timeline.dart';

/// A user may change the width of Range bars without changing the original
/// cTrader account, symbol, UTC BID ticks or archived source coverage.
/// Before this policy, every 25→1000→25 size switch re-downloaded the same
/// authenticated broker windows while an already verified 1m-tick source
/// existed on the phone.
///
/// Reuse is permitted ONLY while the chart holds a consistent verified
/// source/timeline pair and there is no concurrent load, Replay or account
/// switch. The source remains unmodified, and rebuildAsync applies the same
/// bounded BID-to-Range math as initial live/history loading.
class RangeSizeReuse {
  const RangeSizeReuse._();

  static bool canRebuild({
    required List<MarketTick> verifiedTicks,
    required RangeBarTimeline? previousTimeline,
    required double pointSize,
    required int nextRangePoints,
    required bool sourceReady,
  }) {
    if (!sourceReady || verifiedTicks.isEmpty || previousTimeline == null ||
        !pointSize.isFinite || pointSize <= 0 || nextRangePoints <= 0 ||
        !(nextRangePoints * pointSize).isFinite ||
        nextRangePoints * pointSize <= 0 ||
        previousTimeline.bars.isEmpty ||
        previousTimeline.bars.length !=
            previousTimeline.endTickIndices.length ||
        previousTimeline.bars.length !=
            previousTimeline.endTimestamps.length ||
        previousTimeline.endTickIndices.last != verifiedTicks.length - 1 ||
        previousTimeline.endTimestamps.last != verifiedTicks.last.timestamp ||
        previousTimeline.bars.first.open != verifiedTicks.first.bid ||
        previousTimeline.bars.last.close != verifiedTicks.last.bid) {
      return false;
    }
    return true;
  }

  static Future<RangeBarTimeline> rebuild({
    required List<MarketTick> verifiedTicks,
    required RangeBarTimeline previousTimeline,
    required double pointSize,
    required int nextRangePoints,
  }) {
    if (!canRebuild(
      verifiedTicks: verifiedTicks,
      previousTimeline: previousTimeline,
      pointSize: pointSize,
      nextRangePoints: nextRangePoints,
      sourceReady: true,
    )) {
      throw StateError('Cannot reuse a mismatched verified BID archive');
    }
    return RangeBarTimeline.buildAsync(
        verifiedTicks, nextRangePoints * pointSize);
  }
}
