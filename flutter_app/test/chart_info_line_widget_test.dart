import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradelab_flutter/chart/chart_annotations.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/screens/chart_screen.dart';

/// Offline BTCUSDT-shaped bars are test-only. The chart must never create
/// fabricated quotes, candles or future Replay history.
void main() {
  for (final width in <double>[320, 390]) {
    testWidgets('Info Line uses two market source anchors and does not '
        'refetch at ${width}dp', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var requests = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/api/v3/klines') {
          requests++;
          return http.Response(jsonEncode(List.generate(120, (i) {
            final ms = 1700000000000 + i * 900000;
            final price = 35000.0 + i * 10.0;
            return [ms, '$price', '${price + 30}',
                '${price - 20}', '${price + 5}', '1', ms + 899999];
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
      final originalRequests = requests;
      expect(originalRequests, greaterThan(0));

      await tester.tap(find.byKey(const Key('drawing-rail-open-catalog')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('drawing-tools-search')),
          'خط معلومات');
      await tester.pumpAndSettle();
      final tool = find.byKey(const Key('drawing-tool-infoLine'));
      expect(tool, findsOneWidget);
      await tester.ensureVisible(tool);
      await tester.tap(tool);
      await tester.pumpAndSettle();

      final area = tester.getRect(find.byKey(const Key('chart-gesture-area')));
      final plot = area.width - 61;
      final start = Offset(area.left + plot * .32, area.center.dy + 45);
      final end = Offset(area.left + plot * .67, area.center.dy - 46);
      await tester.tapAt(start);
      await tester.pump(const Duration(milliseconds: 420));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(ChartScreen));
      expect(state.debugGuideDragSelection.patterns, 0,
          reason: 'First tap only sets the source start anchor');
      await tester.tapAt(end);
      await tester.pump(const Duration(milliseconds: 420));
      await tester.pumpAndSettle();

      final created = state.debugGuideDragSelection;
      expect(created.patterns, 1);
      expect(created.patternValue!.tool, ChartDrawingTool.infoLine);
      expect(created.patternValue!.showLabels, isTrue);
      expect(created.patternValue!.start.index,
          isNot(created.patternValue!.end.index));
      expect(created.patternValue!.visibleAt(
          created.patternValue!.end.index), isFalse,
          reason: 'Replay must hide info labels on future unrevealed bars');
      expect(requests, originalRequests,
          reason: 'Drawing a line uses downloaded verified candles only');
      expect(tester.takeException(), isNull);
    });
  }
}
