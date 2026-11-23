import 'dart:collection';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_indicator_library.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

class CountingBars extends ListBase<TradeCandle> {
  CountingBars(this.candles);
  final List<TradeCandle> candles;
  final List<int> reads = [];
  @override
  int get length => candles.length;
  @override
  set length(int next) => throw UnsupportedError('immutable');
  @override
  TradeCandle operator [](int index) {
    reads.add(index);
    return candles[index];
  }
  @override
  void operator []=(int index, TradeCandle candle) =>
      throw UnsupportedError('immutable');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('built-ins and searchable selection enable real multiple overlays', () {
    const original = ChartIndicatorLibraryState();
    expect(original.active, isEmpty);
    final after12 = original.toggleActive('sma-12');
    final after50 = after12.toggleActive('sma-50');
    expect(after50.active.map((x) => x.period), [12, 50]);
    expect(after50.toggleActive('sma-12').active.single.id, 'sma-50');
    expect(after50.toggleActive('not-real'), same(after50));
    expect(after50.toggleFavorite('sma-50').favoriteIds,
      contains('sma-50'));
  });

  test('simple overlay Pine SMA can run, complex strategy cannot', () {
    const valid = ChartSavedIndicatorScript(
      id: 'script-example', name: 'My SMA 21',
      source: '//@version=6\n'
        'indicator("My SMA", overlay=true)\n'
        'plot(ta.sma(close, 21))',
    );
    expect(valid.supportedSmaPeriod, 21);
    const strategy = ChartSavedIndicatorScript(
      id: 'script-unsupported', name: 'Unsupported User Strategy',
      source: '//@version=6\n'
        'strategy("Unsupported User Strategy", overlay=true)\n'
        'strategy.entry("Buy", strategy.long)\n'
        'plot(ta.sma(close, 21))',
    );
    expect(strategy.supportedSmaPeriod, isNull,
      reason: 'Never pretend a custom Pine trading strategy is an SMA');
    final state = const ChartIndicatorLibraryState()
      .saveScript(valid).saveScript(strategy);
    expect(state.scripts, hasLength(2));
    expect(state.supported.where((x) => x.custom).single.period, 21);
    expect(state.toggleActive('script-unsupported'), same(state),
      reason: 'Unsupported Pine is stored but must not run on the chart');
    final active = state.toggleActive('script-example');
    expect(active.active.single.id, 'script-example');
    expect(active.deleteScript('script-example').active, isEmpty);
    expect(active.deleteScript('script-example').scripts, hasLength(1));
  });

  test('script permissions reject multi-plot, requests, and invalid periods', () {
    for (final source in [
      'indicator("A", overlay=true)\nplot(ta.sma(close, 501))',
      'indicator("A", overlay=true)\nplot(ta.sma(close, 0))',
      'indicator("A", overlay=false)\nplot(ta.sma(close, 20))',
      'indicator("A", overlay=true)\n'
          'plot(ta.sma(close, 20))\nplot(close)',
      'indicator("A", overlay=true)\nrequest.security("A", "D", close)\n'
          'plot(ta.sma(close, 20))',
    ]) {
      expect(ChartSavedIndicatorScript(
        id: 'script-rejected', name: 'Unsafe', source: source,
      ).supportedSmaPeriod, isNull, reason: source);
    }
    expect(ChartSavedIndicatorScript(
      id: 'script-ok', name: 'SMA1',
      source: 'indicator("A", overlay=true)\nplot(ta.sma(close, 1))',
    ).supportedSmaPeriod, 1);
  });

