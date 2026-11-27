import 'dart:collection';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/pine_broker_emulator.dart';
import 'package:tradelab_flutter/chart/pine_v6_language_runtime.dart';
import 'package:tradelab_flutter/chart/pine_runtime_core.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

PineBrokerConfig config(bool close)=>PineBrokerConfig(initialCapital:10000,
  defaultQty:1,pointValue:1,minTick:1,processOnClose:close);
TradeCandle bar(int i,double o,double h,double l,double c)=>TradeCandle(o,h,l,c,timestampMs:i*60000);
String script(bool close)=>'''//@version=6
strategy("Broker test", pyramiding=0, process_orders_on_close:$close, initial_capital=10000)
if bar_index == 0
    strategy.entry("L",strategy.long)
    strategy.exit("X","L",stop=95,limit=105)
plot(strategy.position_size)
plot(strategy.position_avg_price)
plot(strategy.closedtrades)
plot(strategy.closedtrades.exit_price(0))''';
class _Poison extends ListBase<TradeCandle>{
  _Poison(this.data,this.cutoff);
  final List<TradeCandle> data;final int cutoff;
  @override int get length=>data.length;
  @override set length(int n)=>throw UnsupportedError('readonly');
  @override TradeCandle operator[](int i){if(i>=cutoff)throw StateError('future read');return data[i];}
  @override void operator[]=(int i,TradeCandle v)=>throw UnsupportedError('readonly');
}
void main(){
  test('BR04 no retroactive bracket: on-close versus next open and observable timing',(){
    final bars=[bar(0,100,110,90,100),bar(1,103,104,101,102),bar(2,102,106,99,104)];
    for(final close in [true,false]){
      final p=PineV6LanguageProgram.compile(script(close),brokerConfig:config(close));
      final r=p.newInstance();
      try{
        r.rebuild(bars,3);
        final v=r.outputs.map((x)=>x.values).toList();
        expect(v,[[0,1,0],[null,close?100:103,null],[0,0,1],[null,null,105]]);
        final t=r.brokerSnapshot!.closedTrades.single;
        expect(t.entryPrice,close?100:103);expect(t.exitPrice,105);
        expect(t.entryBar,close?0:1);expect(t.exitBar,2);
        expect(t.profit,close?5:2);
        final first=r.brokerSnapshot!;
        r.rebuild(_Poison(bars,1),1);
        expect(r.brokerSnapshot!.closedTrades,isEmpty);
        r.rebuild(_Poison(bars,3),3);
        expect(r.brokerSnapshot!.closedTrades,first.closedTrades);
        expect(r.brokerSnapshot!.fills,first.fills);
      }finally{r.close();}
    }
  });
  test('BR01 BR03 long and short paths and gap fills',(){
    for(final isLong in [true,false]){
      final source=script(true).replaceAll('strategy.long',isLong?'strategy.long':'strategy.short')
        .replaceAll('stop=95,limit=105',isLong?'stop=95,limit=105':'stop=105,limit=95');
      final p=PineV6LanguageProgram.compile(source,brokerConfig:config(true));
      for(final pair in [(bar(1,100,107,90,101),isLong?105:105),
        (bar(1,100,110,93,101),isLong?95:95),(bar(1,90,92,88,90),90),(bar(1,110,112,108,110),110)]){
        final r=p.newInstance();
        try{r.rebuild([bar(0,100,101,99,100),pair.$1],2);
          final t=r.brokerSnapshot!.closedTrades.single;expect(t.exitPrice,pair.$2);
          expect(t.profit,(pair.$2-100)*(isLong?1:-1));
          expect(r.brokerSnapshot!.fills.length,2);
        }finally{r.close();}
      }
    }
  });
  test('BR02 equal-distance ambiguous path rejects; failed replay preserves prior state',(){
    final p=PineV6LanguageProgram.compile(script(true),brokerConfig:config(true));
    final r=p.newInstance();
    try{
      final bars=[bar(0,100,101,99,100),bar(1,100,110,90,100)];
      r.rebuild(bars,1);
      expect(()=>r.rebuild(bars,2),throwsA(isA<PineRuntimeException>().having((e)=>e.code,'code','unsupported_broker_tie')));
      expect(r.completedBars,1);expect(r.brokerSnapshot!.size,1);
    }finally{r.close();}
  });
  test('BR05 same direction no add, reversal isolated, explicit unsupported config rejects',(){
    const src='''//@version=6
strategy("Reverse", pyramiding=0, process_orders_on_close=true, initial_capital=10000)
if bar_index < 2
    strategy.entry("L",strategy.long)
if bar_index == 2
    strategy.entry("S",strategy.short,qty=2)
plot(strategy.position_size)''';
    final p=PineV6LanguageProgram.compile(src,brokerConfig:config(true));
    final r=p.newInstance(),other=p.newInstance();
    try{
      final rows=[bar(0,100,101,99,100),bar(1,101,102,100,101),bar(2,102,103,101,102)];
      r.rebuild(rows,3);other.rebuild(rows,1);
      expect(r.outputs.single.values,[0,1,1]);expect(r.brokerSnapshot!.size,-2);
      expect(r.brokerSnapshot!.closedTrades.single.profit,2);
      expect(other.brokerSnapshot!.size,1);expect(other.brokerSnapshot!.closedTrades,isEmpty);
      expect(()=>PineV6LanguageProgram.compile(src.replaceAll('pyramiding=0','pyramiding=2'),brokerConfig:config(true)),throwsA(isA<PineRuntimeException>()));
      expect(()=>PineV6LanguageProgram.compile(src),throwsA(isA<PineRuntimeException>()));
    }finally{r.close();other.close();}
  });
  test('BR06 bracket modification, wrong entry ID ignored, unsupported partial exit gated',(){
    final b=PineBrokerEmulator(config(true),PineRuntimeBudget());
    b.beginBar(0,bar(0,100,101,99,100));b.entry('L',PineBrokerDirection.long,1);
    b.exit('X','wrong',95,105);b.endBar();
    expect(b.snapshot.pendingExit,isNull);
    b.beginBar(1,bar(1,100,101,99,100));b.exit('X','L',95,110);b.exit('X','L',98,110);b.endBar();
    b.beginBar(2,bar(2,100,103,97,99));b.endBar();
    expect(b.snapshot.closedTrades.single.exitPrice,98);
    expect(()=>PineV6LanguageProgram.compile(script(true).replaceAll('stop=95','qty=0.5,stop=95'),brokerConfig:config(true)),throwsA(isA<PineRuntimeException>()));
  });
}
