import 'dart:collection';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/candle_prefix.dart';
import 'package:tradelab_flutter/chart/chart_heikin_ashi.dart';
import 'package:tradelab_flutter/chart/pine_runtime_core.dart';
import 'package:tradelab_flutter/chart/pine_indicator_seed_candidates.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

class _PoisonedBars extends ListBase<TradeCandle>{
  _PoisonedBars(this.data,this.cutoff);
  final List<TradeCandle> data;
  final int cutoff;
  int reads=0;
  @override int get length=>data.length;
  @override set length(int value)=>throw UnsupportedError('readonly');
  @override TradeCandle operator[](int i){
    if(i>=cutoff)throw StateError('future candle read: $i');
    reads++;
    return data[i];
  }
  @override void operator[]=(int i,TradeCandle value)=>throw UnsupportedError('readonly');
}

void main(){
  test('existing HA calculator uses owner-reported first-bar seed without changing display',(){
    final raw=[const TradeCandle(100,110,95,105),const TradeCandle(105,112,101,111)];
    final ha=ChartHeikinAshi.build(raw);
    expect([ha[0].open,ha[0].high,ha[0].low,ha[0].close],[102.5,110,95,102.5]);
    expect([ha[1].open,ha[1].high,ha[1].low,ha[1].close],[102.5,112,101,107.25]);
    final append=ChartHeikinAshi.extendVerified(ha.take(1).toList(),raw.skip(1).toList());
    expect([append.single.open,append.single.close],[ha[1].open,ha[1].close]);
  });
  test('SMA-seeded EMA first values and leading na; interior na not asserted',(){
    final b=PineRuntimeBudget(),ema=PineSmaSeededEma(PineRuntimeBudget(),3);
    expect([for(final x in <double?>[null,1,2,3,4,5])ema.step(x)],[null,null,null,2,3,4]);
    expect(()=>ema.step(null),throwsA(isA<PineRuntimeException>().having(
      (e)=>e.code,'code','unverified_ema_na')));
    ema.budget.stop();
    b.stop();
  });
  test('MACD(12,26,9) owner-reported exact warm-up indices on constant data',(){
    final b=PineRuntimeBudget();
    final state=PineSeededMacd(b,fast:12,slow:26,signal:9);
    final out=[for(var i=0;i<40;i++)state.step(100)];
    expect(out.indexWhere((x)=>x.line!=null),25);
    expect(out.indexWhere((x)=>x.signal!=null),33);
    expect(out.indexWhere((x)=>x.histogram!=null),33);
    expect(out[33],(line:0.0,signal:0.0,histogram:0.0));
    b.stop();
  });
  test('MACD separate fast/slow/signal arithmetic on changing samples',(){
    final b=PineRuntimeBudget(),m=PineSeededMacd(PineRuntimeBudget(),fast:2,slow:3,signal:2);
    final out=[for(final x in <double>[1,2,3,4,10])m.step(x)];
    expect(out[2].line,closeTo(.5,1e-12));
    expect(out[2].signal,isNull);
    expect(out[3].histogram,closeTo(0,1e-12));
    expect(out[4].line,closeTo(4/3,1e-12));
    expect(out[4].signal,closeTo(19/18,1e-12));
    expect(out[4].histogram,closeTo(5/18,1e-12));
    b.stop();
  });
  test('Supertrend first bar zero, bars 1..8 na, ATR-backed bar 9 and direction flips',(){
    final b=PineRuntimeBudget(),s=PineSupertrendCandidate(PineRuntimeBudget(),factor:3,length:10);
    final out=[for(var i=0;i<10;i++)s.step(const TradeCandle(10,11,9,10))];
    expect(out.first,(value:0.0,direction:1));
    for(var i=1;i<9;i++){expect(out[i],(value:null,direction:1),reason:'bar $i');}
    expect(out[9],(value:16.0,direction:1));
    final up=s.step(const TradeCandle(20,21,19,20));
    expect(up.value,closeTo(11.3,1e-12));expect(up.direction,-1);
    final down=s.step(const TradeCandle(5,6,4,5));
    expect(down.value,closeTo(17.63,1e-12));expect(down.direction,1);
    s.budget.stop();b.stop();
  });
  test('synthetic-only 3000 to 1000 to 3000 prefix/seek with poisoned future',(){
    // This is deliberately not the TradingView file. Nothing here proves
    // a reference match or seeds a candidate with reference output.
    final raw=[for(var i=0;i<5335;i++)TradeCandle(
      100+(i%17).toDouble(),102+(i%17).toDouble(),
      99+(i%17).toDouble(),101+(i%17).toDouble())];
    List<Object?> run(List<TradeCandle> source,int cutoff){
      final b=PineRuntimeBudget();
      final ema=PineSmaSeededEma(b,26),macd=PineSeededMacd(b,fast:12,slow:26,signal:9);
      final trend=PineSupertrendCandidate(b,factor:3,length:10);
      final prefix=CandlePrefix(source,cutoff);
      final ha=ChartHeikinAshi.build(prefix);
      try{return [for(var i=0;i<cutoff;i++)(
        ema.step(prefix[i].close),macd.step(prefix[i].close),trend.step(prefix[i]),
        ha[i].open,ha[i].high,ha[i].low,ha[i].close)];}
      finally{b.stop();}
    }
    final direct=run(raw,raw.length).take(3000).toList();
    final guard=_PoisonedBars(raw,3000);
    expect(run(guard,3000),direct);
    expect(run(_PoisonedBars(raw,1000),1000),direct.take(1000));
    expect(run(_PoisonedBars(raw,3000),3000),direct);
    expect(guard.reads,greaterThan(0));
  });
}
