import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/screens/chart_screen.dart';

/// A genuine Flutter render snapshot for layout review, not a broker source.
/// Test-only deterministic BTCUSDT OHLC stays inside MockClient and is NEVER
/// included in a release app, a Replay history, or a cTrader BID gateway.
///
/// The goldens are captured on GitHub's Linux Flutter test renderer. They
/// should be checked against the user's original reference screenshot, then
/// independently confirmed on an actual Android phone at the SAME DPR.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // flutter_test defaults to Ahem: every Arabic letter and digit becomes
    // a square. Ahem makes layout tests deterministic, but photographs of
    // its squares are NOT a useful TradingView visual comparison.
    //
    // Load the Ubuntu's open-source Arabic-capable DejaVuSans *only into
    // this screenshot test*. No font is committed or shipped in the APK.
    final bytes = await File(
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    ).readAsBytes();
    for (final family in <String>['TradeLabVisualQA', 'Roboto', 'Ahem']) {
      final loader = FontLoader(family)
        ..addFont(Future<ByteData>.value(ByteData.sublistView(
            Uint8List.fromList(bytes))));
      await loader.load();
    }
    // Unit tests do not automatically load the material icon typeface.
    // Without this, every chart toolbar and drawing-rail icon becomes a
    // square even when the real Android APK shows the proper vector glyph.
    final sdkRoot = Platform.environment['FLUTTER_ROOT'];
    if (sdkRoot == null || sdkRoot.isEmpty) {
      throw StateError('FLUTTER_ROOT is required for visual QA icons');
    }
    final materialIcons = File(
        '$sdkRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (!materialIcons.existsSync()) {
      throw StateError('Material Icons test font is missing at '
          '${materialIcons.path}');
    }
    final iconBytes = await materialIcons.readAsBytes();
    await (FontLoader('MaterialIcons')..addFont(
        Future<ByteData>.value(ByteData.sublistView(iconBytes)))).load();
  });
  for (final caseConfig in <({double width, double height, bool dark, String label})>[
    (width: 360, height: 640, dark: true, label: 'dark-360x640'),
    (width: 390, height: 844, dark: true, label: 'dark-390x844'),
    (width: 360, height: 640, dark: false, label: 'light-360x640'),
  ]) {
    testWidgets('capture chart UI visual QA ${caseConfig.label}',
        (tester) async {
      await tester.binding.setSurfaceSize(
          Size(caseConfig.width, caseConfig.height));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final broker = MockClient((request) async {
        if (request.url.path == '/api/v3/klines') {
          // OHLC data is intentionally synthetic TEST FIXTURE ONLY.
          // It is excluded from product binaries, fixtures are never sold
          // as historical quotes, and network requests are intercepted.
          return http.Response(jsonEncode(List.generate(240, (index) {
            final at = 1795176000000 + index * 900000;
            final mid = 40200.0 +
                85 * math.sin(index / 15.0) + index * .35;
            final open = mid;
            final close = mid + math.sin(index * 1.73) * 18;
            final high = math.max(open, close) + 7.5;
            final low = math.min(open, close) - 8.5;
            return [at, open.toStringAsFixed(2),
              high.toStringAsFixed(2), low.toStringAsFixed(2),
              close.toStringAsFixed(2), '1', at + 899999];
          })), 200);
        }
        return http.Response('{"error":"visual_qa_offline"}', 503);
      });
      final api = MarketApi(client: broker);
      final market = MarketController(api: api);
      addTearDown(market.dispose);
      addTearDown(api.close);

      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: caseConfig.dark ? Brightness.dark : Brightness.light,
          useMaterial3: true, fontFamily: 'TradeLabVisualQA'),
        home: Scaffold(body: ChartScreen(
          controller: market, requestedSymbolCode: 'BTCUSDT')),
      ));
      await tester.pumpAndSettle();

      final chart = find.byKey(const Key('chart-gesture-area'));
      expect(chart, findsOneWidget);
      expect(find.byKey(const Key('chart-source-empty')), findsNothing,
          reason: 'Screenshot must contain actual Flutter-painted candles');
      expect(find.byKey(const Key('chart-reference-header')), findsOneWidget);

      await expectLater(find.byType(ChartScreen),
        matchesGoldenFile('goldens/chart-fixture-${caseConfig.label}.png'));

      // Capture tracking only at 360dp to inspect crosshair, source
      // candle OHLC inspector and source-time price labels. This is a
      // real LongPress Flutter gesture, not an illustration.
      if (caseConfig.label == 'dark-360x640') {
        final rect = tester.getRect(chart);
        await tester.longPressAt(Offset(rect.left + rect.width * .62,
            rect.top + rect.height * .52));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('chart-crosshair-ohlc-inspector')),
          findsOneWidget,
          reason: 'Crosshair screenshot should prove tracking UI is visible');
        await expectLater(find.byType(ChartScreen),
          matchesGoldenFile('goldens/chart-fixture-crosshair-360x640.png'));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
