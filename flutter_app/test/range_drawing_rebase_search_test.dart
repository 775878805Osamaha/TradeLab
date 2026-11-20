import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/range_bar_timeline.dart';
import 'package:tradelab_flutter/data/range_drawing_rebase_search.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

/// Read-only fixture that measures the actual source index/candle reads
/// performed by a Range drawing rebase, not wall-clock emulator guesses.
class _MeasuredList<T> extends ListBase<T> {
  _MeasuredList(this.source);
  final List<T> source;
  int reads = 0;

  @override
  int get length => source.length;

  @override
  set length(int value) =>
      throw UnsupportedError('Verified broker snapshots are read-only');

  @override
  T operator [](int index) {
    reads++;
    return source[index];
  }

  @override
  void operator []=(int index, T value) =>
      throw UnsupportedError('Verified broker snapshots are read-only');
}

/// The exact pre-optimization source-event + nearest-price linear search.
/// Keep this independent reference to protect every legacy tie-break rule.
int? _originalLinearRebase(
    RangeBarTimeline timeline, int sourceTick, double anchorPrice) {
  final through = timeline.visibleBarsThroughTick(sourceTick);
  if (through == 0) return null;
  var first = through - 1;
  while (first > 0 && timeline.endTickIndices[first - 1] == sourceTick) {
    first--;
  }
  if (timeline.endTickIndices[first] != sourceTick) return through - 1;
  var nearest = first;
  var distance = double.infinity;
  for (var index = first; index < through; index++) {
    final bar = timeline.bars[index];
    final delta = anchorPrice < bar.low ? bar.low - anchorPrice
        : anchorPrice > bar.high ? anchorPrice - bar.high : 0.0;
    if (delta < distance) {
      distance = delta;
      nearest = index;
    }
  }
  return nearest;
}

