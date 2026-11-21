import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradelab_flutter/chart/chart_short_position.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/screens/chart_screen.dart';

/// Exercises the real retained chart paint path with deterministic offline
/// API-shaped fixture candles. It never substitutes broker data in the app.
void main() {
  for (final width in <double>[320, 390]) {
    for (final direction in ChartPositionDirection.values) {
      testWidgets('source-backed ${direction.name} stop dragging repaints '
          'without rebuilding chart header at ${width}dp', (tester) async {
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
            direction == ChartPositionDirection.long
                ? 'مركز شراء' : 'مركز بيع');
        await tester.pumpAndSettle();
        final kind = direction == ChartPositionDirection.long
            ? 'longPosition' : 'shortPosition';
        final tool = find.byKey(Key('drawing-tool-$kind'));
        await tester.ensureVisible(tool);
        await tester.tap(tool);
        await tester.pumpAndSettle();

        final rect = tester.getRect(find.byKey(const Key('chart-gesture-area')));
        final plotWidth = rect.width - 61;
        final y = rect.top + (rect.height - 24) * .50;
        final x = rect.left + plotWidth * .42;
        final entry = Offset(x, y);
        final stop = Offset(rect.left + plotWidth * .50,
            y + (direction == ChartPositionDirection.long ? 74 : -74));
        final target = Offset(rect.left + plotWidth * .68,
            y + (direction == ChartPositionDirection.long ? -74 : 74));
        for (final point in [entry, stop, target]) {
          await tester.tapAt(point);
          await tester.pump(const Duration(milliseconds: 410));
        }
        await tester.pumpAndSettle();

        final dynamic state = tester.state(find.byType(ChartScreen));
        final position = state.debugPositionDrawings;
        expect(position.count, 1);
        expect(position.direction, direction);
        final originalStop = position.stop;

        // The left-edge stop handle uses the *entry-bar* horizontal anchor,
        // not the screen x where the stop price was originally tapped.
        final finger = await tester.startGesture(Offset(x, stop.dy));
        await finger.moveBy(const Offset(0, 24));
        await tester.pump();
        final header = find.byKey(const Key('chart-reference-header'));
        final retainedHeader = tester.widget(header);
        for (var n = 0; n < 5; n++) {
          await finger.moveBy(const Offset(0, 5));
          await tester.pump();
          expect(identical(tester.widget(header), retainedHeader), isTrue,
              reason: 'Each handle sample must repaint the chart only, '
                  'not rebuild the toolbar or header');
          expect(tester.takeException(), isNull);
        }
        final dragged = state.debugPositionDrawings;
        expect(dragged.stop, isNot(originalStop),
            reason: 'The authentic source-price stop handle must move');
        expect(dragged.direction, direction);
        expect(direction == ChartPositionDirection.long
            ? dragged.stop < dragged.entry
            : dragged.stop > dragged.entry, isTrue);
        await finger.up();
        await tester.pumpAndSettle();
        expect(state.debugPositionDrawings.count, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
