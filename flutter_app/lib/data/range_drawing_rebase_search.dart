import 'tradelab_data.dart';

/// Selects an original-source BID Range bar after an older verified tick
/// window has changed the origin of every subsequent Range candle.
///
/// End-tick indices are chronological and every bar created by a single BID
/// event is in one contiguous, monotone-price run: one BID tick can move only
/// upward OR downward, not both. RangeBarBuilder closes exactly one distance
/// step per bar in that direction. The first bar may carry older wicks and the
/// trailing still-forming bar can be shorter, but their high boundaries rise
/// monotonically for an up tick, and their low boundaries fall monotonically
/// for a down tick.
///
/// These facts allow two binary searches rather than scanning potentially
/// 100,000 price-distance bars once per drawing anchor. This method must
/// receive only a RangeBarTimeline generated from verified BID ticks.
/// No source prices, bar endpoints or Replay boundaries are changed.
abstract final class RangeDrawingRebaseSearch {
  /// [through] is the exclusive event cutoff from
  /// RangeBarTimeline.visibleBarsThroughTick(sourceTick), never the number
  /// of available *future* source bars.
  ///
  /// Old semantics are preserved: if no reconstructed bar was closed by
  /// the exact original BID event, use the latest bar available through it.
  /// For equal-distance bars return the EARLIEST one. Nonfinite annotation
  /// prices also retain the original earliest-bar behavior.
  static int closestFromVerifiedEvent({
    required List<int> endTickIndices,
    required List<TradeCandle> bars,
    required int through,
    required int sourceTick,
    required double anchorPrice,
  }) {
    if (through < 1 || through > endTickIndices.length ||
        through > bars.length) {
      throw RangeError.range(
        through, 1,
        endTickIndices.length < bars.length
            ? endTickIndices.length : bars.length,
        'through',
      );
    }

    // Lower-bound: first bar whose event index is >= the genuine BID event.
    var lower = 0;
    var upper = through;
    while (lower < upper) {
      final mid = lower + (upper - lower) ~/ 2;
      if (endTickIndices[mid] < sourceTick) {
        lower = mid + 1;
      } else {
        upper = mid;
      }
    }
    final first = lower;
    if (first >= through || endTickIndices[first] != sourceTick) {
      return through - 1;
    }
    if (through - first == 1 || !anchorPrice.isFinite) return first;

    // An entire one-tick close run has a single direction. Rising Range
    // bars have monotonically increasing highs; falling bars have
    // monotonically decreasing lows. Find the first interval containing
    // the anchor or the earliest interval immediately past the anchor.
    // Adjacent bar price boundaries are shared, so this is precisely the
    // same nearest-price/tie-break choice as the former linear search.
    final rising = bars[first].close > bars[first].open;
    lower = first;
    upper = through;
    while (lower < upper) {
      final mid = lower + (upper - lower) ~/ 2;
      final candle = bars[mid];
      final isBeforeAnchor = rising
          ? candle.high < anchorPrice
          : candle.low > anchorPrice;
      if (isBeforeAnchor) {
        lower = mid + 1;
      } else {
        upper = mid;
      }
    }
    return lower == through ? through - 1 : lower;
  }
}
