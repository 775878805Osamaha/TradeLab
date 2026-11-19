import 'package:flutter/foundation.dart';

import 'market_api.dart';
import 'range_bar_builder.dart';
import 'tradelab_data.dart';

/// One published historic BID prefix and its matching Range bar timeline.
/// Both are produced together: the UI never sees a new tick list paired with
/// a timeline calculated from a different Range origin.
class RangePrependBuildResult {
  const RangePrependBuildResult(this.ticks, this.timeline);

  final List<MarketTick> ticks;
  final RangeBarTimeline timeline;
}

/// Maps Range bars back to the exact chronological BID tick that produced
/// them. Chart Replay can retain its last revealed *event* when older ticks
/// are prepended, even though all Range bar indices are rebuilt.
class RangeBarTimeline {
  const RangeBarTimeline._(this.bars, this.endTickIndices, this.endTimestamps);

  final List<TradeCandle> bars;

  /// All source ticks form a final, still-open Range bar. This last
  /// snapshot is useful on the live chart, but MUST NOT be executed as
  /// a finished candle in Replay.
  int get closedBarCount => bars.isEmpty ? 0 : bars.length - 1;

  /// A Replay cutoff may correspond to the latest tick of a range snapshot.
  /// Exclude the last forming bar, even when its endTickIndex is already
  /// known, so Replay does not treat an incomplete bar as confirmed.
  int visibleClosedBarsThroughTick(int lastAllowedTickIndex) {
    final byEvent = visibleBarsThroughTick(lastAllowedTickIndex);
    return byEvent < closedBarCount ? byEvent : closedBarCount;
  }

  final List<int> endTickIndices;
  /// UTC milliseconds of the real BID tick that completed each Range bar.
  /// Several bars may close on one tick when the price jumps.
  final List<int> endTimestamps;

  /// Small pages build immediately. Large archived BID histories are rebuilt
  /// off the UI isolate so dragging, gestures and repainting remain responsive.
  static Future<RangeBarTimeline> buildAsync(
      List<MarketTick> ticks, double priceDistance) async {
    if (ticks.length < 5000 || kIsWeb) {
      return build(ticks, priceDistance);
    }
    return compute<(List<MarketTick>, double), RangeBarTimeline>(
      _buildRangeTimelineWorker,
      (ticks, priceDistance),
      debugLabel: 'tradelab-range-bars',
    );
  }

  /// Prepends a verified older BID page and rebuilds the Range origin in
  /// one operation. For large histories both the expensive list merge and
  /// candle generation run away from Flutter's gesture/raster UI isolate.
  ///
  /// The exclusive page boundary must already have been verified by the
  /// caller. Keep that guarantee here too: a duplicate millisecond at the
  /// boundary would silently reorder broker events and invalidate Replay.
  static Future<RangePrependBuildResult> prependAndBuildAsync({
    required List<MarketTick> olderTicks,
    required List<MarketTick> currentTicks,
    required double priceDistance,
  }) async {
    if (olderTicks.isEmpty || currentTicks.isEmpty ||
        olderTicks.last.timestamp >= currentTicks.first.timestamp) {
      throw ArgumentError('Older BID page must precede current history');
    }
    final request = (olderTicks, currentTicks, priceDistance);
    if (olderTicks.length + currentTicks.length < 5000 || kIsWeb) {
      return _prependAndBuildWorker(request);
    }
    return compute<(List<MarketTick>, List<MarketTick>, double),
        RangePrependBuildResult>(
      _prependAndBuildWorker, request,
      debugLabel: 'tradelab-range-prepend-and-build',
    );
  }

  static RangePrependBuildResult _prependAndBuildWorker(
      (List<MarketTick>, List<MarketTick>, double) request) {
    // One immutable copy is the final source archive; old UI snapshots remain
    // untouched if a stale load finishes or a provider reuses its page buffer.
    final combined = List<MarketTick>.unmodifiable(
        request.$1.followedBy(request.$2));
    final timeline = build(combined, request.$3);
    return RangePrependBuildResult(combined, timeline);
  }

