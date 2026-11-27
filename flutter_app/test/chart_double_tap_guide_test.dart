import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/screens/chart_screen.dart';

/// Offline, source-shaped candles are test fixtures, not live broker prices.
void main() {
  for (final width in <double>[320, 390]) {
    testWidgets('double-tapped horizontal guide moves without resetting '
        'the chart at ${width}dp', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final client = MockClient((request) async {
        if (request.url.path == '/api/v3/klines') {
          return http.Response(jsonEncode(List.generate(120, (i) {
            final ms = 1700000000000 + i * 900000;
            return [ms, '${35000 + i}', '${35100 + i}',
              '${34900 + i}', '${35050 + i}', '1', ms + 899999];
          })), 200);
        }
        return http.Response('{"error":"offline"}', 503);
      });
      final market = MarketController(api: MarketApi(client: client));
      addTearDown(market.dispose);
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: ChartScreen(controller: market, requestedSymbolCode: 'BTCUSDT'),
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chart-source-empty')), findsNothing);
      final area = tester.getRect(find.byKey(const Key('chart-gesture-area')));
      final contact = Offset(area.left + (area.width - 61) * .55,
          area.center.dy);

      await tester.tap(find.byKey(const Key('drawing-rail-open-catalog')));
      await tester.pumpAndSettle();
      final tool = find.byKey(const Key('drawing-tool-horizontal'));
      await tester.ensureVisible(tool);
      await tester.tap(tool);
      await tester.pumpAndSettle();
      await tester.tapAt(contact);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(ChartScreen));
      expect(state.debugGuideDragSelection.levels, 1);

      // Exit drawing mode. Editing by double tap must work in ordinary
      // chart-pan mode, without enabling a toolbar drawing tool.
      await tester.tap(find.byKey(const Key('drawing-rail-cursor')));
      await tester.pumpAndSettle();

      await tester.tapAt(contact);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(contact);
      await tester.pumpAndSettle();
      final selected = state.debugGuideDragSelection;
      expect(selected.doubleTapGuideArmed, isTrue,
          reason: 'Double tap on a real line must arm line movement');
      expect(selected.selectedLine, 0);
      final initialPrice = selected.levelValue;
      expect(initialPrice, isNotNull);

      final finger = await tester.startGesture(contact);
      await finger.moveBy(const Offset(0, -24));
      await tester.pump();
      expect(state.debugGuideDragSelection.draggingLine, isTrue);
      await finger.moveBy(const Offset(0, -24));
      await tester.pump();
      final changed = state.debugGuideDragSelection;
      expect(changed.levelValue, isNot(initialPrice),
          reason: 'The authentic price-anchored guide must actually move');
      await finger.up();
      await tester.pumpAndSettle();
      expect(state.debugGuideDragSelection.doubleTapGuideArmed, isFalse);
      expect(state.debugGuideDragSelection.draggingLine, isFalse);
      expect(state.debugGuideDragSelection.levels, 1,
          reason: 'Moving the line cannot place a duplicate drawing');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('armed guide is cleared on market switch and hidden tab',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = MockClient((request) async {
      if (request.url.path == '/api/v3/klines') {
        return http.Response(jsonEncode(List.generate(120, (i) {
          final ms = 1700000000000 + i * 900000;
          return [ms, '${35000 + i}', '${35100 + i}',
            '${34900 + i}', '${35050 + i}', '1', ms + 899999];
        })), 200);
      }
      return http.Response('{"error":"offline"}', 503);
    });
    final market = MarketController(api: MarketApi(client: client));
    addTearDown(market.dispose);

    Future<void> mount(String symbol, {bool active = true}) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: ChartScreen(controller: market,
            requestedSymbolCode: symbol, active: active),
      )));
      await tester.pumpAndSettle();
    }
    await mount('BTCUSDT');
    expect(find.byKey(const Key('chart-source-empty')), findsNothing);
    final area = tester.getRect(find.byKey(const Key('chart-gesture-area')));
    final contact = Offset(area.left + (area.width - 61) * .55,
        area.center.dy);
    final dynamic state = tester.state(find.byType(ChartScreen));

    Future<void> createAndArmGuide() async {
      await tester.tap(find.byKey(const Key('drawing-rail-open-catalog')));
      await tester.pumpAndSettle();
      final tool = find.byKey(const Key('drawing-tool-horizontal'));
      await tester.ensureVisible(tool);
      await tester.tap(tool);
      await tester.pumpAndSettle();
      await tester.tapAt(contact);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(state.debugGuideDragSelection.levels, 1);
      await tester.tap(find.byKey(const Key('drawing-rail-cursor')));
      await tester.pumpAndSettle();
      await tester.tapAt(contact);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(contact);
      await tester.pumpAndSettle();
      expect(state.debugGuideDragSelection.doubleTapGuideArmed, isTrue);
    }

    await createAndArmGuide();
    await mount('ETHUSDT');
    expect(state.debugGuideDragSelection.doubleTapGuideArmed, isFalse,
        reason: 'BTC drawing edit must never survive an ETH source switch');
    expect(state.debugGuideDragSelection.levels, 0,
        reason: 'Previous symbol drawings must not be re-used as ETH guides');
    expect(find.byKey(const Key('chart-source-empty')), findsNothing);

    await createAndArmGuide();
    await mount('ETHUSDT', active: false);
    expect(state.debugGuideDragSelection.doubleTapGuideArmed, isFalse,
        reason: 'Leaving the chart tab must cancel its pending edit');
    expect(tester.takeException(), isNull);
  });

}
