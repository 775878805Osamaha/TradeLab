import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/candle_prefix.dart';
import 'package:tradelab_flutter/chart/chart_indicator_autoscale.dart';
import 'package:tradelab_flutter/chart/chart_indicator_engine.dart';
import 'package:tradelab_flutter/chart/chart_indicator_library.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

class _ReadGuard extends ListBase<TradeCandle> {
  _ReadGuard(this.source);
  final List<TradeCandle> source;
  final List<int> read = [];
  @override
  int get length => source.length;
  @override
  set length(int value) => throw UnsupportedError('immutable');
  @override
  TradeCandle operator [](int index) {
    read.add(index);
    return source[index];
  }
  @override
  void operator []=(int index, TradeCandle value) =>
      throw UnsupportedError('immutable');
}

void main() {
  List<TradeCandle> prices(List<double> closes) =>
      closes.map((p)=>TradeCandle(p,p+.1,p-.1,p))
        .toList(growable:false);

  test('source autoscale includes Bollinger 2-sigma lines and keeps OHLC',(){
    final source = prices(List<double>.generate(20, (i)=>100+i.toDouble()));
    const viewport = ChartViewport(barWidth:10, rightMarginBars:0);
    final base = ChartPriceScale.visible(source,viewport,200,240,
      topMarginPercent:0,bottomMarginPercent:0);
    final enlarged = ChartIndicatorAutoScale.include(
      base:base, candles:source, viewport:viewport, plotWidth:200,
      indicators:[const ChartIndicatorDefinition(
        'bb-20','Bollinger 20',20)],
      cache: ChartIndicatorSeriesCache());
    expect(enlarged.maximum, greaterThan(base.maximum));
    expect(enlarged.sourceMinimum, base.sourceMinimum);
    expect(enlarged.sourceMaximum, base.sourceMaximum);
    expect(enlarged.sourceCandles,same(source));
    expect(enlarged.y(121),greaterThanOrEqualTo(0));
    expect(enlarged.height,base.height);
  });

  test('RSI and MACD have independent axes and do not stretch price ruler',(){
    final source = prices(List<double>.generate(40,(i)=>100+i.toDouble()));
    const v=ChartViewport(barWidth:10);
    final base=ChartPriceScale.visible(source,v,200,240);
    final output=ChartIndicatorAutoScale.include(
      base:base,candles:source,viewport:v,plotWidth:200,
      indicators:[
        const ChartIndicatorDefinition('rsi-14','RSI',14),
        const ChartIndicatorDefinition('macd','MACD',12),
      ],cache:ChartIndicatorSeriesCache());
    expect(identical(base,output),isTrue);
  });

  test('empty/offscreen source preserves verified axis without fabricated bars',(){
    final source=prices([100,101,102]);
    const viewport=ChartViewport(barWidth:10,scrollBars:-100);
    final base=ChartPriceScale.visible(source,viewport,200,240);
    final output=ChartIndicatorAutoScale.include(
      base:base,candles:source,viewport:viewport,plotWidth:200,
      indicators:[const ChartIndicatorDefinition('ema-9','EMA 9',9)],
      cache:ChartIndicatorSeriesCache());
    expect(output,same(base));
  });

  test('Replay autoscale never reads hidden future source candles',(){
    final source=_ReadGuard(prices([100,101,102,999999]));
    final visible=CandlePrefix(source,3);
    const v=ChartViewport(barWidth:10,rightMarginBars:0);
    final base=ChartPriceScale.visible(visible,v,180,200);
    source.read.clear();
    final output=ChartIndicatorAutoScale.include(
      base:base,candles:visible,viewport:v,plotWidth:180,
      indicators:[const ChartIndicatorDefinition('ema-9','EMA 9',9)],
      cache:ChartIndicatorSeriesCache());
    expect(source.read.every((i)=>i<3),isTrue);
    expect(output.maximum,lessThan(1000));
  });
}
