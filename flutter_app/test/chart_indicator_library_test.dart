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
      'indicator("A", overlay=true)\nplot(ta.ema(close, 20))',
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
}
