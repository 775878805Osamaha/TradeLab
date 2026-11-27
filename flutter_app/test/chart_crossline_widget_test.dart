import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradelab_flutter/chart/chart_annotations.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/screens/chart_screen.dart';

/// Deterministic offline source-shaped fixture candles, never broker quotes
/// in production and never future Replay prices.
void main() {
  for (final width in <double>[320, 390]) {
    testWidgets('crossline is a genuine one-touch price/time source drawing '
        'at ${width}dp', (tester) async {
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
          'خط عرضي');
      await tester.pumpAndSettle();
      final tool = find.byKey(const Key('drawing-tool-crossLine'));
      expect(tool, findsOneWidget);
      await tester.ensureVisible(tool);
      await tester.tap(tool);
      await tester.pumpAndSettle();

      final area = tester.getRect(find.byKey(const Key('chart-gesture-area')));
      final touch = Offset(area.left + (area.width - 61) * .55,
          area.center.dy);
      await tester.tapAt(touch);
      await tester.pump(const Duration(milliseconds: 410));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(ChartScreen));
      final created = state.debugGuideDragSelection;
      expect(created.patterns, 1);
      expect(created.patternValue!.tool, ChartDrawingTool.crossLine);
      expect(created.patternValue!.start.index,
          created.patternValue!.end.index);
      expect(created.patternValue!.start.price,
          created.patternValue!.end.price);
      expect(created.patternValue!.visibleAt(
          created.patternValue!.start.index), isFalse,
          reason: 'Crossline must not reveal a future Replay source bar');

      // A double tap on a real painted arm arms precisely one source-anchored
      // edit instead of resetting the chart or placing a duplicate cross.
      await tester.tapAt(touch);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(touch);
      await tester.pumpAndSettle();
      expect(state.debugGuideDragSelection.doubleTapGuideArmed, isTrue);
      final before = state.debugGuideDragSelection.patternValue!.start.price;
      final finger = await tester.startGesture(touch);
      await finger.moveBy(const Offset(24, -24));
      await tester.pump();
      await finger.moveBy(const Offset(0, -20));
      await tester.pump();
      final moved = state.debugGuideDragSelection.patternValue!;
      expect(moved.start.price, isNot(before));
      expect(moved.start.index, moved.end.index);
      expect(moved.start.price, moved.end.price);
      await finger.up();
      await tester.pumpAndSettle();
      expect(state.debugGuideDragSelection.patterns, 1);
      expect(state.debugGuideDragSelection.doubleTapGuideArmed, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
