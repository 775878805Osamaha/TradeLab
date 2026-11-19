import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_candle_bodies.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';
import 'package:tradelab_flutter/chart/candle_prefix.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  List<Rect> rectangles(Path path) => path.computeMetrics().map(
    (metric) => metric.extractPath(0, metric.length).getBounds(),
  ).toList();

  void expectRectNear(Rect actual, Rect expected) {
    expect(actual.left, closeTo(expected.left, 1e-4));
    expect(actual.top, closeTo(expected.top, 1e-4));
    expect(actual.right, closeTo(expected.right, 1e-4));
    expect(actual.bottom, closeTo(expected.bottom, 1e-4));
  }

  test('batched body rectangles keep original source OHLC geometry', () {
    const candles = <TradeCandle>[
      TradeCandle(10, 14, 9, 12),
      TradeCandle(12, 14, 10, 11),
      TradeCandle(11, 13, 10, 12),
      TradeCandle(12, 14, 10, 9),
    ];
    final paths = ChartCandleBodies.visible(
      candles: candles,
      viewport: const ChartViewport(barWidth: 10),
      start: 0, end: candles.length, plotWidth: 40,
      priceY: (price) => (20 - price) * 10,
      colorByPreviousClose: false,
    );
    final rising = rectangles(paths.rising);
    final falling = rectangles(paths.falling);
    expect(rising, hasLength(2));
    expect(falling, hasLength(2));
    expectRectNear(rising[0], const Rect.fromLTRB(1.6, 80, 8.4, 101));
    expectRectNear(falling[0], const Rect.fromLTRB(11.6, 80, 18.4, 91));
    expectRectNear(rising[1], const Rect.fromLTRB(21.6, 80, 28.4, 91));
    expectRectNear(falling[1], const Rect.fromLTRB(31.6, 80, 38.4, 111));
  });

  test('doji body keeps the original minimum one-pixel height', () {
    const candles = <TradeCandle>[TradeCandle(10, 12, 8, 10)];
    final paths = ChartCandleBodies.visible(
      candles: candles,
      viewport: const ChartViewport(barWidth: 3),
      start: 0, end: 1, plotWidth: 30,
      priceY: (price) => (20 - price) * 10,
      colorByPreviousClose: false,
    );
    final rect = rectangles(paths.rising).single;
    expect(rect.width, closeTo(2.04, 1e-4));
    expect(rect.height, closeTo(1, 1e-4));
    expect(rect.center.dx, closeTo(28.5, 1e-4));
  });

  test('previous close candle coloring differs from body coloring', () {
    const candles = <TradeCandle>[
      TradeCandle(10, 13, 9, 12),
      TradeCandle(9, 14, 8, 10), // Rising body but below previous close.
    ];
    ChartBodyPaths build(bool previousClose) => ChartCandleBodies.visible(
      candles: candles,
      viewport: const ChartViewport(barWidth: 10),
      start: 1, end: 2, plotWidth: 40,
      priceY: (price) => price,
      colorByPreviousClose: previousClose,
    );
    expect(rectangles(build(false).rising), hasLength(1));
    expect(rectangles(build(false).falling), isEmpty);
    expect(rectangles(build(true).rising), isEmpty);
    expect(rectangles(build(true).falling), hasLength(1));
  });

  test('historical pan culls the same candle columns as the old painter', () {
    final candles = List<TradeCandle>.filled(
      20, const TradeCandle(10, 12, 9, 11));
    final paths = ChartCandleBodies.visible(
      candles: candles,
      viewport: const ChartViewport(barWidth: 10),
      start: 0, end: candles.length, plotWidth: 40,
      priceY: (price) => price,
      colorByPreviousClose: false,
    );
    expect(rectangles(paths.rising), hasLength(5));
    expect(rectangles(paths.falling), isEmpty);
  });

  test('Replay prefix cannot expose a future candle body', () {
    const candles = <TradeCandle>[
      TradeCandle(10, 12, 9, 11),
      TradeCandle(11, 13, 10, 12),
      TradeCandle(12, 15, 11, 14),
      TradeCandle(14, 999, 0, 998),
    ];
    final visible = CandlePrefix(candles, 2);
    final paths = ChartCandleBodies.visible(
      candles: visible,
      viewport: const ChartViewport(),
      start: 0, end: visible.length, plotWidth: 40,
      priceY: (price) => price,
      colorByPreviousClose: false,
    );
    expect(rectangles(paths.rising), hasLength(2));
    expect(rectangles(paths.falling), isEmpty);
    expect(paths.rising.getBounds().bottom, lessThan(100));
  });

  test('invalid canvas dimensions or prices produce no body contours', () {
    const candles = <TradeCandle>[TradeCandle(10, 12, 9, 11)];
    ChartBodyPaths build(double width, double Function(double) y) =>
        ChartCandleBodies.visible(
          candles: candles,
          viewport: const ChartViewport(),
          start: -10, end: 100, plotWidth: width,
          priceY: y, colorByPreviousClose: false,
        );
    for (final width in <double>[
      double.nan, double.infinity, double.negativeInfinity, 0, -1
    ]) {
      expect(rectangles(build(width, (v) => v).rising), isEmpty);
    }
    expect(rectangles(build(40, (_) => double.nan).rising), isEmpty);
    expect(rectangles(build(40, (v) => v).rising), hasLength(1));
  });
}
