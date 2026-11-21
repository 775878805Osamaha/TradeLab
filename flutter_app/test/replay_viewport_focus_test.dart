import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';

void main() {
  for (final plotWidth in <double>[260, 320, 390]) {
    test('Replay date/oldest/random selection reveals real candle at ${plotWidth}dp',
        () {
      const original = ChartViewport(
        barWidth: 12, scrollBars: 0, rightMarginBars: 1.5);
      const count = 500;
      for (final index in <int>[0, 1, 17, 250, 498]) {
        final focused = original.revealHistoricalBar(
          index: index, candleCount: count, plotWidth: plotWidth);
        final x = focused.chartX(
          index: index, candleCount: count, plotWidth: plotWidth);
        expect(x, greaterThanOrEqualTo(0),
            reason: 'Date-picked historical bar must not remain offscreen');
        expect(x, lessThanOrEqualTo(plotWidth));
        expect(focused.indexAt(
          x: x, plotWidth: plotWidth, candleCount: count), index,
            reason: 'The blue line must stay anchored to its original bar');
        expect(focused.barWidth, original.barWidth,
            reason: 'Navigating to a date must not reset chart zoom');
        expect(focused.rightMarginBars, original.rightMarginBars);
      }
    });
  }

  for (final width in <double>[260, 320, 390]) {
    test('Replay older candle stays at same x during autoplay and rewind '
        'at ${width}dp', () {
      const sourceIndex = 70;
      const oldCount = 100;
      const start = ChartViewport(
        barWidth: 12, scrollBars: 20, rightMarginBars: 1.5);
      final originalX = start.chartX(
        index: sourceIndex, candleCount: oldCount, plotWidth: width);
      expect(originalX, inInclusiveRange(0.0, width));
      final advance = start.afterReplayVisibleCountChange(
        previousVisibleCount: oldCount,
        nextVisibleCount: oldCount + 1,
        plotWidth: width,
      );
      expect(advance.scrollBars, 21);
      expect(advance.barWidth, start.barWidth);
      expect(advance.rightMarginBars, start.rightMarginBars);
      expect(advance.chartX(index: sourceIndex,
          candleCount: oldCount + 1, plotWidth: width),
          closeTo(originalX, .00000001),
          reason: 'A newly revealed Replay candle cannot drag a '
              'historical drawing/price candle one column to the left');

      final rewind = advance.afterReplayVisibleCountChange(
        previousVisibleCount: oldCount + 1,
        nextVisibleCount: oldCount,
        plotWidth: width,
      );
      expect(rewind, start);
      expect(rewind.chartX(index: sourceIndex,
          candleCount: oldCount, plotWidth: width),
          closeTo(originalX, .00000001));
    });
  }

  test('Replay live edge follows newest revealed real candle', () {
    const v = ChartViewport(
        barWidth: 10, scrollBars: 0, rightMarginBars: 3);
    final forward = v.afterReplayVisibleCountChange(
      previousVisibleCount: 100, nextVisibleCount: 101,
      plotWidth: 320,
    );
    expect(identical(forward, v), isTrue);
    expect(forward.chartX(index: 100, candleCount: 101, plotWidth: 320),
        v.chartX(index: 99, candleCount: 100, plotWidth: 320),
        reason: 'At the live edge the next bar appears in the same '
            'newest-candle x position');
    final backward = v.afterReplayVisibleCountChange(
      previousVisibleCount: 100, nextVisibleCount: 99,
      plotWidth: 320,
    );
    expect(identical(backward, v), isTrue);
  });

  test('Replay explicit right whitespace stays anchored on new closes', () {
    const v = ChartViewport(
        barWidth: 10, scrollBars: -5, rightMarginBars: 1);
    final x = v.chartX(
      index: 99, candleCount: 100, plotWidth: 320);
    final forward = v.afterReplayVisibleCountChange(
      previousVisibleCount: 100, nextVisibleCount: 102, plotWidth: 320);
    expect(forward.scrollBars, -3);
    expect(forward.chartX(
        index: 99, candleCount: 102, plotWidth: 320), closeTo(x, 1e-9));
    final back = forward.afterReplayVisibleCountChange(
      previousVisibleCount: 102, nextVisibleCount: 100, plotWidth: 320);
    expect(back.scrollBars, -5);
    expect(back.chartX(
        index: 99, candleCount: 100, plotWidth: 320), closeTo(x, 1e-9));
  });

  test('Replay rewind to before observed bar reanchors on last real candle',
      () {
    const v = ChartViewport(
        barWidth: 10, scrollBars: 5, rightMarginBars: 2);
    final newView = v.afterReplayVisibleCountChange(
      previousVisibleCount: 100, nextVisibleCount: 20, plotWidth: 320);
    expect(newView.scrollBars, 0,
        reason: 'Historical candle at index 94 was removed by the rewind');
    expect(newView.rightMarginBars, 2);
    expect(newView.barWidth, 10);
    expect(newView.indexAt(x: 315,
        plotWidth: 320, candleCount: 20), isNull,
        reason: 'Blank Replay future space is not a hidden source bar');

    const oldest = ChartViewport(barWidth: 10, scrollBars: 99);
    final advance = oldest.afterReplayVisibleCountChange(
      previousVisibleCount: 100, nextVisibleCount: 101, plotWidth: 320);
    expect(advance.scrollBars, 100,
        reason: 'Oldest source candle remains anchored after a new close');
    expect(advance.chartX(index: 0, candleCount: 101, plotWidth: 320),
        oldest.chartX(index: 0, candleCount: 100, plotWidth: 320));

    expect(identical(v.afterReplayVisibleCountChange(
      previousVisibleCount: 100, nextVisibleCount: 101,
      plotWidth: double.nan,
    ), v), isTrue);
    expect(identical(v.afterReplayVisibleCountChange(
      previousVisibleCount: 100, nextVisibleCount: 0,
      plotWidth: 320,
    ), v), isTrue);
  });

  test('Invalid history never causes a synthetic Replay selection', () {
    const current = ChartViewport(barWidth: 16, scrollBars: 7);
    expect(current.revealHistoricalBar(
      index: -1, candleCount: 20, plotWidth: 320), current);
    expect(current.revealHistoricalBar(
      index: 20, candleCount: 20, plotWidth: 320), current);
    expect(current.revealHistoricalBar(
      index: 0, candleCount: 0, plotWidth: 320), current);
    expect(current.revealHistoricalBar(
      index: 0, candleCount: 20, plotWidth: double.nan), current);
  });
}
