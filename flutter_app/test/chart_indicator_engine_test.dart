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
}
