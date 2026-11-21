import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/screens/chart_screen.dart';
import 'package:tradelab_flutter/chart/chart_symbol_settings_page.dart';
import 'package:tradelab_flutter/chart/chart_scale_settings_page.dart';
import 'package:tradelab_flutter/chart/chart_ohlc_inspector.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  for (final width in <double>[320, 390]) {
    testWidgets('TradingView mobile tracking survives long-press lift and '
        'exits on a single tap at ${width}dp', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // Deterministic test fixtures only, not fabricated live broker quotes.
      // All chart OHLC selections resolve against the visible verified
      // provider-shaped candle source, never a hidden Replay future.
      final client = MockClient((request) async {
        if (request.url.path == '/api/v3/klines') {
          return http.Response(jsonEncode(List.generate(160, (index) {
            final ms = 1700000000000 + index * 60000;
            return [ms, '${35000 + index}', '${35010 + index}',
              '${34990 + index}', '${35005 + index}',
              '1', ms + 59999];
          })), 200);
        }
        return http.Response('{"error":"offline"}', 503);
      });
      final market = MarketController(api: MarketApi(client: client));
      addTearDown(market.dispose);
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: ChartScreen(
          controller: market, requestedSymbolCode: 'BTCUSDT'),
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chart-source-empty')), findsNothing);

      final chart = find.byKey(const Key('chart-gesture-area'));
      final bounds = tester.getRect(chart);
      final plotWidth = bounds.width - 61;
      final inspected = Offset(
          bounds.left + plotWidth * .65, bounds.top + bounds.height * .5);
      final inspector = find.byKey(const Key('chart-crosshair-ohlc-inspector'));
      expect(inspector, findsNothing);

      // A long press opens OHLC inspection. The release of that same
      // finger must NOT remove the values and source-verified time guide.
      await tester.longPressAt(inspected);
      await tester.pump();
      expect(inspector, findsOneWidget,
          reason: 'Tracking stays visible after the long-press finger lifts');
      expect(find.byKey(const Key('chart-ohlc-open')), findsOneWidget);
      expect(find.byKey(const Key('chart-ohlc-close')), findsOneWidget);

      await tester.tapAt(Offset(
          bounds.left + plotWidth * .3, bounds.top + bounds.height * .4));
      await tester.pump();
      expect(inspector, findsNothing,
          reason: 'A single chart tap must leave OHLC tracking mode');
      expect(tester.takeException(), isNull);

      // TradingView Mobile uses long-press on the price/time rulers for
      // native scale menus, not OHLC tracking or the Replay blue cursor.
      await tester.longPressAt(Offset(
          bounds.right - 10, bounds.top + bounds.height * .5));
      await tester.pumpAndSettle();
      expect(inspector, findsNothing,
          reason: 'The price ruler cannot create a candle cursor');
      expect(find.byKey(const Key('chart-price-axis-menu-auto')),
          findsOneWidget);
      expect(find.byKey(const Key('chart-price-axis-menu-settings')),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('chart-price-axis-menu-auto')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chart-price-axis-menu-auto')),
          findsNothing);
      expect(find.byKey(const Key('chart-crosshair-ohlc-inspector')),
          findsNothing);

      // The price ruler has a direct entry to existing scale settings.
      // Canceling preserves the real source and returns to the chart.
      await tester.longPressAt(Offset(
          bounds.right - 10, bounds.top + bounds.height * .5));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(
          const Key('chart-price-axis-menu-settings')));
      await tester.pumpAndSettle();
      expect(find.byType(ChartScaleSettingsPage), findsOneWidget);
      await tester.tap(find.byKey(const Key('scale-cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('panel-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
      expect(find.byKey(const Key('chart-source-empty')), findsNothing);

      await tester.longPressAt(Offset(
          bounds.left + plotWidth * .5, bounds.bottom - 8));
      await tester.pumpAndSettle();
      expect(inspector, findsNothing,
          reason: 'Time ruler menu must not inspect a BID source candle');
      expect(find.byKey(const Key('chart-time-axis-menu-settings')),
          findsOneWidget);
      expect(find.byKey(const Key('chart-time-axis-menu-timezone')),
          findsOneWidget);
      await tester.tap(find.byKey(
          const Key('chart-time-axis-menu-timezone')));
      await tester.pumpAndSettle();
      expect(find.byType(ChartSymbolSettingsPage), findsOneWidget,
          reason: 'Time ruler opens the existing timezone/settings page '
              'without loading a new source history');
      expect(tester.takeException(), isNull);
    });
  }

  test('3px historical crosshair OHLC matches time guide source index', () {
    final candles = List<TradeCandle>.generate(100, (i) =>
        TradeCandle(100 + i.toDouble(), 104 + i.toDouble(),
            97 + i.toDouble(), 101 + i.toDouble()));
    final timestamps = List<int>.generate(100,
        (i) => DateTime.utc(2026, 11, 19).millisecondsSinceEpoch + i * 300000);
    const viewport = ChartViewport(
        barWidth: 3, scrollBars: 20, rightMarginBars: 4);
    final center = viewport.chartX(
        index: 70, candleCount: candles.length, plotWidth: 330);
    final found = ChartOhlcInspector.atCrosshair(
      viewport: viewport, touchX: center + 1.1, plotWidth: 330,
      candles: candles, timestampsUtcMs: timestamps,
    );
    expect(found, isNotNull);
    expect(found!.index, 70);
    expect(found.candle.open, 170);
    expect(found.candle.high, 174);
    expect(found.candle.low, 167);
    expect(found.candle.close, 171);
    expect(found.utcTimestampMs, timestamps[70]);
    expect(found.formatPrice(found.candle.close, 2), '171.00');
    final next = ChartOhlcInspector.atCrosshair(
      viewport: viewport, touchX: center + 2.0, plotWidth: 330,
      candles: candles, timestampsUtcMs: timestamps,
    );
    expect(next?.index, 71,
        reason: 'The guide, the candle and all four OHLC prices move together');
  });

  test('Replay selection is limited to visible candle prefix, not archive', () {
    const viewport = ChartViewport(barWidth: 10, scrollBars: -4);
    final wholeArchive = <TradeCandle>[
      const TradeCandle(10, 15, 9, 12),
      const TradeCandle(12, 14, 10, 11),
      const TradeCandle(11, 19, 10, 18),
      const TradeCandle(18, 22, 17, 20),
      const TradeCandle(999, 9999, 998, 9000),
    ];
    final allUtc = List<int>.generate(5,
        (i) => DateTime.utc(2026, 11, 19).millisecondsSinceEpoch + i * 60000);
    final replay = wholeArchive.sublist(0, 4);
    final lastVisibleX = viewport.chartX(
        index: 3, candleCount: replay.length, plotWidth: 300);
    final actual = ChartOhlcInspector.atCrosshair(
      viewport: viewport, touchX: lastVisibleX,
      plotWidth: 300, candles: replay, timestampsUtcMs: allUtc);
    expect(actual?.index, 3);
    expect(actual?.candle.close, 20);
    expect(actual?.utcTimestampMs, allUtc[3]);
    expect(ChartOhlcInspector.atCrosshair(
      viewport: viewport, touchX: 290,
      plotWidth: 300, candles: replay, timestampsUtcMs: allUtc), isNull,
      reason: 'There is no future candle in Replay right-hand whitespace');
    expect(wholeArchive[4].close, 9000);
  });

  test('Range/HA inspected prices are the displayed representation', () {
    const raw = TradeCandle(2100, 2110, 2090, 2105);
    const heikin = TradeCandle(2102, 2109, 2092, 2104);
    const range = TradeCandle(2100, 2103, 2099, 2102);
    const viewport = ChartViewport(barWidth: 30);
    final x = viewport.chartX(index: 0, candleCount: 1, plotWidth: 300);
    const utc = [1795075200123];
    ChartOhlcSelection? inspect(TradeCandle candle) =>
        ChartOhlcInspector.atCrosshair(
          viewport: viewport, touchX: x, plotWidth: 300,
          candles: [candle], timestampsUtcMs: utc);
    expect(inspect(heikin)?.candle.close, 2104);
    expect(inspect(range)?.candle.high, 2103);
    expect(inspect(range)?.utcTimestampMs, utc[0]);
    expect(inspect(raw)?.candle.close, 2105);
    expect(inspect(range)?.changePercent, closeTo(2 / 2100 * 100, 1e-9));
  });

  test('source missing, future, invalid timestamp or blank areas have no OHLC',
      () {
    const candle = TradeCandle(0, 1, 0, 0);
    const viewport = ChartViewport(barWidth: 10, scrollBars: -10);
    final center = viewport.chartX(
      index: 0, candleCount: 1, plotWidth: 300);
    ChartOhlcSelection? at(double x, List<TradeCandle> bars,
        List<int> times) => ChartOhlcInspector.atCrosshair(
          viewport: viewport, touchX: x, plotWidth: 300,
          candles: bars, timestampsUtcMs: times);
    expect(at(center, [candle], [1795075200000])?.changePercent, isNull,
        reason: 'A zero source open must not create a synthetic percent');
    expect(at(295, [candle], [1795075200000]), isNull);
    expect(at(center, const [], const []), isNull);
    expect(at(center, [candle], const []), isNull);
    expect(at(center, [candle], [0]), isNull);
    expect(at(double.nan, [candle], [1795075200000]), isNull);
  });
}
