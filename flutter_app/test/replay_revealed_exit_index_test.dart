import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';
import 'package:tradelab_flutter/replay/replay_revealed_exit_index.dart';

class _ProtectedRevealedCandles extends ListBase<TradeCandle> {
  _ProtectedRevealedCandles(this.bars, {required this.allowedThrough});

  final List<TradeCandle> bars;
  int allowedThrough;
  int reads = 0;

  @override
  int get length => bars.length;

  @override
  set length(int value) => throw UnsupportedError('Verified candles immutable');

  @override
  TradeCandle operator [](int index) {
    if (index >= allowedThrough) {
      throw StateError('Future Replay price was accessed');
    }
    reads++;
    return bars[index];
  }

  @override
  void operator []=(int index, TradeCandle value) =>
      throw UnsupportedError('Verified candles immutable');
}

class _HugeUnmaterializedCandles extends ListBase<TradeCandle> {
  @override
  int get length => ReplayRevealedExitIndex.maxSourceCandles + 1;

  @override
  set length(int value) => throw UnsupportedError('Immutable source');

  @override
  TradeCandle operator [](int index) =>
      throw StateError('Must reject source before reading its future prices');

  @override
  void operator []=(int index, TradeCandle value) =>
      throw UnsupportedError('Immutable source');
}

void main() {
  const flat = TradeCandle(100, 101, 99, 100);

  test('build and seek read only the REVEALED prefix, never future OHLC', () {
    const count = 100000;
    final source = List<TradeCandle>.filled(
        count, flat, growable: false).toList();
    source[2999] = const TradeCandle(100, 106, 95, 100);
    source[3050] = const TradeCandle(100, 108, 97, 100);
    final protected = _ProtectedRevealedCandles(
        source, allowedThrough: 3000);
    final index = ReplayRevealedExitIndex(protected);
    expect(protected.reads, 0,
        reason: 'Creating an index must not inspect any future candle');
    index.indexThrough(3000);
    expect(protected.reads, 3000);
    expect(index.indexedThrough, 3000);
    expect(index.firstCrossing(
        fromInclusive: 0, throughExclusive: 3000,
        lowAtMost: 96, highAtLeast: 105), 2999);
    expect(protected.reads, 3000,
        reason: 'Queries should consult the revealed index, not candle list');
    expect(() => index.firstCrossing(
        fromInclusive: 0, throughExclusive: 3001, lowAtMost: 96),
        throwsRangeError,
        reason: 'A source price after Replay cutoff may not be queried');
    protected.allowedThrough = 4000;
    index.indexThrough(4000);
    expect(protected.reads, 4000);
    expect(index.firstCrossing(
        fromInclusive: 3000, throughExclusive: 4000,
        lowAtMost: 96), isNull);
    expect(index.firstCrossing(
        fromInclusive: 3000, throughExclusive: 4000,
        highAtLeast: 107), 3050);
    expect(() => index.indexThrough(3500), throwsRangeError,
        reason: 'Rewinding discards this index, never reuses future extrema');
  });

  test('mixed crossing bounds return earliest source bar, not later target',
      () {
    const candles = <TradeCandle>[
      TradeCandle(100, 101, 99, 100),
      TradeCandle(100, 102, 98, 100),
      TradeCandle(100, 110, 96, 100),
      TradeCandle(100, 104, 88, 100),
      TradeCandle(100, 120, 70, 100),
    ];
    final index = ReplayRevealedExitIndex(candles)..indexThrough(4);
    expect(index.firstCrossing(
        fromInclusive: 1, throughExclusive: 4,
        lowAtMost: 90, highAtLeast: 105), 2);
    expect(index.firstCrossing(
        fromInclusive: 1, throughExclusive: 4,
        lowAtMost: 90), 3);
    expect(index.firstCrossing(
        fromInclusive: 0, throughExclusive: 2,
        lowAtMost: 90, highAtLeast: 105), isNull);
    expect(index.firstCrossing(
        fromInclusive: 0, throughExclusive: 4), isNull);
    expect(() => index.firstCrossing(
        fromInclusive: -1, throughExclusive: 1,
        highAtLeast: 105), throwsRangeError);
    expect(() => index.firstCrossing(
        fromInclusive: 1, throughExclusive: 3,
        lowAtMost: double.nan), throwsArgumentError);
  });

  test('incremental index update uses only newly revealed chart closes', () {
    final bars = List<TradeCandle>.filled(6000, flat,
        growable: false).toList();
    bars[500] = const TradeCandle(100, 103, 90, 101);
    bars[2000] = const TradeCandle(100, 110, 90, 101);
    bars[4500] = const TradeCandle(100, 115, 95, 101);
    final protected = _ProtectedRevealedCandles(
        bars, allowedThrough: 1000);
    final index = ReplayRevealedExitIndex(protected);
    index.indexThrough(1000);
    expect(index.firstCrossing(
      fromInclusive: 0, throughExclusive: 1000,
      lowAtMost: 91), 500);
    protected.allowedThrough = 3000;
    index.indexThrough(3000);
    expect(protected.reads, 3000,
        reason: 'Revealed prefix is read once even after extension');
    expect(index.firstCrossing(
      fromInclusive: 1000, throughExclusive: 3000,
      highAtLeast: 109), 2000);
    protected.allowedThrough = 5000;
    index.indexThrough(5000);
    expect(protected.reads, 5000);
    expect(index.firstCrossing(
      fromInclusive: 3000, throughExclusive: 5000,
      highAtLeast: 114), 4500);
    expect(index.indexedThrough, 5000);
  });

  test('rejects source beyond bounded Range memory before any candle access',
      () {
    expect(() => ReplayRevealedExitIndex(_HugeUnmaterializedCandles()),
        throwsArgumentError);
  });
}