  static RangeBarTimeline _buildRangeTimelineWorker(
      (List<MarketTick>, double) request) =>
      build(request.$1, request.$2);

  static RangeBarTimeline build(List<MarketTick> ticks, double priceDistance) {
    final builder = RangeBarBuilder(priceDistance);
    final endTickIndices = <int>[];
    final endTimestamps = <int>[];
    for (var index = 0; index < ticks.length; index++) {
      final closedBefore = builder.closedCount;
      builder.appendBidTick(ticks[index].bid);
      for (var n = closedBefore; n < builder.closedCount; n++) {
        endTickIndices.add(index);
        endTimestamps.add(ticks[index].timestamp);
      }
    }
    final bars = builder.snapshot();
    // RangeBarBuilder always has one forming bar after the first BID tick.
    if (bars.length > endTickIndices.length && ticks.isNotEmpty) {
      endTickIndices.add(ticks.length - 1);
      endTimestamps.add(ticks.last.timestamp);
    }
    if (bars.length != endTickIndices.length ||
        bars.length != endTimestamps.length) {
      throw StateError('Range bar/tick timeline mismatch');
    }
    return RangeBarTimeline._(bars, endTickIndices, endTimestamps);
  }

  /// Rebase a still-selecting Replay start after a verified older BID page
  /// changes the Range origin and all subsequent bar indices.
  ///
  /// The old selected bar's source BID tick is the authority; a new bar can
  /// be selected only if it was fully closed by that SAME event or earlier.
  /// Null means no confirmed reconstructed bar existed yet. Never silently
  /// borrow a bar that required a future BID tick.
  int? rebaseReplayStart({
    required List<int> oldEndTickIndices,
    required int oldSelectedIndex,
    required int prependedTicks,
  }) {
    if (oldSelectedIndex < 0 ||
        oldSelectedIndex >= oldEndTickIndices.length ||
        prependedTicks < 0) {
      return null;
    }
    final originalTick = oldEndTickIndices[oldSelectedIndex];
    final allowedTick = originalTick + prependedTicks;
    final closed = visibleClosedBarsThroughTick(allowedTick);
    if (closed < 1) return null;
    return closed - 1;
  }

  /// Remap an old drawing anchor by the *source BID tick* rather than by
  /// subtracting bar counts. Prepending ticks can change every Range close.
  /// Returns null when no bar existed yet at that market event, avoiding a
  /// misleading drawing anchored to later (possibly hidden Replay) ticks.
  int? rebaseOldBarIndex({
    required List<int> oldEndTickIndices,
    required int oldIndex,
    required int prependedTicks,
    required double anchorPrice,
  }) {
    if (oldIndex < 0 || oldIndex >= oldEndTickIndices.length ||
        prependedTicks < 0) return null;
    final sourceTick = oldEndTickIndices[oldIndex] + prependedTicks;
    final through = visibleBarsThroughTick(sourceTick);
    if (through == 0) return null;
    // Prefer bars closed by that exact BID event and closest to the drawing
    // price, which matters when one tick crosses several Range boundaries.
    var first = through - 1;
    while (first > 0 && endTickIndices[first - 1] == sourceTick) {
      first--;
    }
    if (endTickIndices[first] != sourceTick) return through - 1;
    var nearest = first;
    var distance = double.infinity;
    for (var i = first; i < through; i++) {
      final candle = bars[i];
      final delta = anchorPrice < candle.low ? candle.low - anchorPrice
          : anchorPrice > candle.high ? anchorPrice - candle.high : 0.0;
      if (delta < distance) {
        distance = delta;
        nearest = i;
      }
    }
    return nearest;
  }

  /// Returns a safe Replay cutoff that never includes a bar created from a
  /// tick after [lastAllowedTickIndex]. Uses upper-bound binary search.
  int visibleBarsThroughTick(int lastAllowedTickIndex) {
    var low = 0;
    var high = endTickIndices.length;
    while (low < high) {
      final middle = low + (high - low) ~/ 2;
      if (endTickIndices[middle] <= lastAllowedTickIndex) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }
}
