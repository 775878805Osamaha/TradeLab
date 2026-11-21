import 'dart:collection' show UnmodifiableListView;

import 'package:flutter/foundation.dart';

import 'market_api.dart';
import 'range_bar_builder.dart';
import 'range_drawing_rebase_search.dart';
import 'tradelab_data.dart';

/// One published historic BID prefix and its matching Range bar timeline.
/// Both are produced together: the UI never sees a new tick list paired with
/// a timeline calculated from a different Range origin.
class RangePrependBuildResult {
  const RangePrependBuildResult(this.ticks, this.timeline);

  final List<MarketTick> ticks;
  final RangeBarTimeline timeline;
}

/// The live BID suffix and its matching Range history must be committed as
/// one immutable snapshot. Never publish new source ticks with old timeline
/// indices, including when multiple real BID events share a millisecond.
class RangeLiveAppendBuildResult {
  const RangeLiveAppendBuildResult(this.ticks, this.timeline);

  final List<MarketTick> ticks;
  final RangeBarTimeline timeline;
}

/// Maps Range bars back to the exact chronological BID tick that produced
/// them. Chart Replay can retain its last revealed *event* when older ticks
/// are prepended, even though all Range bar indices are rebuilt.
class RangeBarTimeline {
  const RangeBarTimeline._(this.bars, this.endTickIndices, this.endTimestamps);

  // A six-day verified BID archive may contain up to a million source ticks,
  // but small Range sizes can create many more bars than ticks when prices
  // jump. Bound BOTH the source transfer and the rebuilt candle timeline
  // before it can exhaust low-memory Android devices.
  static const maxSourceTicks = 1000000;
  static const maxClosedBarCount = 250000;

  static void _checkBudget(int tickCount, int closedBarLimit) {
    if (closedBarLimit < 1 || closedBarLimit > maxClosedBarCount) {
      throw ArgumentError.value(
          closedBarLimit, 'closedBarLimit', 'Outside chart memory budget');
    }
    if (tickCount < 0 || tickCount > maxSourceTicks) {
      throw const MarketDataException(
          'تجاوز تاريخ BID حد الذاكرة الآمن؛ '
          'لن نحمّل بيانات إضافية إلى الشارت.');
    }
  }

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

  /// Range work is not proportional only to the number of BID events:
  /// a single authentic broker jump can close thousands of price-distance
  /// bars. Walk only a cheap prefix of source ticks and conservatively
  /// estimate possible bar crossings before choosing the UI isolate.
  ///
  /// The bound is a scheduling heuristic, not a price/bar calculation.
  /// Every candle and Replay event still comes from RangeBarBuilder.
  static bool shouldBuildInBackground(
      Iterable<MarketTick> ticks, double priceDistance) {
    if (kIsWeb) return false;
    var count = 0;
    double? previous;
    var approximateCrossings = 0.0;
    for (final tick in ticks) {
      count++;
      if (count >= 5000) return true;
      if (previous != null && priceDistance.isFinite && priceDistance > 0) {
        approximateCrossings += (tick.bid - previous).abs() / priceDistance;
        if (!approximateCrossings.isFinite ||
            approximateCrossings >= 4096) {
          return true;
        }
      }
      previous = tick.bid;
    }
    return false;
  }

  /// Decide whether incremental LIVE Range appending needs a background
  /// isolate. The first new BID event must be compared with the LAST
  /// authenticated old event: a suffix containing only one tick has no
  /// internal price jump for shouldBuildInBackground to measure. Without
  /// this anchor an otherwise tiny archive may synchronously allocate
  /// thousands of genuine Range bars on the chart's gesture isolate.
  ///
  /// Only one old tick enters this lazy iterable. We never rescan or copy
  /// the full verified historical archive just to make this decision.
  static bool shouldAppendInBackground({
    required int currentTickCount,
    required int currentBarCount,
    required MarketTick lastVerifiedTick,
    required List<MarketTick> verifiedSuffix,
    required double priceDistance,
  }) {
    if (kIsWeb || verifiedSuffix.isEmpty) return false;
    return currentTickCount > 5000 ||
        currentBarCount > 4096 ||
        shouldBuildInBackground(
          <MarketTick>[lastVerifiedTick].followedBy(verifiedSuffix),
          priceDistance,
        );
  }