void main() {
  test('40k closing bars per real BID tick match original price tie breaks '
      'with logarithmic indexed reads in both directions', () {
    const count = 40000;
    const sourceTick = 1;
    final anchors = <double>[
      0, 100, 100.001, 100.5, 101, 101.5, 102,
      200, 500, 1000, 12345.75, 20000, 39999, 40100, 40100.5,
      50000, double.infinity, double.negativeInfinity, double.nan,
    ];
    for (final rising in [true, false]) {
      final initial = rising ? 100.0 : 40100.0;
      final jumped = rising ? 40100.0 : 100.0;
      final timeline = RangeBarTimeline.build([
        MarketTick(1000, initial),
        MarketTick(1001, jumped),
        MarketTick(1002, rising ? jumped + .2 : jumped - .2),
      ], 1);
      expect(timeline.closedBarCount, count);
      final through = timeline.visibleBarsThroughTick(sourceTick);
      expect(through, count);

      final tickIds = _MeasuredList<int>(timeline.endTickIndices);
      final bars = _MeasuredList<TradeCandle>(timeline.bars);
      for (final price in anchors) {
        tickIds.reads = 0;
        bars.reads = 0;
        final fast = RangeDrawingRebaseSearch.closestFromVerifiedEvent(
          endTickIndices: tickIds, bars: bars, through: through,
          sourceTick: sourceTick, anchorPrice: price,
        );
        final reference = _originalLinearRebase(timeline, sourceTick, price);
        expect(fast, reference,
            reason: 'Anchor price $price must select the same BID bar');
        expect(tickIds.reads, lessThanOrEqualTo(24),
            reason: 'The original source tick must be located by bisection');
        expect(bars.reads, lessThanOrEqualTo(24),
            reason: 'Price selection must not scan 40k Range bars');
        expect(timeline.rebaseOldBarIndex(
          oldEndTickIndices: const [sourceTick],
          oldIndex: 0, prependedTicks: 0, anchorPrice: price,
        ), reference,
            reason: 'The actual chart drawing rebase must use the fast path');
      }
      expect(timeline.endTickIndices[through - 1], sourceTick);
      expect(timeline.endTickIndices.last, 2,
          reason: 'The still-forming bar is from the later actual BID tick');
    }
  });

  test('first candle may carry earlier wicks; still agrees with linear choice',
      () {
    for (final rising in [true, false]) {
      final initial = rising ? 100.0 : 20000.0;
      final ticks = [
        MarketTick(100, initial),
        MarketTick(101, initial + (rising ? .8 : -.8)),
        MarketTick(102, initial + (rising ? .1 : -.1)),
        MarketTick(103, initial + (rising ? 20000 : -20000)),
        MarketTick(104, initial + (rising ? 20000.2 : -20000.2)),
      ];
      final timeline = RangeBarTimeline.build(ticks, 1);
      final through = timeline.visibleBarsThroughTick(3);
      expect(through, 20000);
      for (final candidate in <double>[
        initial - 1, initial, initial + .1, initial + .8,
        initial + 1, initial + 100, initial + 10000,
        initial + 19999, initial + 20000, initial + 20001,
        initial - 100, initial - 10000,
      ]) {
        expect(timeline.rebaseOldBarIndex(
          oldEndTickIndices: const [3],
          oldIndex: 0, prependedTicks: 0, anchorPrice: candidate,
        ), _originalLinearRebase(timeline, 3, candidate));
      }
    }
  });

  test('distinct BID events in the same millisecond cannot share one bar run',
      () {
    final timeline = RangeBarTimeline.build([
      MarketTick(100, 100),
      MarketTick(101, 100.2),
      MarketTick(101, 5000.2),
      MarketTick(101, 5000.4),
    ], 1);
    final through = timeline.visibleBarsThroughTick(2);
    expect(through, 4900);
    expect(timeline.endTickIndices[0], 2);
    expect(timeline.endTimestamps[0], 101);
    for (final price in [100.0, 100.2, 1000.0, 4900.0, 5000.2]) {
      final chosen = timeline.rebaseOldBarIndex(
        oldEndTickIndices: const [2], oldIndex: 0,
        prependedTicks: 0, anchorPrice: price);
      expect(chosen, _originalLinearRebase(timeline, 2, price));
      expect(timeline.endTickIndices[chosen!], 2);
    }
    expect(timeline.visibleBarsThroughTick(1), 0,
        reason: 'A same-ms prior BID event did not yet close any Range bars');
  });

  test('no exact source-event close falls back to last earlier confirmed bar',
      () {
    final timeline = RangeBarTimeline.build([
      MarketTick(100, 100),
      MarketTick(101, 102),
      MarketTick(102, 102.1),
      MarketTick(103, 102.2),
    ], 1);
    final through = timeline.visibleBarsThroughTick(2);
    expect(through, 2);
    expect(timeline.rebaseOldBarIndex(
      oldEndTickIndices: const [2], oldIndex: 0,
      prependedTicks: 0, anchorPrice: 9999,
    ), 1);
    expect(timeline.rebaseOldBarIndex(
      oldEndTickIndices: const [0], oldIndex: 0,
      prependedTicks: 0, anchorPrice: 100,
    ), isNull);
    expect(timeline.rebaseOldBarIndex(
      oldEndTickIndices: const [2], oldIndex: -1,
      prependedTicks: 0, anchorPrice: 102,
    ), isNull);
    expect(timeline.rebaseOldBarIndex(
      oldEndTickIndices: const [2], oldIndex: 0,
      prependedTicks: -1, anchorPrice: 102,
    ), isNull);
  });

  test('source BID event rebase after older prepend never borrows future bars',
      () {
    final old = RangeBarTimeline.build([
      MarketTick(100, 100),
      MarketTick(101, 101),
      MarketTick(102, 101.4),
      MarketTick(103, 102),
      MarketTick(104, 500),
    ], 1);
    final older = [
      MarketTick(90, 99),
      MarketTick(91, 98),
      MarketTick(92, 97),
    ];
    final now = RangeBarTimeline.build([
      ...older,
      MarketTick(100, 100),
      MarketTick(101, 101),
      MarketTick(102, 101.4),
      MarketTick(103, 102),
      MarketTick(104, 500),
    ], 1);
    final oldIndex = 1;
    final cutoffTick = older.length + old.endTickIndices[oldIndex];
    final selected = now.rebaseOldBarIndex(
      oldEndTickIndices: old.endTickIndices,
      oldIndex: oldIndex,
      prependedTicks: older.length,
      anchorPrice: old.bars[oldIndex].close,
    );
    expect(selected, isNotNull);
    expect(now.endTickIndices[selected!], lessThanOrEqualTo(cutoffTick),
      reason: 'The drawing cannot use later unseen BID price events');
    expect(selected, _originalLinearRebase(
      now, cutoffTick, old.bars[oldIndex].close));
    expect(now.visibleClosedBarsThroughTick(cutoffTick),
        lessThan(now.closedBarCount));
  });
}
