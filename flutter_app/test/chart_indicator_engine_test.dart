import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/candle_prefix.dart';
import 'package:tradelab_flutter/chart/chart_indicator_engine.dart';
import 'package:tradelab_flutter/chart/chart_indicator_library.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

class _CountedCandles extends ListBase<TradeCandle> {
  _CountedCandles(this.source);
  final List<TradeCandle> source;
  final List<int> reads = [];
  @override
  int get length => source.length;
  @override
  set length(int count) => throw UnsupportedError('read only');
  @override
  TradeCandle operator [](int index) {
    reads.add(index);
    return source[index];
  }
  @override
  void operator []=(int index, TradeCandle c) =>
      throw UnsupportedError('read only');
}

void main() {
  ChartIndicatorDefinition definition(String id, int period) =>
      ChartIndicatorDefinition(id, id, period);
  List<TradeCandle> candles(List<double> closes) =>
      closes.map((c) => TradeCandle(c,c,c,c)).toList(growable:false);

  test('all real built-in types have explicit placement and selection', () {
    final kinds = ChartIndicatorDefinition.builtIns
        .map((indicator) => indicator.kind).toSet();
    expect(kinds, containsAll(ChartIndicatorKind.values));
    expect(definition('ema-21',21).separatePane, isFalse);
    expect(definition('bb-20',20).separatePane, isFalse);
    expect(definition('rsi-14',14).separatePane, isTrue);
    expect(definition('macd',12).separatePane, isTrue);
    final selected = const ChartIndicatorLibraryState()
        .toggleActive('rsi-14').toggleActive('macd');
    expect(selected.active, hasLength(2));
    expect(selected.toggleActive('atr-14'), same(selected),
      reason: 'Never hide a third unrenderable pane in the added list');
    expect(selected.toggleActive('ema-21').active, hasLength(3));
  });

  test('EMA uses source first-close seed and alpha=2/(period+1)', () {
    final bars = candles([10,20,30,40]);
    final result = ChartIndicatorEngine.compute(bars,definition('ema-9',3));
    final values = result.plots.single.values;
    expect(values, [10,15,22.5,31.25]);
    final same = ChartIndicatorEngine.compute(bars,definition('ema-9',1));
    expect(same.plots.single.values, [10,20,30,40]);
  });

  test('Bollinger 20 uses population standard deviation and 3 overlays', () {
    final values = List<double>.generate(20,(i)=>i+1.0);
    final result = ChartIndicatorEngine.compute(
      candles(values),definition('bb-20',20));
    expect(result.plots, hasLength(3));
    for (final plot in result.plots) {
      expect(plot.values.take(19).every((x)=>x==null),isTrue);
    }
    final sigma = math.sqrt(33.25);
    expect(result.plots[0].values[19],closeTo(10.5,1e-10));
    expect(result.plots[1].values[19],closeTo(10.5+2*sigma,1e-10));
    expect(result.plots[2].values[19],closeTo(10.5-2*sigma,1e-10));
  });

  test('RSI Wilder seed, rising/falling/oscillating values are deterministic',(){
    final up = List<double>.generate(18, (i)=>100+i.toDouble());
    final down = List<double>.generate(18, (i)=>100-i.toDouble());
    final rUp = ChartIndicatorEngine.compute(
      candles(up),definition('rsi-14',14)).plots.single.values;
    final rDn = ChartIndicatorEngine.compute(
      candles(down),definition('rsi-14',14)).plots.single.values;
    expect(rUp.take(14).every((x)=>x==null),isTrue);
    expect(rUp[14],100);
    expect(rDn[14],0);
    final rMixed = ChartIndicatorEngine.compute(
      candles([100,101,100,101]),definition('rsi-14',2))
        .plots.single.values;
    expect(rMixed,[null,null,50,75]);
    for(final v in rMixed.whereType<double>()){
      expect(v,inInclusiveRange(0,100));
    }
  });

  test('MACD has canonical 12/26/9 moving averages and zero histogram',(){
    final flat = ChartIndicatorEngine.compute(
      candles(List<double>.filled(60,100)),definition('macd',12));
    expect(flat.plots.map((p)=>p.title),
      ['MACD','Signal','Histogram']);
    expect(flat.plots.last.histogram,isTrue);
    for(final plot in flat.plots){
      expect(plot.values.whereType<double>().every((n)=>n.abs()<1e-12),
        isTrue);
    }
    final rising = ChartIndicatorEngine.compute(
      candles(List<double>.generate(40,(i)=>10+i.toDouble())),
      definition('macd',12));
    final bar = rising.plots;
    final expectedLine = 2/13 - 2/27;
    final expectedSignal = expectedLine * (2/10);
    expect(bar[0].values[1],closeTo(expectedLine,1e-12));
    expect(bar[1].values[1],closeTo(expectedSignal,1e-12));
    expect(bar[2].values[1],
        closeTo(expectedLine-expectedSignal,1e-12));
  });

  test('ATR Wilder true range sees real session price gaps',(){
    final bars = [
      const TradeCandle(10,12,9,11),
      const TradeCandle(11,15,10,14),
      const TradeCandle(14,15,12,13),
      const TradeCandle(13,14,11,12),
    ];
    final atr = ChartIndicatorEngine.compute(bars,
        definition('atr-14',3)).plots.single.values;
    expect(atr[0],isNull);
    expect(atr[1],isNull);
    expect(atr[2],closeTo(11/3,1e-12));
    expect(atr[3],closeTo(31/9,1e-12));
  });

  test('retained cache avoids re-reading 120k broker bars on touch frames',(){
    final bars = _CountedCandles(List<TradeCandle>.generate(120000,(i){
      final close = 100+(i%19).toDouble();
      return TradeCandle(close,close+1,close-1,close);
    }));
    final cache = ChartIndicatorSeriesCache();
    final ema = definition('ema-200',200);
    final first = cache.get(bars,ema);
    expect(bars.reads.length,120000);
    bars.reads.clear();
    for (var i=0;i<100;i++) {
      expect(identical(cache.get(bars,ema),first),isTrue);
    }
    expect(bars.reads,isEmpty,
      reason: 'Pan/pinch must never scan historical EMA again');
    final rsi = definition('rsi-14',14);
    final another = cache.get(bars,rsi);
    expect(another.plots.single.values.length,120000);
    expect(cache.get(bars,rsi),same(another));
  });

  test('Replay hidden future is never read, including MACD and RSI panes',(){
    final actual = _CountedCandles([
      const TradeCandle(100,101,99,100),
      const TradeCandle(110,111,109,110),
      const TradeCandle(120,121,119,120),
      const TradeCandle(999999,1000000,999998,999999),
    ]);
    final cache = ChartIndicatorSeriesCache();
    final prefix = CandlePrefix(actual,3);
    for (final d in [
      definition('ema-9',2),definition('bb-20',2),
      definition('rsi-14',2),definition('macd',12),definition('atr-14',2),
    ]) {
      final output = cache.get(prefix,d);
      expect(output.plots.first.values.length,3);
    }
    expect(actual.reads.every((i)=>i<3),isTrue,
      reason:'A verified Replay prefix must prohibit hidden future values');
    actual.reads.clear();
    final rewound = CandlePrefix(actual,2);
    expect(cache.get(rewound,definition('rsi-14',2))
       .plots.single.values.length,2);
    expect(actual.reads.every((i)=>i<2),isTrue);
  });
  test('zero-loss TradingView RSI yields 100 even on flat close', () {
    final values = ChartIndicatorEngine.compute(
      candles(List<double>.filled(35, 100)),
      definition('rsi-14', 14)).plots.single.values;
    expect(values.take(14).every((value) => value == null), isTrue);
    expect(values.skip(14).every((value) => value == 100.0), isTrue,
      reason: 'Pine RSI checks average loss == 0 before average gain == 0');
    final dropping = ChartIndicatorEngine.compute(
      candles(List<double>.generate(35, (i) => 100 - i.toDouble())),
      definition('rsi-14', 14)).plots.single.values;
    expect(dropping[34], 0);
  });

  test('Stochastic 14/3/3 matches source-indexed highs/lows and warmup', () {
    final bars = List<TradeCandle>.generate(40, (i) {
      final close = 100 + i.toDouble();
      return TradeCandle(close, close + 1, close - 1, close);
    });
    final result = ChartIndicatorEngine.compute(
      bars, definition('stoch-14', 14));
    expect(result.plots.map((p) => p.title), ['%K', '%D']);
    final k = result.plots[0].values;
    final d = result.plots[1].values;
    expect(k.take(15).every((value) => value == null), isTrue);
    expect(d.take(17).every((value) => value == null), isTrue);
    final raw = 100 * 14 / 15;
    for (var i = 15; i < bars.length; i++) {
      expect(k[i], closeTo(raw, 1e-10), reason: 'smoothed %K at bar '+i.toString());
      if (i >= 17) expect(d[i], closeTo(raw, 1e-10));
    }
  });

  test('Stochastic monotonic deque equals independent rolling extrema', () {
    final bars = List<TradeCandle>.generate(175, (i) {
      final value = 100.0 + 17 * math.sin(i * .73);
      return TradeCandle(
        value - 1.2, value + 2 + (i % 3), value - 3 - (i % 2),
        value + math.cos(i * .27),
      );
    });
    final output = ChartIndicatorEngine.compute(
      bars, definition('stoch-14', 19));
    final raw = List<double?>.filled(bars.length, null);
    final expectedK = List<double?>.filled(bars.length, null);
    final expectedD = List<double?>.filled(bars.length, null);
    for (var i = 18; i < bars.length; i++) {
      final values = bars.sublist(i - 18, i + 1);
      final hi = values.map((b) => b.high).reduce(math.max);
      final lo = values.map((b) => b.low).reduce(math.min);
      raw[i] = 100 * (bars[i].close - lo) / (hi - lo);
      if (i >= 20) {
        expectedK[i] = (raw[i]! + raw[i-1]! + raw[i-2]!) / 3;
      }
      if (i >= 22) {
        expectedD[i] = (expectedK[i]! + expectedK[i-1]! +
          expectedK[i-2]!) / 3;
      }
    }
    for (var i = 0; i < bars.length; i++) {
      if (expectedK[i] == null) {
        expect(output.plots[0].values[i], isNull);
      } else {
        expect(output.plots[0].values[i], closeTo(expectedK[i]!, 1e-8));
      }
      if (expectedD[i] == null) {
        expect(output.plots[1].values[i], isNull);
      } else {
        expect(output.plots[1].values[i], closeTo(expectedD[i]!, 1e-8));
      }
    }
  });

  test('Stochastic zero-range never invents an oscillator value', () {
    final bars = List<TradeCandle>.filled(
      45, const TradeCandle(100,100,100,100));
    final result = ChartIndicatorEngine.compute(
      bars, definition('stoch-14', 14));
    expect(result.plots, hasLength(2));
    expect(result.plots.every((p) =>
      p.values.every((value) => value == null)), isTrue);
  });

  test('ROC 9 is a percent change over exactly nine source candles', () {
    final bars = candles([
      100, 101, 102, 103, 104, 105, 106, 107, 108, 120, 124,
    ]);
    final values = ChartIndicatorEngine.compute(
      bars, definition('roc-9', 9)).plots.single.values;
    expect(values.take(9).every((x) => x == null), isTrue);
    expect(values[9], closeTo(20, 1e-12));
    expect(values[10], closeTo(100 * 23 / 101, 1e-12));
    final zeroBars = candles([0, 1, 2, 3, 4, 5, 6, 7, 8, 100]);
    final zero = ChartIndicatorEngine.compute(
      zeroBars, definition('roc-9', 9)).plots.single.values;
    expect(zero[9], isNull,
      reason: 'Zero real source denominator is not a synthetic quote');
  });

  test('Stochastic 500 across 120k actual bars is linear time', () {
    final actual = _CountedCandles(List<TradeCandle>.generate(120000, (i) {
      final close = 100 + math.sin(i / 11) * 50;
      return TradeCandle(close, close + 4, close - 4, close);
    }));
    final cache = ChartIndicatorSeriesCache();
    final study = definition('stoch-14', 500);
    final original = cache.get(actual, study);
    expect(original.plots[0].values, hasLength(120000));
    expect(actual.reads.length, lessThan(120000 * 15),
      reason: 'Monotonic deque visits each candle O(1), not O(period)');
    actual.reads.clear();
    for (var i = 0; i < 60; i++) {
      expect(cache.get(actual, study), same(original));
    }
    expect(actual.reads, isEmpty,
      reason: 'Repeated finger repaint uses cached verified-source series');
  });

  test('Stochastic and ROC cannot see the unrevealed Replay candle', () {
    final actual = _CountedCandles(List<TradeCandle>.generate(70, (i) {
      final close = i == 69 ? 999999.0 : 100 + i.toDouble();
      return TradeCandle(close, close + 2, close - 2, close);
    }));
    final first = CandlePrefix(actual, 69);
    final cache = ChartIndicatorSeriesCache();
    for (final study in [
      definition('stoch-14', 14), definition('roc-9', 9),
    ]) {
      final result = cache.get(first, study);
      expect(result.plots.first.values.length, 69);
    }
    expect(actual.reads.every((index) => index < 69), isTrue);
    actual.reads.clear();
    final advanced = CandlePrefix(actual, 70);
    final after = cache.get(advanced, definition('roc-9', 9));
    expect(after.plots.single.values[69]!, greaterThan(100000),
      reason: 'Only advancing verified Replay can expose this genuine bar');
  });


}
