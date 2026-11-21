import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';
import 'package:tradelab_flutter/replay/replay_start_resolver.dart';


class _CountingTimestamps extends ListBase<int> {
  _CountingTimestamps(this.data);
  final List<int> data;
  int reads = 0;

  @override
  int get length => data.length;

  @override
  set length(int value) =>
      throw UnsupportedError('Immutable broker timestamps');

  @override
  int operator [](int index) {
    reads++;
    return data[index];
  }

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('Immutable broker timestamps');
}

void main() {
  final bars = [100000, 160000, 220000, 280000, 340000];

  test('only broker-timestamped completed bars qualify for Replay', () {
    expect(ReplayStartResolver.hasVerifiedTimes(bars, 5), isTrue);
    expect(ReplayStartResolver.hasVerifiedTimes(bars, 6), isFalse);
    expect(ReplayStartResolver.hasVerifiedTimes([10, 9, 20], 3), isFalse);
    expect(ReplayStartResolver.hasVerifiedTimes([10, 10, 20], 3), isTrue);
    expect(ReplayStartResolver.hasVerifiedTimes([], 0), isFalse);
  });

  test('selection remains bar-anchored when zoom and pan change chart x', () {
    const viewport = ChartViewport(barWidth: 10, scrollBars: 0);
    final x = viewport.chartX(index: 2, candleCount: 5, plotWidth: 300);
    final index = ReplayStartResolver.atX(
      viewport: viewport, x: x, plotWidth: 300, candleCount: 5,
      completedCount: 5, fallbackIndex: 0);
    expect(index, 2);
    final zoomed = viewport.pinch(
      scale: 2, initialFocalX: x, currentFocalX: x,
      plotWidth: 300, candleCount: 5);
    expect(zoomed.chartX(index: index, candleCount: 5, plotWidth: 300),
        closeTo(x, .001));
    expect(ReplayStartResolver.timestampAt(bars, index, 5), 220000);
  });

  test('date in real market gap seeks previous verified bar only', () {
    expect(ReplayStartResolver.atOrBefore(bars, 5, 219999), 1);
    expect(ReplayStartResolver.atOrBefore(bars, 5, 220000), 2);
    expect(ReplayStartResolver.atOrBefore(bars, 5, 300000), 3);
    expect(ReplayStartResolver.atOrBefore(bars, 5, 0), -1);
    expect(ReplayStartResolver.atOrBefore(bars, 5, 999999), 3,
        reason: 'Last bar excluded: Replay must retain a future step');
  });

  test('200k Replay date searches validate once then use logarithmic reads',
      () {
    const first = 1700000000000;
    const count = 200000;
    const step = 60000;
    final raw = List<int>.generate(
      count, (i) => first + i * step, growable: false);
    final tracked = _CountingTimestamps(raw);
    final index = ReplayVerifiedTimeIndex();
    expect(index.hasVerifiedTimes(tracked, count), isTrue);
    expect(tracked.reads, count);
    tracked.reads = 0;

    for (var i = 0; i < 180; i++) {
      final wanted = 1000 + i * 1079;
      expect(index.atOrBefore(tracked, count, raw[wanted]), wanted);
      expect(index.timestampAt(tracked, wanted, count), raw[wanted]);
    }
    expect(tracked.reads, lessThan(5000),
      reason: 'Repeated date selections must be O(log 200k), not O(200k)');
    expect(index.atOrBefore(tracked, count, raw.last + step), count - 2,
      reason: 'Keep at least one future bar unrevealed');
    expect(index.atOrBefore(tracked, count, first - 1), -1);
    expect(tracked.reads, lessThan(5100));
  });

  test('Replay index revalidates changed snapshot and completed-count', () {
    final cache = ReplayVerifiedTimeIndex();
    final original = <int>[100, 100, 220, 280, 340];
    expect(cache.hasVerifiedTimes(original, 5), isTrue,
      reason: 'Genuine Range events may share a millisecond');
    expect(cache.atOrBefore(original, 5, 100), 1);
    expect(cache.atOrBefore(original, 5, 999), 3);
    expect(cache.hasVerifiedTimes(original, 6), isFalse);
    expect(cache.atOrBefore(original, 6, 280), -1);

    final invalid = <int>[100, 90, 220, 280, 340];
    expect(cache.hasVerifiedTimes(invalid, 5), isFalse);
    expect(() => cache.timestampAt(invalid, 2, 5), throwsStateError);
    final replaced = <int>[100, 110, 230, 300, 360];
    expect(cache.hasVerifiedTimes(replaced, 5), isTrue);
    expect(cache.atOrBefore(replaced, 5, 240), 2);
    expect(() => cache.timestampAt(replaced, 5, 5), throwsStateError);
    cache.clear();
    expect(cache.hasVerifiedTimes(replaced, 5), isTrue);
  });

  test('async Replay picker ignores changed source, account and timezone',
      () {
    final original = <int>[100, 200, 300];
    final guard = ReplayDateSelectionGuard(
      timestamps: original, completedCount: 3,
      loadRevision: 11, symbol: 'XAUUSD', timeframe: '5m',
      provider: 'ctrader', accountId: 'account-a', zoneKey: 'newYork',
    );
    bool allowed({
      List<int>? timestamps,
      int count = 3,
      int revision = 11,
      String symbol = 'XAUUSD',
      String timeframe = '5m',
      String provider = 'ctrader',
      String? accountId = 'account-a',
      String zoneKey = 'newYork',
      bool selecting = true,
    }) => guard.isCurrent(
      timestamps: timestamps ?? original,
      completedCount: count, loadRevision: revision,
      symbol: symbol, timeframe: timeframe,
      provider: provider, accountId: accountId,
      zoneKey: zoneKey, selectingStart: selecting,
    );
    expect(allowed(), isTrue);
    expect(allowed(timestamps: [100, 200, 300]), isFalse,
      reason: 'A new but identical-value archive is not the old session');
    expect(allowed(count: 2), isFalse);
    expect(allowed(revision: 12), isFalse);
    expect(allowed(symbol: 'EURUSD'), isFalse);
    expect(allowed(timeframe: '1h'), isFalse);
    expect(allowed(provider: 'binance'), isFalse);
    expect(allowed(accountId: 'account-b'), isFalse);
    expect(allowed(zoneKey: 'utc'), isFalse);
    expect(allowed(selecting: false), isFalse);
  });

  test('pixel selection never targets off-canvas future whitespace', () {
    const viewport = ChartViewport(barWidth: 12, scrollBars: -8);
    expect(ReplayStartResolver.atX(
      viewport: viewport, x: 299, plotWidth: 300, candleCount: 5,
      completedCount: 5, fallbackIndex: 1), 1);
    expect(ReplayStartResolver.atX(
      viewport: viewport, x: -100, plotWidth: 300, candleCount: 5,
      completedCount: 5, fallbackIndex: 1), 1);
  });
}