  /// Small inexpensive pages build immediately. Large histories *or* sparse
  /// pages with a large authentic BID price jump are rebuilt off the UI
  /// isolate so touch, zoom and rendering can continue smoothly.
  static Future<RangeBarTimeline> buildAsync(
      List<MarketTick> ticks, double priceDistance, {
      int closedBarLimit = maxClosedBarCount,
  }) async {
    // Reject pathological source sizes BEFORE scheduling any isolate
    // transfer, sampling BID prices or duplicating giant source buffers.
    _checkBudget(ticks.length, closedBarLimit);
    if (!shouldBuildInBackground(ticks, priceDistance)) {
      return build(ticks, priceDistance, closedBarLimit: closedBarLimit);
    }
    return compute<(List<MarketTick>, double, int), RangeBarTimeline>(
      _buildRangeTimelineWorker,
      (ticks, priceDistance, closedBarLimit),
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
    int closedBarLimit = maxClosedBarCount,
  }) async {
    // Check total source size first, before touching a potentially oversized
    // page or concatenating into a second 1m+ element array.
    _checkBudget(currentTicks.length, closedBarLimit);
    if (olderTicks.length > maxSourceTicks - currentTicks.length) {
      throw const MarketDataException(
          'إضافة تيكات BID الأقدم تتجاوز حد الذاكرة الآمن.');
    }
    // A first verified startup page has no newer archive yet. It still
    // needs the same bounded one-pass merge/build operation. Reject only
    // an empty incoming older page or a shared millisecond boundary.
    if (olderTicks.isEmpty ||
        (currentTicks.isNotEmpty &&
            olderTicks.last.timestamp >= currentTicks.first.timestamp)) {
      throw ArgumentError('Older BID page must precede current history');
    }
    final request = (
      olderTicks, currentTicks, priceDistance, closedBarLimit);
    // Avoid a UI-isolate merge even for a sparse page with few source ticks
    // if their authentic price gaps imply thousands of Range bars.
    if (!shouldBuildInBackground(
        olderTicks.followedBy(currentTicks), priceDistance)) {
      return _prependAndBuildWorker(request);
    }
    return compute<(List<MarketTick>, List<MarketTick>, double, int),
        RangePrependBuildResult>(
      _prependAndBuildWorker, request,
      debugLabel: 'tradelab-range-prepend-and-build',
    );
  }

  /// Extend a VERIFIED Range timeline with only new authenticated broker
  /// events, including newer events on the very same last millisecond. The
  /// caller MUST first validate the entire inclusive cTrader page using
  /// RangeLiveBidDelta.verifiedSuffixAsync; that guard verifies event
  /// multiplicity and exact price/order of the previously loaded boundary.
  ///
  /// Existing closed bars preserve source indices exactly. Only the old
  /// unclosed forming bar is resumed by RangeBarBuilder; this never
  /// recomputes a different Range origin or borrows a future Replay tick.
  ///
  /// Use a background isolate when the old archive is large, since even
  /// appending one verified tick publishes a fresh immutable bar/tick list.
  static Future<RangeLiveAppendBuildResult> appendVerifiedSuffixAsync({
    required List<MarketTick> currentTicks,
    required RangeBarTimeline currentTimeline,
    required List<MarketTick> verifiedSuffix,
    required double priceDistance,
    int closedBarLimit = maxClosedBarCount,
  }) async {
    _checkBudget(currentTicks.length, closedBarLimit);
    if (verifiedSuffix.length > maxSourceTicks - currentTicks.length) {
      throw const MarketDataException(
          'تيكات BID الحية تجاوزت حد الذاكرة الآمن لشارت المدى.');
    }
    if (currentTicks.isEmpty || currentTimeline.bars.isEmpty ||
        currentTimeline.bars.length != currentTimeline.endTickIndices.length ||
        currentTimeline.bars.length != currentTimeline.endTimestamps.length ||
        currentTimeline.closedBarCount > closedBarLimit ||
        currentTimeline.endTickIndices.last != currentTicks.length - 1 ||
        currentTimeline.endTimestamps.last != currentTicks.last.timestamp ||
        // Exact source boundary checks are O(1), even with 1m BID events.
        // A stale archive can have the same count and last UTC timestamp
        // while carrying DIFFERENT BID prices or an older first close.
        // Never attach new candles to that unrelated Replay timeline.
        currentTimeline.bars.first.open != currentTicks.first.bid ||
        currentTimeline.bars.last.close != currentTicks.last.bid ||
        currentTimeline.endTickIndices.first < 0 ||
        currentTimeline.endTickIndices.first >= currentTicks.length ||
        currentTimeline.endTimestamps.first !=
            currentTicks[currentTimeline.endTickIndices.first].timestamp) {
      throw const MarketDataException(
          'تاريخ شموع Range لا يتطابق مع آخر مصدر BID موثق.');
    }
    if (verifiedSuffix.isEmpty) {
      return RangeLiveAppendBuildResult(currentTicks, currentTimeline);
    }
    final request = (currentTicks, currentTimeline, verifiedSuffix,
        priceDistance, closedBarLimit);
    if (shouldAppendInBackground(
      currentTickCount: currentTicks.length,
      currentBarCount: currentTimeline.bars.length,
      lastVerifiedTick: currentTicks.last,
      verifiedSuffix: verifiedSuffix,
      priceDistance: priceDistance,
    )) {
      return compute<
        (List<MarketTick>, RangeBarTimeline, List<MarketTick>, double, int),
        RangeLiveAppendBuildResult>(
        _appendVerifiedRangeWorker, request,
        debugLabel: 'tradelab-incremental-live-range',
      );
    }
    return _appendVerifiedRangeWorker(request);
  }

