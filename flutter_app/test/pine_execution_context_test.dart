import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/pine_v6_language_runtime.dart';
import 'package:tradelab_flutter/chart/pine_execution_context.dart';
import 'package:tradelab_flutter/chart/pine_runtime_core.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main(){
  const source='''//@version=6
indicator("Context")
groupName = "Settings"
n = input.int(2, "Length", minval=1, maxval=5, group=groupName)
enabled = input.bool(true, "Enabled")
s = input.string("A", "Mode", options=["A","B"])
var int counter = 0
varip int ticks = 0
counter += 1
ticks += 1
plot(enabled ? n + counter : ticks)
plot(s == "B" ? syminfo.mintick : 0)
plot(time)
plot(volume[1])
plot(barstate.isconfirmed ? 1 : 0)
plot(timeframe.isminutes ? 1 : 0)''';
  final bars=[const TradeCandle(1,2,0,1,timestampMs:1000,volume:12),
    const TradeCandle(1,2,0,1,timestampMs:2000,volume:13)];
  test('input overrides, explicit context, var/varip closed bars, independent replay',(){
    final p=PineV6LanguageProgram.compile(source,context:PineExecutionContext(
      minTick:0.01,timeframePeriod:'60',overrides:{'Length':4,'Mode':'B'}));
    final r=p.newInstance(),other=p.newInstance();
    try{
      r.rebuild(bars,2);
      final expected=[[5,6],[0.01,0.01],[1000,2000],[null,12],[1,1],[1,1]];
      expect(r.outputs.map((p)=>p.values).toList(),expected);
      other.rebuild(bars,1);
      expect(other.outputs.first.values,[5]);
      r.rebuild(bars,1);r.rebuild(bars,2);
      expect(r.outputs.map((p)=>p.values).toList(),expected);
    }finally{r.close();other.close();}
  });
  test('map var and varip isolate state and reconstruct on rewind',(){
    const code='''//@version=6
indicator("Map isolation")
var map<int,float> m = map.new<int,float>()
varip map<int,float> n = map.new<int,float>()
old = map.put(m,1,close + bar_index)
oldN = map.put(n,1,bar_index)
plot(old)
plot(oldN)
plot(map.get(m,1))''';
    final p=PineV6LanguageProgram.compile(code);
    final a=p.newInstance(),b=p.newInstance();
    try{
      a.rebuild(bars,2);b.rebuild(bars,1);
      expect(a.outputs.map((p)=>p.values).toList(),[[null,1],[null,0],[1,2]]);
      expect(b.outputs.map((p)=>p.values).toList(),[[null],[null],[1]]);
      a.rebuild(bars,1);a.rebuild(bars,2);
      expect(a.outputs.map((p)=>p.values).toList(),[[null,1],[null,0],[1,2]]);
    }finally{a.close();b.close();}
  });
  test('session uses verified exchange offset and int casts truncate',(){
    const code='''//@version=6
indicator("Session")
s = input.session("0700-2000")
plot(not na(time(timeframe.period,s)) ? 1 : 0)
plot(int(-2.8))
plot(chart.right_visible_bar_time)''';
    final ts=DateTime.utc(2026,11,27,6).millisecondsSinceEpoch;
    final rows=[for(var i=0;i<3;i++)TradeCandle(1,2,0,1,timestampMs:ts+i*3600000)];
    final p=PineV6LanguageProgram.compile(code,context:PineExecutionContext(
      timeframePeriod:'60',fixedExchangeUtcOffsetMinutes:60,rightVisibleBarTime:ts+7200000));
    expect(p.evaluate(rows).map((p)=>p.values).toList(),[[1,1,1],[-2,-2,-2],List.filled(3,ts+7200000)]);
    final outside=[TradeCandle(1,2,0,1,timestampMs:ts-3600000)];
    expect(p.evaluate(outside).first.values,[0]);
    expect(()=>PineV6LanguageProgram.compile(code),throwsA(isA<PineRuntimeException>()));
  });
  test('invalid input override or missing verified context fails before evaluation',(){
    expect(()=>PineV6LanguageProgram.compile(source,context:PineExecutionContext(
      minTick:0.01,timeframePeriod:'60',overrides:{'Length':8})),throwsA(isA<PineRuntimeException>()));
    expect(()=>PineV6LanguageProgram.compile(source),throwsA(isA<PineRuntimeException>()));
  });
}
