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
  test('Replay confirmation keeps verified prefix visible by price ruler',
      () {
    for (final plotWidth in <double>[259, 329]) {
      for (final barWidth in <double>[3, 10, 60]) {
        const selected = 80000;
        final selecting = ChartViewport(
          barWidth: barWidth, scrollBars: -140,
          rightMarginBars: 4);
        final active = selecting.afterConfirmingReplayStart(
          revealedCount: selected + 1, plotWidth: plotWidth);
        expect(active.barWidth, barWidth,
          reason: 'Pinch zoom remains unchanged on Replay entry');
        expect(active.scrollBars, 0,
          reason: 'Do not inherit far-left selection-stage blank future');
        expect(active.rightMarginBars, lessThanOrEqualTo(4));
        final x = active.chartX(index: selected,
          candleCount: selected + 1, plotWidth: plotWidth);
        expect(x, inInclusiveRange(plotWidth * .79, plotWidth),
          reason: 'Last real revealed candle must be visible near ruler');
        expect(active.indexAt(x: x, plotWidth: plotWidth,
          candleCount: selected + 1), selected);
        // Playback must follow the NEXT real bar without showing future
        // source indices or bringing back the original white gap.
        final advanced = active.afterReplayVisibleCountChange(
          previousVisibleCount: selected + 1,
          nextVisibleCount: selected + 2,
          plotWidth: plotWidth);
        expect(advanced.scrollBars, 0);
        expect(advanced.chartX(index: selected + 1,
          candleCount: selected + 2, plotWidth: plotWidth), closeTo(x, 1e-8));
        expect(active.indexAt(x: plotWidth - 1,
          plotWidth: plotWidth, candleCount: selected + 1), isNull);
      }
    }
  });

  test('Replay confirmation preserves authored margin when it fits plot',
      () {
    const viewport = ChartViewport(
      barWidth: 10, scrollBars: 190, rightMarginBars: 4);
    final active = viewport.afterConfirmingReplayStart(
      revealedCount: 120, plotWidth: 329);
    expect(active.scrollBars, 0);
    expect(active.rightMarginBars, 4);
    expect(active.barWidth, 10);
    // Invalid layout/empty historical prefix cannot silently alter scroll.
    expect(viewport.afterConfirmingReplayStart(
      revealedCount: 0, plotWidth: 329), viewport);
    expect(viewport.afterConfirmingReplayStart(
      revealedCount: 120, plotWidth: double.nan), viewport);
  });

}