  test('local persistence restores only supported active identifiers', () async {
    FlutterSecureStorage.setMockInitialValues({
      'tradelab_flutter_ctrader_session': 'broker-session-is-untouched',
    });
    final storage = SecureChartIndicatorLibraryStore(
        storage: const FlutterSecureStorage());
    final saved = const ChartIndicatorLibraryState()
      .toggleActive('sma-12')
      .toggleFavorite('sma-20')
      .saveScript(const ChartSavedIndicatorScript(
        id: 'script-saved', name: 'My 30 SMA',
        source: 'indicator("My 30", overlay=true)\n'
            'plot(ta.sma(close, 30))',
      )).toggleActive('script-saved');
    await storage.save(saved);
    final loaded = await SecureChartIndicatorLibraryStore(
        storage: const FlutterSecureStorage()).load();
    expect(loaded.active.map((x) => x.period), [12, 30]);
    expect(loaded.favoriteIds, contains('sma-20'));
    expect(loaded.scripts.single.source, contains('ta.sma'));
    expect(await const FlutterSecureStorage()
      .read(key: 'tradelab_flutter_ctrader_session'),
      'broker-session-is-untouched');
    expect(ChartIndicatorLibraryState.decode('invalid-json').active, isEmpty);
    final malicious = ChartIndicatorLibraryState.decode('{"version":1,'
      '"activeIds":["sma-12","script-unauthorized","nope"],'
      '"favoriteIds":["nope","sma-20"],"scripts":[]}');
    expect(malicious.active.map((item) => item.id), ['sma-12']);
    expect(malicious.favoriteIds, {'sma-20'});
  });

  test('panning across 120k bars scans only viewport plus SMA warmup', () {
    final bars = CountingBars(List<TradeCandle>.generate(120000, (i) {
      final close = 100.0 + (i % 13).toDouble();
      return TradeCandle(close, close, close, close);
    }));
    final pts = ChartIndicatorVisiblePoints.sma(
        candles: bars, start: 119895, end: 120000, period: 200);
    expect(pts, hasLength(105));
    expect(bars.reads.length, lessThanOrEqualTo(105 * 2 + 200));
    expect(bars.reads.every((i) => i >= 119695 && i < 120000), isTrue,
      reason: 'No 120k full-history rescan during every finger frame');
    final closes = List<double>.generate(200, (j) =>
        100.0 + ((120000 - 200 + j) % 13).toDouble());
    final actual = closes.reduce((a,b) => a + b) / 200;
    expect(pts.last.value, closeTo(actual, 1e-10));
  });

  test('Replay source cutoff never reads hidden future bar values', () {
    final source = CountingBars([
      const TradeCandle(10, 10, 10, 10),
      const TradeCandle(20, 20, 20, 20),
      const TradeCandle(30, 30, 30, 30),
      const TradeCandle(99999, 99999, 99999, 99999),
    ]);
    final vals = ChartIndicatorVisiblePoints.sma(
      candles: source, start: 0, end: 3, period: 3);
    expect(vals.map((point) => point.value), [10, 15, 20]);
    expect(source.reads.every((index) => index < 3), isTrue);
    expect(ChartIndicatorVisiblePoints.sma(
      candles: source, start: 4, end: 3, period: 3), isEmpty);
  });

  test('SMA lines agree with source close and exact warm-up on every pan', () {
    final bars = List<TradeCandle>.generate(60, (i) {
      final n = i.toDouble() + 1;
      return TradeCandle(n, n, n, n);
    });
    for (final period in [1, 12, 20, 50, 200]) {
      for (final start in [0, 7, 30, 52]) {
        final points = ChartIndicatorVisiblePoints.sma(
            candles: bars, start: start, end: 60, period: period);
        expect(points.length, 60 - start);
        for (final p in points) {
          final first = (p.index - period + 1).clamp(0, 60).toInt();
          final window = bars
            .sublist(first, p.index + 1).map((x) => x.close);
          final expected = window.reduce((a, b) => a + b) / window.length;
          expect(p.value, closeTo(expected, 1e-9));
        }
      }
    }
  });


