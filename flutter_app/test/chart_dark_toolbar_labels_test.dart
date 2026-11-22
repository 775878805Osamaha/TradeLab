import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/screens/chart_screen.dart';

void main() {
  for (final isDark in <bool>[true, false]) {
    testWidgets('TradingView-style chart ticker and timeframe are readable '
        'in ${isDark ? 'dark' : 'light'} toolbar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final market = MarketController();
      addTearDown(market.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          brightness: isDark ? Brightness.dark : Brightness.light,
          useMaterial3: true),
        home: Scaffold(body: ChartScreen(controller: market)),
      ));
      await tester.pumpAndSettle();
      final symbol = find.byKey(const Key('symbol-picker'));
      final timeframe = find.byKey(const Key('timeframe-picker'));
      expect(symbol, findsOneWidget);
      expect(timeframe, findsOneWidget);
      final title = tester.widget<Text>(find.descendant(
          of: symbol, matching: find.byType(Text)).first);
      final subtitle = tester.widgetList<Text>(find.descendant(
          of: symbol, matching: find.byType(Text))).last;
      final time = tester.widget<Text>(find.descendant(
          of: timeframe, matching: find.byType(Text)).first);
      expect(title.style?.color, isDark
          ? const Color(0xFFF3F5F7) : const Color(0xFF101010));
      expect(time.style?.color, isDark
          ? const Color(0xFFF3F5F7) : const Color(0xFF333333));
      expect(subtitle.style?.color, isDark
          ? const Color(0xFFAFB9C5) : const Color(0xFF9B9B9B));
      expect(tester.takeException(), isNull);
    });
  }
}
