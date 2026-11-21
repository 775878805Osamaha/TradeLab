import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradelab_flutter/chart/chart_short_position.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/screens/chart_screen.dart';

/// Offline deterministic Binance-shaped source fixture. Nothing here
/// sends a broker order, fabricates an app quote or reads Replay future.
void main() {
  for (final width in <double>[320, 390]) {
    testWidgets('catalog long-position draws authentic price anchors on '
        'Android ${width}dp', (tester) async {
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
      await tester.tap(find.byKey(const Key('drawing-rail-open-catalog')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('drawing-tools-search')),
          'مركز شراء');
      await tester.pumpAndSettle();
      final longTool = find.byKey(const Key('drawing-tool-longPosition'));
      expect(longTool, findsOneWidget);
      await tester.ensureVisible(longTool);
      await tester.tap(longTool);
      await tester.pumpAndSettle();

      final rect = tester.getRect(find.byKey(const Key('chart-gesture-area')));
      final plotWidth = rect.width - 61;
      final middleY = rect.top + (rect.height - 24) * .50;
      // Price axis is descending on Android: lower Y means higher price.
      final entry = Offset(rect.left + plotWidth * .46, middleY);
      final stop = Offset(rect.left + plotWidth * .52, middleY + 74);
      final target = Offset(rect.left + plotWidth * .66, middleY - 74);
      final dynamic state = tester.state(find.byType(ChartScreen));

      await tester.tapAt(entry);
      await tester.pump(const Duration(milliseconds: 400));
      expect(state.debugPositionDrawings.count, 0);
      await tester.tapAt(stop);
      await tester.pump(const Duration(milliseconds: 400));
      expect(state.debugPositionDrawings.count, 0,
          reason: 'A long stop below entry is not a completed position');
      await tester.tapAt(target);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final drawing = state.debugPositionDrawings;
      expect(drawing.count, 1);
      expect(drawing.direction, ChartPositionDirection.long);
      expect(drawing.stop, lessThan(drawing.entry));
      expect(drawing.target, greaterThan(drawing.entry));
      expect(find.byKey(const Key('short-position-placement-hint')),
          findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
