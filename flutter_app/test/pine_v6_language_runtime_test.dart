import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/pine_runtime_core.dart';
import 'package:tradelab_flutter/chart/chart_indicator_library.dart';
import 'package:tradelab_flutter/chart/chart_indicator_engine.dart';
import 'package:tradelab_flutter/chart/pine_subset_program.dart';
import 'package:tradelab_flutter/chart/pine_v6_language_runtime.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

List<TradeCandle> bars(List<double> closes) => [
  for(final close in closes) TradeCandle(close,close+1,close-1,close),
];
class ObservedBars extends ListBase<TradeCandle> {
  ObservedBars(this.data);
  final List<TradeCandle> data;
  final List<int> reads=[];
  @override int get length=>data.length;
  @override set length(int n)=>throw UnsupportedError('readonly');
  @override TradeCandle operator[](int i){reads.add(i);return data[i];}
  @override void operator[]=(int i,TradeCandle value)=>
      throw UnsupportedError('readonly');
}
List<double?> single(String source,List<TradeCandle> candles) =>
    PineV6LanguageProgram.compile(source).evaluate(candles).single.values;

void main(){
  test('closed-bar var initializes once and increments once each bar',(){
    const code='''//@version=6
indicator("Counter")
var int count = 0
count += 1
plot(count)''';
    expect(single(code,bars([10,20,30,40,50])),[1,2,3,4,5]);
    const opening='''//@version=6
indicator("First")
var float opening = close
plot(opening)''';
    expect(single(opening,bars([10,20,30])),[10,10,10]);
  });

  test('varip is persistent across closed Replay candles, not ticks',(){
    const code='''//@version=6
indicator("Closed varip")
varip int count = 0
count += 1
plot(count)''';
    expect(single(code,bars([2,4,6,8])),[1,2,3,4]);
  });

  test('if/else branches update existing persistent var',(){
    const code='''//@version=6
indicator("Conditional")
var int count = 0
if close > 3
    count += 2
else
    count += 1
plot(count)''';
    expect(single(code,bars([1,4,2,5])),[1,3,4,6]);
  });

  test('for sums real historical x[i], early history is na not future',(){
    const code='''//@version=6
indicator("Loop historical sum")
var float total = 0
for i = 0 to 2
    total += nz(close[i], 0)
plot(total)''';
    expect(single(code,bars([1,2,3])),[1,4,10]);
  });

  test('break and continue execute in for and while loops',(){
    const code='''//@version=6
indicator("For")
int sum = 0
for i = 0 to 5
    if i == 2
        continue
    if i == 4
        break
    sum += i
plot(sum)''';
    expect(single(code,bars([1,2])),[4,4]);
    const whileCode='''//@version=6
indicator("While")
int i = 0
int sum = 0
while i < 5
    i += 1
    if i == 3
        continue
    sum += i
plot(sum)''';
    expect(single(whileCode,bars([1,2])),[12,12]);
  });

  test('infinite while and large for terminate with typed error',(){
    const forever='''//@version=6
indicator("Loop budget")
while true
    close
plot(close)''';
    final program=PineV6LanguageProgram.compile(forever);
    expect(()=>program.evaluate(bars([1]),maxLoopIterations:5),
        throwsA(isA<PineRuntimeException>().having(
            (e)=>e.code,'code','loop_limit')));
    const longFor='''//@version=6
indicator("Large loop")
int count = 0
for i = 0 to 1000
    count += 1
plot(count)''';
    expect(()=>PineV6LanguageProgram.compile(longFor).evaluate(
        bars([1]),maxLoopIterations:10),
        throwsA(isA<PineRuntimeException>().having(
            (e)=>e.code,'code','loop_limit')));
  });

  test('per-call ta.sma uses independent history and conditional calls '
      'only advance when invoked',(){
    const code='''//@version=6
indicator("Conditional SMA")
smooth(float src) =>
    ta.sma(src, 2)
float result = na
if close > 3
    result := smooth(close)
plot(result)''';
    expect(single(code,bars([1,4,5,1,6])),[
      null,null,4.5,null,5.5,
    ]);
  });

  test('two instances of the exact same var source never share state',(){
    const code='''//@version=6
indicator("Independent var")
var int count = 0
count += 1
plot(count)''';
    final program=PineV6LanguageProgram.compile(code);
    final a=program.newInstance(),b=program.newInstance();
    for(final bar in bars([10,20,30,40]))a.advance(bar);
    for(final bar in bars([100,200]))b.advance(bar);
    expect(a.persistentValue('count'),4);
    expect(b.persistentValue('count'),2);
    expect(a.outputs.single.values,[1,2,3,4]);
    expect(b.outputs.single.values,[1,2]);
    a.close();b.close();
  });

  test('Replay 50->20->30 equals direct 30 and cannot read future',(){
    const code='''//@version=6
indicator("Replay var")
var int count = 0
if close > open
    count += 2
else
    count += 1
plot(count)''';
    final original=ObservedBars(bars([
      for(var i=0;i<100;i++)i.toDouble()+1,
    ]));
    final program=PineV6LanguageProgram.compile(code);
    final replay=program.newInstance();
    replay.rebuild(original,50);
    expect(original.reads,everyElement(lessThan(50)));
    original.reads.clear();
    replay.rebuild(original,20);
    expect(original.reads,everyElement(lessThan(20)));
    original.reads.clear();
    replay.rebuild(original,30);
    expect(original.reads,everyElement(lessThan(30)));
    final fresh=program.newInstance()..rebuild(original,30);
    expect(replay.outputs.single.values,fresh.outputs.single.values);
    expect(replay.persistentValue('count'),fresh.persistentValue('count'));
    expect(replay.completedBars,30);
  });

  test('unsupported function refuses execution before reading bars',(){
    const source='''//@version=6
indicator("Denied")
plot(request.security("BINANCE:BTCUSDT", "D", close))''';
    expect(()=>PineV6LanguageProgram.compile(source),
        throwsA(isA<PineRuntimeException>()));
  });

  test('legacy numeric programs still use old engine with identical plots',(){
    final fixtures=[
      'indicator("MA")\nplot(ta.sma(close, 3))',
      'indicator("EMA")\nn = input.int(2, "Length")\n'
          'plot(ta.ema(close, n))',
      'indicator("Price")\nplot(close[1])\n'
          'plot(math.abs(close-open))',
    ];
    final source=bars([2,3,5,7,11,13]);
    for(final script in fixtures){
      final original=PineSubsetProgram.compile(script).evaluate(source);
      final updated=PineV6LanguageProgram.compile(script).evaluate(source);
      expect(updated.length,original.length);
      for(var i=0;i<original.length;i++){
        expect(updated[i].values,original[i].values);
      }
    }
  });
  test('switch last-value expression inside user function follows selected arm',(){
    const code='''//@version=6
indicator("Switch")
choose(int value) =>
    switch value
        0 => 7
        1 => 9
        => 11
plot(choose(bar_index))''';
    expect(single(code,bars([1,2,3,4])),[7,9,11,11]);
  });

  test('Stage 3a saved script is admitted to chart and executed with real OHLC',(){
    const saved=ChartSavedIndicatorScript(
        id:'script-stage3',name:'Var Counter',
        source:'''//@version=6
indicator("Counter", overlay=true)
var int count = 0
count += 1
plot(count)''');
    final definition=saved.supportedIndicator();
    expect(definition,isNotNull,reason:saved.compileError);
    expect(definition!.kind,ChartIndicatorKind.pine);
    expect(definition.pineOverlay,isTrue);
    final plotted=ChartIndicatorEngine.compute(bars([10,11,12]),definition);
    expect(plotted.plots.single.values,[1,2,3]);
    expect(saved.compileError,isNull);
  });

  test('legacy invalid-period source is not admitted via Stage 3a fallback',(){
    const saved=ChartSavedIndicatorScript(
        id:'script-rejected',name:'Bad SMA',
        source:'''//@version=6
indicator("Bad", overlay=true)
plot(ta.sma(close,501))''');
    expect(saved.supportedIndicator(),isNull);
    expect(saved.compileError,isNotNull);
  });

  test('two independent Replay sessions never leak var state across rebuilds',(){
    const code='''//@version=6
indicator("Session isolation")
var int count = 0
count += 1
plot(count)''';
    final program=PineV6LanguageProgram.compile(code);
    final source=bars([for(var i=0;i<10;i++)i.toDouble()]);
    final first=program.newInstance()..rebuild(source,5);
    final second=program.newInstance()..rebuild(source,2);
    first.rebuild(source,1);
    expect(first.persistentValue('count'),1);
    expect(second.persistentValue('count'),2);
    expect(second.outputs.single.values,[1,2]);
    final fresh=program.newInstance()..rebuild(source,2);
    expect(second.outputs.single.values,fresh.outputs.single.values);
  });

  test('two written UDF call sites keep separate persistent var histories',(){
    const script='''//@version=6
indicator("Separate UDF vars")
accumulate(float amount) =>
    var float total = 0
    total += amount
    total
first = accumulate(1)
second = accumulate(2)
plot(first)
plot(second)''';
    final plots=PineV6LanguageProgram.compile(script)
        .evaluate(bars([2,4,6]));
    expect(plots[0].values,[1,2,3]);
    expect(plots[1].values,[2,4,6]);
  });

  test('separate written ta.sma calls inside one UDF have disjoint trails',(){
    const script='''//@version=6
indicator("Separate SMA sites")
smooth(float x) =>
    ta.sma(x,2)
plot(smooth(close))
plot(smooth(close*2))''';
    final plots=PineV6LanguageProgram.compile(script)
        .evaluate(bars([2,4,6]));
    expect(plots[0].values,[null,3,5]);
    expect(plots[1].values,[null,6,10]);
  });

}