  static RangeLiveAppendBuildResult _appendVerifiedRangeWorker(
      (List<MarketTick>, RangeBarTimeline,
          List<MarketTick>, double, int) request) {
    final existingTicks = request.$1;
    final previousTimeline = request.$2;
    final suffix = request.$3;
    final priceDistance = request.$4;
    final closedBarLimit = request.$5;
    final priorClosed = previousTimeline.closedBarCount;
    final builder = RangeBarBuilder.resumeFromVerifiedForming(
        priceDistance, previousTimeline.bars.last);
    final newCloseIndices = <int>[];
    final newCloseTimes = <int>[];
    var lastTime = existingTicks.last.timestamp;
    for (var index = 0; index < suffix.length; index++) {
      final tick = suffix[index];
      if (tick.timestamp < lastTime || tick.timestamp < 0 ||
          !tick.bid.isFinite || tick.bid <= 0) {
        throw const MarketDataException(
            'سلسلة BID الحية غير مرتبة أو تحتوي سعرًا غير صالح.');
      }
      lastTime = tick.timestamp;
      final before = builder.closedCount;
      try {
        // Limit THIS tick before producing its candles, not after it may
        // have allocated up to 100k temporary bars on a low-memory phone.
        builder.appendBidTick(tick.bid,
            maxNewClosedBars: closedBarLimit - priorClosed - before);
      } on RangeBarBudgetExceeded {
        throw const MarketDataException(
            'المدى الحي تجاوز ميزانية شموع Range المغلقة للهاتف.');
      }
      for (var n = before; n < builder.closedCount; n++) {
        newCloseIndices.add(existingTicks.length + index);
        newCloseTimes.add(tick.timestamp);
      }
    }
    final suffixBars = builder.sealSnapshot();
    final appendedTicks =
        List<MarketTick>.unmodifiable(existingTicks.followedBy(suffix));
    final combinedBars = List<TradeCandle>.unmodifiable(
        previousTimeline.bars.take(priorClosed).followedBy(suffixBars));
    final endIndices = List<int>.unmodifiable(
        previousTimeline.endTickIndices.take(priorClosed)
        .followedBy(newCloseIndices)
        .followedBy([appendedTicks.length - 1]));
    final endTimes = List<int>.unmodifiable(
        previousTimeline.endTimestamps.take(priorClosed)
        .followedBy(newCloseTimes)
        .followedBy([appendedTicks.last.timestamp]));
    if (combinedBars.length != endIndices.length ||
        combinedBars.length != endTimes.length) {
      throw StateError('Incremental live Range timeline/source mismatch');
    }
    return RangeLiveAppendBuildResult(appendedTicks,
        RangeBarTimeline._(combinedBars, endIndices, endTimes));
  }

