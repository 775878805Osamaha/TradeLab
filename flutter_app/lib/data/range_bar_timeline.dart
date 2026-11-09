import 'package:flutter/foundation.dart';

import 'market_api.dart';
import 'range_bar_builder.dart';
import 'tradelab_data.dart';

/// Maps Range bars back to the exact chronological BID tick that produced
/// them. Chart Replay can retain its last revealed *event* when older ticks
/// are prepended, even though all Range bar indices are rebuilt.
class RangeBarTimeline {
  const RangeBarTimeline._(this.bars, this.endTickIndices);

  final List<TradeCandle> bars;
  final List<int> endTickIndices;

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

  static RangeBarTimeline _buildRangeTimelineWorker(
      (List<MarketTick>, double) request) =>
      build(request.$1, request.$2);

  static RangeBarTimeline build(List<MarketTick> ticks, double priceDistance) {
    final builder = RangeBarBuilder(priceDistance);
    final endTickIndices = <int>[];
    for (var index = 0; index < ticks.length; index++) {
      final closedBefore = builder.closedCount;
      builder.appendBidTick(ticks[index].bid);
      for (var n = closedBefore; n < builder.closedCount; n++) {
        endTickIndices.add(index);
      }
    }
    final bars = builder.snapshot();
    // RangeBarBuilder always has one forming bar after the first BID tick.
    if (bars.length > endTickIndices.length && ticks.isNotEmpty) {
      endTickIndices.add(ticks.length - 1);
    }
    if (bars.length != endTickIndices.length) {
      throw StateError('Range bar/tick timeline mismatch');
    }
    return RangeBarTimeline._(bars, endTickIndices);
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
