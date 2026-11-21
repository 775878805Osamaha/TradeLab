import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_position_viewport_visibility.dart';
import 'package:tradelab_flutter/chart/chart_short_position.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';

/// No market candles are constructed: all decisions use verified index/count
/// and the exact x geometry shared with the chart painter.
void main() {
  const candleCount = 120000;
  const buy = ChartShortPosition(
    startIndex: 119980, endIndex: 119990,
    entry: 4030, stop: 4020, target: 4055,
    direction: ChartPositionDirection.long,
  );
  const sell = ChartShortPosition(
    startIndex: 100, endIndex: 200,
    entry: 4030, stop: 4050, target: 4000,
  );

  for (final width in <double>[259, 329]) {
    test('visible recent Long and historical offscreen Short at ${width}dp',
        () {
      const latest = ChartViewport(
        barWidth: 10, scrollBars: 0, rightMarginBars: 4);
      expect(ChartPositionViewportVisibility.overlapsPlot(
          position: buy, viewport: latest,
          candleCount: candleCount, plotWidth: width), isTrue);
      expect(ChartPositionViewportVisibility.overlapsPlot(
          position: sell, viewport: latest,
          candleCount: candleCount, plotWidth: width), isFalse);

      const oldHistory = ChartViewport(
        barWidth: 10, scrollBars: 119800, rightMarginBars: 4);
      expect(ChartPositionViewportVisibility.overlapsPlot(
          position: sell, viewport: oldHistory,
          candleCount: candleCount, plotWidth: width), isTrue,
          reason: 'Old Short tags must return with its real box on pan');
      expect(ChartPositionViewportVisibility.overlapsPlot(
          position: buy, viewport: oldHistory,
          candleCount: candleCount, plotWidth: width), isFalse,
          reason: 'Recent Long price tags cannot haunt an ancient chart');
    });
  }

  test('partially clipped source positions remain visible at plot edges', () {
    const partiallyVisible = ChartShortPosition(
      startIndex: 119970, endIndex: 119985,
      entry: 4030, stop: 4040, target: 4020,
    );
    const latest = ChartViewport(
      barWidth: 10, scrollBars: 0, rightMarginBars: 4);
    expect(ChartPositionViewportVisibility.overlapsPlot(
        position: partiallyVisible, viewport: latest,
        candleCount: candleCount, plotWidth: 259), isTrue);
  });

  test('Replay future endpoint must never expose box or price-axis labels', () {
    const unseen = ChartShortPosition(
      startIndex: 119990, endIndex: 119995,
      entry: 4030, stop: 4025, target: 4050,
      direction: ChartPositionDirection.long,
    );
    const viewport = ChartViewport(
      barWidth: 10, scrollBars: 0, rightMarginBars: 4);
    expect(ChartPositionViewportVisibility.overlapsPlot(
        position: unseen, viewport: viewport,
        candleCount: 119992, plotWidth: 329), isFalse);
    expect(ChartPositionViewportVisibility.overlapsPlot(
        position: unseen, viewport: viewport,
        candleCount: 119996, plotWidth: 329), isTrue);
  });

  test('intentional future whitespace does not pin ghost price tags', () {
    const whiteSpace = ChartViewport(
      barWidth: 10, scrollBars: -100, rightMarginBars: 4);
    expect(ChartPositionViewportVisibility.overlapsPlot(
        position: buy, viewport: whiteSpace,
        candleCount: candleCount, plotWidth: 329), isFalse);
  });

  test('non-finite rulers and zero-width plots cannot expose a drawing', () {
    const latest = ChartViewport();
    for (final width in <double>[0, -1, double.nan, double.infinity]) {
      expect(ChartPositionViewportVisibility.overlapsPlot(
          position: buy, viewport: latest,
          candleCount: candleCount, plotWidth: width), isFalse);
    }
    expect(ChartPositionViewportVisibility.overlapsPlot(
        position: buy, viewport: const ChartViewport(barWidth: double.nan),
        candleCount: candleCount, plotWidth: 329), isFalse);
    expect(ChartPositionViewportVisibility.overlapsPlot(
        position: buy, viewport: const ChartViewport(scrollBars: double.infinity),
        candleCount: candleCount, plotWidth: 329), isFalse);
    expect(ChartPositionViewportVisibility.overlapsPlot(
        position: buy, viewport: latest,
        candleCount: 0, plotWidth: 329), isFalse);
  });
}