  test('supported one-plot Pine EMA and RSI execute with correct placement',
      () {
    const emaScript = ChartSavedIndicatorScript(
      id:'script-ema',name:'My EMA 34',
      source:'//@version=6\nindicator("EMA", overlay=true)\n'
          'plot(ta.ema(close,34))');
    const rsiScript = ChartSavedIndicatorScript(
      id:'script-rsi',name:'My RSI 14',
      source:'//@version=6\nindicator("RSI", overlay=false)\n'
          'plot(ta.rsi(close,14))');
    expect(emaScript.supportedIndicator()?.kind,ChartIndicatorKind.ema);
    expect(emaScript.supportedIndicator()?.separatePane,isFalse);
    expect(rsiScript.supportedIndicator()?.kind,ChartIndicatorKind.rsi);
    expect(rsiScript.supportedIndicator()?.separatePane,isTrue);
    expect(rsiScript.supportedSmaPeriod,isNull);
    final state=const ChartIndicatorLibraryState()
        .saveScript(emaScript).saveScript(rsiScript)
        .toggleActive('script-ema').toggleActive('script-rsi');
    expect(state.active.where((x)=>x.custom).length,2);
    expect(state.active.first.period,34);
  });

  test('study-length customization is persisted and rejects invalid data',
      () {
    final base=const ChartIndicatorLibraryState();
    final configured=base.setPeriod('ema-21',34).setPeriod('rsi-14',9);
    expect(configured.active,isEmpty);
    final byId={for(final item in configured.supported)item.id:item};
    expect(byId['ema-21']!.title,'EMA 34');
    expect(byId['ema-21']!.period,34);
    expect(byId['rsi-14']!.period,9);
    expect(configured.setPeriod('macd',5),same(configured));
    expect(configured.setPeriod('rsi-14',1),same(configured));
    expect(configured.setPeriod('ema-21',501),same(configured));
    final restored=ChartIndicatorLibraryState.decode(configured.encode());
    expect(restored.periodOverrides,{'ema-21':34,'rsi-14':9});
    expect(restored.setPeriod('ema-21',21)
        .periodOverrides.containsKey('ema-21'),isFalse);
    final bad=ChartIndicatorLibraryState.decode(
      '{"version":1,"periodOverrides":'
      '{"macd":5,"ema-9":0,"rsi-14":1,"ema-21":37}}');
    expect(bad.periodOverrides,{'ema-21':37});
  });
  test('Stochastic and ROC appear in actual catalog and persist selection',
      () {
    final all = ChartIndicatorDefinition.builtIns;
    expect(all.map((x) => x.id), containsAll(['stoch-14', 'roc-9']));
    expect(all.singleWhere((x) => x.id == 'stoch-14').separatePane,
      isTrue);
    expect(all.singleWhere((x) => x.id == 'roc-9').separatePane,
      isTrue);
    final selected = const ChartIndicatorLibraryState()
        .toggleActive('stoch-14').toggleActive('roc-9');
    expect(selected.active.map((s) => s.kind),
      [ChartIndicatorKind.stochastic, ChartIndicatorKind.roc]);
    final restored = ChartIndicatorLibraryState.decode(selected.encode());
    expect(restored.activeIds, selected.activeIds);
    expect(restored.toggleActive('rsi-14'), same(restored),
      reason: 'Two independent panes are visible; do not hide a third');
    expect(restored.toggleActive('stoch-14').active.single.id, 'roc-9');
  });

  test('Stochastic lookback and ROC length validate and persist', () {
    final custom = const ChartIndicatorLibraryState()
        .setPeriod('stoch-14', 21)
        .setPeriod('roc-9', 12);
    expect(custom.supported.singleWhere((x) => x.id == 'stoch-14').period,
      21);
    expect(custom.supported.singleWhere((x) => x.id == 'stoch-14').title,
      'Stochastic 21');
    expect(custom.supported.singleWhere((x) => x.id == 'roc-9').title,
      'ROC 12');
    final decoded = ChartIndicatorLibraryState.decode(custom.encode());
    expect(decoded.periodOverrides, {'stoch-14': 21, 'roc-9': 12});
    expect(decoded.setPeriod('roc-9', 0), same(decoded));
    expect(decoded.setPeriod('stoch-14', 501), same(decoded));
  });


}
