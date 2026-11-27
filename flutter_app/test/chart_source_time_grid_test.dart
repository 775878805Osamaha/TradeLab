import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_source_time_grid.dart';
import 'package:tradelab_flutter/chart/chart_symbol_settings.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';

void main() {
  test('grid and time labels follow SAME broker candle x through a pan', () {
    const initial = ChartViewport(barWidth: 10, scrollBars: 0);
    const candleCount = 200;
    const plotWidth = 320.0;
    final first = ChartSourceTimeGrid.visible(
      viewport: initial, plotWidth: plotWidth, candleCount: candleCount);
    expect(first.map((m) => m.index).toList(), [170, 180, 190]);
    expect(first.map((m) => m.x).toList(), [25, 125, 225]);

    final dragged = initial.pan(
        deltaX: 45, plotWidth: plotWidth, candleCount: candleCount);
    final next = ChartSourceTimeGrid.visible(
        viewport: dragged, plotWidth: plotWidth, candleCount: candleCount);
    expect(next.map((m) => m.index).toList(), [170, 180, 190]);
    for (var i = 0; i < first.length; i++) {
      final old = first[i];
      final moved = next[i];
      expect(moved.index, old.index);
      expect(moved.x - old.x, closeTo(45, 1e-10),
        reason: 'Time grid must move exactly with the candle, not stay '
            'fixed at width × 1/5 while date labels jump');
      expect(moved.x, dragged.chartX(
          index: moved.index, candleCount: candleCount,
          plotWidth: plotWidth));
    }
  });

  test('pinch anchor preserves the REAL timestamp mark under the finger', () {
    const original = ChartViewport(barWidth: 10, scrollBars: 20);
    const candleCount = 220;
    const width = 320.0;
    const anchored = 180;
    final x = original.chartX(index: anchored,
      candleCount: candleCount, plotWidth: width);
    final before = ChartSourceTimeGrid.visible(
      viewport: original, plotWidth: width, candleCount: candleCount);
    expect(before.any((m) => m.index == anchored && m.x == x), isTrue);

    final zoom = original.pinch(
      scale: 1.5, initialFocalX: x, currentFocalX: x,
      plotWidth: width, candleCount: candleCount);
    expect(zoom.barWidth, 15);
    final after = ChartSourceTimeGrid.visible(
      viewport: zoom, plotWidth: width, candleCount: candleCount);
    final same = after.singleWhere((mark) => mark.index == anchored);
    expect(same.x, closeTo(x, 1e-8),
      reason: 'The user-touched historical candle must not jump on pinch');
  });

  test('3px zoom grid is bounded, chronological and on actual candle centers',
      () {
    const viewport = ChartViewport(barWidth: ChartViewport.minBarWidth,
        scrollBars: 65000, rightMarginBars: 3);
    const count = 120000;
    const width = 329.0;
    final marks = ChartSourceTimeGrid.visible(
        viewport: viewport, plotWidth: width, candleCount: count);
    expect(marks.length, lessThanOrEqualTo(ChartSourceTimeGrid.maxVisibleMarks));
    expect(marks.length, greaterThanOrEqualTo(1));
    expect(ChartSourceTimeGrid.niceBarStep(28), 50);
    for (var i = 0; i < marks.length; i++) {
      final mark = marks[i];
      expect(mark.index, inInclusiveRange(0, count - 1));
      expect(mark.x, inInclusiveRange(0.0, width));
      expect(mark.x, closeTo(viewport.chartX(index: mark.index,
          candleCount: count, plotWidth: width), 1e-8));
      if (i > 0) {
        expect(mark.index, greaterThan(marks[i - 1].index));
        expect(mark.x - marks[i - 1].x,
          greaterThanOrEqualTo(ChartSourceTimeGrid.minTickSpacingPx),
          reason: 'At 3px candles the time ruler must not crowd the plot');
      }
    }
  });

  test('future Replay whitespace never has an invented source timestamp', () {
    const visibleReplay = 4;
    const viewport = ChartViewport(
        barWidth: 10, scrollBars: -18, rightMarginBars: 2);
    final marks = ChartSourceTimeGrid.visible(viewport: viewport,
        plotWidth: 320, candleCount: visibleReplay);
    for (final mark in marks) {
      expect(mark.index, lessThan(visibleReplay));
      expect(mark.index, greaterThanOrEqualTo(0));
      expect(mark.x, viewport.chartX(
        index: mark.index, candleCount: visibleReplay, plotWidth: 320));
    }
    expect(ChartSourceTimeGrid.visible(
        viewport: viewport, plotWidth: 320, candleCount: 0), isEmpty);
  });

  test('irregular Range source ticks stay the only time labels', () {
    // A Friday-to-Sunday gap is authentic when cTrader returns no BID.
    // The layout uses ONLY indexes into this real timestamp list.
    const timeMs = <int>[
      1795190400000, 1795190400001, 1795190400002,
      1795456800000, 1795456800001, 1795456800002,
    ];
    const viewport = ChartViewport(barWidth: 60, scrollBars: 1);
    final marks = ChartSourceTimeGrid.visible(
      viewport: viewport, plotWidth: 320, candleCount: timeMs.length);
    expect(marks, isNotEmpty);
    for (final m in marks) {
      expect(timeMs[m.index], isIn(timeMs));
      expect(m.index.isEven, isTrue,
        reason: '60px candles use a two-source-bar visual tick step');
    }
  });

  test('unusable Android plot geometry yields no fake grid coordinates', () {
    for (final invalid in <double>[
      double.nan, double.infinity, double.negativeInfinity, 0, -1
    ]) {
      expect(ChartSourceTimeGrid.visible(
        viewport: const ChartViewport(), plotWidth: invalid,
        candleCount: 100), isEmpty);
      expect(ChartSourceTimeGrid.visible(
        viewport: ChartViewport(barWidth: invalid),
        plotWidth: 320, candleCount: 100), isEmpty);
      // Zero scrollBars is a VALID live chart position. Only nonfinite
      // scroll offsets invalidate a source-time grid; negative finite
      // offsets deliberately represent authentic right-side whitespace.
      if (!invalid.isFinite) {
        expect(ChartSourceTimeGrid.visible(
          viewport: ChartViewport(scrollBars: invalid),
          plotWidth: 320, candleCount: 100), isEmpty);
      }
    }
    expect(ChartSourceTimeGrid.visible(
      viewport: const ChartViewport(scrollBars: 0),
      plotWidth: 320, candleCount: 100), isNotEmpty);
    expect(ChartSourceTimeGrid.niceBarStep(1), 1);
    expect(ChartSourceTimeGrid.niceBarStep(2), 2);
    expect(ChartSourceTimeGrid.niceBarStep(3), 5);
    expect(ChartSourceTimeGrid.niceBarStep(10), 10);
    expect(ChartSourceTimeGrid.niceBarStep(11), 20);
    expect(ChartSourceTimeGrid.niceBarStep(82), 100);
  });
  test('first visible intraday mark never turns into weekday on pan', () {
    final times = List<int>.generate(200, (i) =>
        DateTime.utc(2026, 11, 23, 9)
          .add(Duration(minutes: i)).millisecondsSinceEpoch);
    for (final offset in [0.0, 3.5, 5.0, 13.0, 20.0]) {
      const width = 320.0;
      final view = ChartViewport(barWidth: 10, scrollBars: offset);
      final marks = ChartSourceTimeGrid.visible(
          viewport: view, plotWidth: width, candleCount: times.length);
      expect(marks, isNotEmpty);
      for (final mark in marks) {
        expect(ChartSourceTimeGrid.beginsDisplayedDay(
          sourceIndex: mark.index, barWidth: view.barWidth,
          timestampsUtcMs: times, zone: ChartTimeZone.utc,
        ), isFalse, reason: 'First visible tick is not necessarily midnight');
      }
    }
  });

  test('UTC and New York date markers use the same verified grid phase', () {
    final aroundUtcMidnight = List<int>.generate(60, (i) =>
        DateTime.utc(2026, 11, 23, 23, 40)
          .add(Duration(minutes: i)).millisecondsSinceEpoch);
    bool isDay(List<int> source, int at, ChartTimeZone zone) =>
        ChartSourceTimeGrid.beginsDisplayedDay(
          sourceIndex: at, barWidth: 10,
          timestampsUtcMs: source, zone: zone);
    expect(ChartSourceTimeGrid.stepForBarWidth(10), 10);
    expect(isDay(aroundUtcMidnight, 10, ChartTimeZone.utc), isFalse);
    expect(isDay(aroundUtcMidnight, 20, ChartTimeZone.utc), isTrue);
    expect(isDay(aroundUtcMidnight, 30, ChartTimeZone.utc), isFalse);
    expect(isDay(aroundUtcMidnight, 20, ChartTimeZone.newYork), isFalse);
    expect(isDay(aroundUtcMidnight, 0, ChartTimeZone.utc), isTrue);
    final nyMidnight = List<int>.generate(60, (i) =>
        DateTime.utc(2026, 11, 24, 4, 40)
          .add(Duration(minutes: i)).millisecondsSinceEpoch);
    expect(isDay(nyMidnight, 20, ChartTimeZone.utc), isFalse);
    expect(isDay(nyMidnight, 20, ChartTimeZone.newYork), isTrue);
    expect(isDay(nyMidnight, 30, ChartTimeZone.newYork), isFalse);
    expect(nyMidnight[20], DateTime.utc(2026, 11, 24, 5)
      .millisecondsSinceEpoch, reason: 'Do not rewrite broker UTC time');
  });

  test('Range weekend transition never creates market-closed candles', () {
    final ms = <int>[
      DateTime.utc(2026, 11, 20, 21).millisecondsSinceEpoch,
      DateTime.utc(2026, 11, 20, 21, 0, 0, 1).millisecondsSinceEpoch,
      DateTime.utc(2026, 11, 23, 1).millisecondsSinceEpoch,
      DateTime.utc(2026, 11, 23, 1, 0, 0, 1).millisecondsSinceEpoch,
      DateTime.utc(2026, 11, 23, 1, 1).millisecondsSinceEpoch,
    ];
    expect(ChartSourceTimeGrid.stepForBarWidth(60), 2);
    bool isDay(int i) => ChartSourceTimeGrid.beginsDisplayedDay(
      sourceIndex: i, barWidth: 60, timestampsUtcMs: ms,
      zone: ChartTimeZone.utc);
    expect(isDay(2), isTrue);
    expect(isDay(4), isFalse);
    expect(isDay(5), isFalse, reason: 'No future Replay source index');
  });

  test('invalid source/time geometry never manufactures day labels', () {
    final times = [
      DateTime.utc(2026, 11, 23).millisecondsSinceEpoch,
      DateTime.utc(2026, 11, 24).millisecondsSinceEpoch,
    ];
    for (final invalid in [0.0, -10.0, double.nan, double.infinity]) {
      expect(ChartSourceTimeGrid.beginsDisplayedDay(
        sourceIndex: 1, barWidth: invalid,
        timestampsUtcMs: times, zone: ChartTimeZone.utc), isFalse);
    }
    for (final i in [-1, 2]) {
      expect(ChartSourceTimeGrid.beginsDisplayedDay(
        sourceIndex: i, barWidth: 10,
        timestampsUtcMs: times, zone: ChartTimeZone.utc), isFalse);
    }
    expect(ChartSourceTimeGrid.beginsDisplayedDay(
      sourceIndex: 1, barWidth: 60,
      timestampsUtcMs: [times[0], 0],
      zone: ChartTimeZone.utc), isFalse);
  });

}