  static RangePrependBuildResult _prependAndBuildWorker(
      (List<MarketTick>, List<MarketTick>, double, int) request) {
    // One immutable copy is the final source archive; old UI snapshots remain
    // untouched if a stale load finishes or a provider reuses its page buffer.
    final combined = List<MarketTick>.unmodifiable(
        request.$1.followedBy(request.$2));
    final timeline = build(
        combined, request.$3, closedBarLimit: request.$4);
    return RangePrependBuildResult(combined, timeline);
  }

  static RangeBarTimeline _buildRangeTimelineWorker(
      (List<MarketTick>, double, int) request) =>
      build(request.$1, request.$2, closedBarLimit: request.$3);

  static RangeBarTimeline build(List<MarketTick> ticks, double priceDistance, {
      int closedBarLimit = maxClosedBarCount,
  }) {
    _checkBudget(ticks.length, closedBarLimit);
    final builder = RangeBarBuilder(priceDistance);
    final endTickIndices = <int>[];
    final endTimestamps = <int>[];
    var previousTimestamp = -1;
    for (var index = 0; index < ticks.length; index++) {
      final tick = ticks[index];
      // Equal-ms BID events retain their authentic source order. Backward
      // timestamps would make Range Replay depend on a future event, so
      // fail closed without sorting or inventing another timestamp.
      if (tick.timestamp < 0 || tick.timestamp < previousTimestamp) {
        throw const MarketDataException(
            'ترتيب أحداث BID غير صالح؛ أوقفنا بناء المدى لحماية Replay.');
      }
      previousTimestamp = tick.timestamp;
      final closedBefore = builder.closedCount;
      try {
        builder.appendBidTick(tick.bid,
            maxNewClosedBars: closedBarLimit - closedBefore);
      } on RangeBarBudgetExceeded {
        // Worker result is discarded, so no truncated Range history or
        // Replay future candle can be published.
        throw const MarketDataException(
            'عدد شموع المدى يتجاوز الحد الآمن للهاتف. '
            'اختر مدى أكبر أو قلّص الفترة التاريخية.');
      }
      for (var n = closedBefore; n < builder.closedCount; n++) {
        endTickIndices.add(index);
        endTimestamps.add(tick.timestamp);
      }
    }
    // Transfer the builder's final candle buffer exactly once. A second
    // full-history List copy here increased peak worker memory for dense
    // Range timelines; sealSnapshot forbids later mutation of the buffer.
    final bars = builder.sealSnapshot();
    // RangeBarBuilder always has one forming bar after the first BID tick.
    if (bars.length > endTickIndices.length && ticks.isNotEmpty) {
      endTickIndices.add(ticks.length - 1);
      endTimestamps.add(ticks.last.timestamp);
    }
    if (bars.length != endTickIndices.length ||
        bars.length != endTimestamps.length) {
      throw StateError('Range bar/tick timeline mismatch');
    }
    // sealSnapshot transfers ownership without copying its potentially
    // 250k-bar backing array, but that List is still externally mutable.
    // Publish O(1) read-only views over these three private, worker-owned
    // buffers. A caller must not be able to rewrite confirmed OHLC or the
    // exact BID event/time indices that Replay and drawing anchors trust.
    // Avoid List.unmodifiable here: that would allocate/copy three arrays
    // just to protect the historical snapshot.
    return RangeBarTimeline._(
      UnmodifiableListView<TradeCandle>(bars),
      UnmodifiableListView<int>(endTickIndices),
      UnmodifiableListView<int>(endTimestamps),
    );
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
    // First event boundary and nearest exact-source price bar are both
    // O(log N), even if one authentic BID jump closed 100k Range bars.
    // Preserve the previous earliest-tie and last-confirmed-bar behavior;
    // future Replay/source events remain outside [0, through).
    return RangeDrawingRebaseSearch.closestFromVerifiedEvent(
      endTickIndices: endTickIndices,
      bars: bars,
      through: through,
      sourceTick: sourceTick,
      anchorPrice: anchorPrice,
    );
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
