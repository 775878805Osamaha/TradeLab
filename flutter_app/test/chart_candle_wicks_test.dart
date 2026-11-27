import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_candle_wicks.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';
import 'package:tradelab_flutter/chart/candle_prefix.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  Offset position(PathMetric segment, double distance) =>
      segment.getTangentForOffset(distance)!.position;

  test('bull and bear wick paths preserve source price and chartX geometry',
      () {
    const candles = <TradeCandle>[
      TradeCandle(10, 14, 9, 12),
      TradeCandle(12, 14, 10, 11),
      TradeCandle(11, 13, 10, 12),
      TradeCandle(12, 14, 10, 9),
    ];
    const viewport = ChartViewport(barWidth: 10);
    final paths = ChartCandleWicks.visible(
      candles: candles,
      viewport: viewport,
      start: 0,
      end: candles.length,
      plotWidth: 40,
      priceY: (value) => (20 - value) * 10,
      colorByPreviousClose: false,
    );
    final rising = paths.rising.computeMetrics().toList();
    final falling = paths.falling.computeMetrics().toList();
    expect(rising, hasLength(2));
    expect(falling, hasLength(2));

    // Original drawLine used the same high/low price map and chartX index.
    final expectedRising = <(Offset, Offset)>[
      (const Offset(5, 60), const Offset(5, 110)),
      (const Offset(25, 70), const Offset(25, 100)),
    ];
    final expectedFalling = <(Offset, Offset)>[
      (const Offset(15, 60), const Offset(15, 100)),
      (const Offset(35, 60), const Offset(35, 100)),
    ];
    for (var i = 0; i < 2; i++) {
      expect(position(rising[i], 0), expectedRising[i].$1);
      expect(position(rising[i], rising[i].length), expectedRising[i].$2);
      expect(position(falling[i], 0), expectedFalling[i].$1);
      expect(position(falling[i], falling[i].length), expectedFalling[i].$2);
    }
  });

  test('previous close color option uses source predecessor, not body color',
      () {
    const candles = <TradeCandle>[
      TradeCandle(10, 13, 8, 12),
      TradeCandle(9, 14, 8, 10), // Bullish body, lower previous close.
    ];
    ChartWickPaths paths(bool previousClose) => ChartCandleWicks.visible(
      candles: candles,
      viewport: const ChartViewport(barWidth: 10),
      start: 1,
      end: 2,
      plotWidth: 40,
      priceY: (price) => price,
      colorByPreviousClose: previousClose,
    );
    expect(paths(false).rising.computeMetrics().length, 1);
    expect(paths(false).falling.computeMetrics().isEmpty, isTrue);
    expect(paths(true).rising.computeMetrics().isEmpty, isTrue);
    expect(paths(true).falling.computeMetrics().length, 1);
  });

  test('only rendered candle columns contribute visible wick contours', () {
    const candle = TradeCandle(10, 12, 8, 11);
    final candles = List<TradeCandle>.filled(20, candle);
    final paths = ChartCandleWicks.visible(
      candles: candles,
      viewport: const ChartViewport(barWidth: 10),
      start: 0,
      end: candles.length,
      plotWidth: 40,
      priceY: (price) => 20 - price,
      colorByPreviousClose: false,
    );
    // The original painter accepted one extra candle just past each edge.
    // At this viewport, x=-5, 5, 15, 25, 35 are drawn; x=-15 is rejected.
    expect(paths.rising.computeMetrics().length, 5);
    expect(paths.falling.computeMetrics().isEmpty, isTrue);
  });

  test('Replay prefix paths never render unrevealed future candles', () {
    const source = <TradeCandle>[
      TradeCandle(10, 12, 9, 11),
      TradeCandle(11, 14, 10, 13),
      TradeCandle(13, 15, 11, 12),
      TradeCandle(12, 90, 1, 88), // Hidden after Replay cut.
    ];
    final prefix = CandlePrefix(source, 2);
    final paths = ChartCandleWicks.visible(
      candles: prefix,
      viewport: const ChartViewport(),
      start: 0,
      end: prefix.length,
      plotWidth: 40,
      priceY: (price) => price,
      colorByPreviousClose: false,
    );
    expect(paths.rising.computeMetrics().length, 2);
    expect(paths.falling.computeMetrics().isEmpty, isTrue);
  });

  test('invalid viewport and non-finite price projections are ignored', () {
    const source = <TradeCandle>[TradeCandle(10, 12, 8, 11)];
    ChartWickPaths paths(double width, double Function(double) project) =>
        ChartCandleWicks.visible(
          candles: source,
          viewport: const ChartViewport(),
          start: -10,
          end: 100,
          plotWidth: width,
          priceY: project,
          colorByPreviousClose: false,
        );
    expect(paths(double.nan, (v) => v).rising.computeMetrics().isEmpty,
      isTrue);
    expect(paths(double.infinity, (v) => v).rising.computeMetrics().isEmpty,
      isTrue);
    expect(paths(40, (v) => double.nan).rising.computeMetrics().isEmpty,
      isTrue);
    expect(paths(40, (v) => v).rising.computeMetrics().length, 1);
  });
}
