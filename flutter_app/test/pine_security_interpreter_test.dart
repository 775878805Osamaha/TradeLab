import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/pine_v6_language_runtime.dart';
import 'package:tradelab_flutter/chart/pine_execution_context.dart';
import 'package:tradelab_flutter/chart/pine_security_dispatch.dart';
import 'package:tradelab_flutter/chart/pine_runtime_core.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

class _Poison extends ListBase<TradeCandle>{
  _Poison(this.data,this.cutoff);
  final List<TradeCandle> data;final int cutoff;
  @override int get length=>data.length;
  @override set length(int value)=>throw UnsupportedError('readonly');
  @override TradeCandle operator[](int i){if(i>=cutoff)throw StateError('future read');return data[i];}
  @override void operator[]=(int i,TradeCandle v)=>throw UnsupportedError('readonly');
}
void main(){
  const ha='''//@version=6
indicator("HA context")
t = ticker.heikinashi(ticker.standard(syminfo.tickerid))
[o,h,l,c] = request.security(t,timeframe.period,[open,high,low,close],lookahead=barmerge.lookahead_off)
plot(o)
plot(h)
plot(l)
plot(c)
plot(close)''';
  test('actual V2 HA via Pine security, original OHLC unchanged and exact replay',(){
    final bytes=File('test/fixtures/tradingview/pine-logs-TradeLab Reference Logs V2.csv').readAsBytesSync();
    expect(sha256.convert(bytes).toString(),'6a052a535dc4bf77d3687a10446e9572bdf523a3bc80e2fe728a2c290899da7f');
    final bars=<TradeCandle>[],ref=<List<double?>>[];
    final lines=const LineSplitter().convert(utf8.decode(bytes));
    expect(lines.length,5336);
    for(final l in lines.skip(1).take(5334)){
      final f=l.substring(l.indexOf(',"')+2,l.length-1).split(',');
      bars.add(TradeCandle(double.parse(f[2]),double.parse(f[3]),double.parse(f[4]),double.parse(f[5]),timestampMs:int.parse(f[1]),volume:double.parse(f[6])));
      ref.add(f.skip(7).map((x)=>x=='NaN'?null:double.parse(x)).toList());
    }
    final p=PineV6LanguageProgram.compile(ha,context:PineExecutionContext(tickerId:'TVC:GOLD',timeframePeriod:'60'));
    final v=p.evaluate(bars).map((x)=>x.values).toList();
    for(var c=0;c<4;c++){
      int compared=0;double max=0;
      for(var i=0;i<bars.length;i++){
        if(i>=5273&&i<=5290)continue;
        final a=v[c][i],b=ref[i][c+8];
        expect(a==null,b==null,reason:'na mask $c/$i');
        if(a!=null&&b!=null){final e=(a-b).abs();if(e>max)max=e;expect(e,lessThanOrEqualTo(1e-6),reason:'$c/$i');}
        compared++;
      }
      expect(compared,5316);
      print('TV_HA_SECURITY '+jsonEncode({'column':c,'compared':compared,'maxAbs':max,'excluded':18}));
    }
    expect(v[4],bars.map((b)=>b.close).toList());
    final r=p.newInstance();
    try{for(final n in [3000,1000,3000]){
      r.rebuild(_Poison(bars,n),n);
      for(var c=0;c<5;c++)expect(r.outputs[c].values,v[c].take(n).toList());
    }}finally{r.close();}
  });
  final bars=[for(var i=0;i<6;i++)TradeCandle(i+1.0,i+2.0,i.toDouble(),i+1.0,timestampMs:i*60000)];
  const htf='''//@version=6
indicator("HTF")
plot(request.security(syminfo.tickerid,"2",close,lookahead=barmerge.lookahead_off))
plot(request.security(syminfo.tickerid,"2",close[1],lookahead=barmerge.lookahead_on))''';
  test('higher TF exposes completed bucket only; previous lookahead_on is causal',(){
    final p=PineV6LanguageProgram.compile(htf,context:PineExecutionContext(tickerId:'EX:X',timeframePeriod:'1'));
    final v=p.evaluate(bars).map((x)=>x.values).toList();
    expect(v,[[null,2,2,4,4,6],[null,null,2,2,4,4]]);
    final r=p.newInstance();
    try{for(final n in [5,2,5]){
      r.rebuild(_Poison(bars,n),n);
      for(var c=0;c<2;c++)expect(r.outputs[c].values,v[c].take(n).toList());
    }}finally{r.close();}
    expect(()=>PineV6LanguageProgram.compile(htf.replaceAll('close[1]','close'),context:PineExecutionContext(tickerId:'EX:X',timeframePeriod:'1')),throwsA(isA<PineRuntimeException>()));
    expect(()=>p.evaluate([bars[0],bars[2]]),throwsA(isA<PineRuntimeException>()));
  });
  test('external same timeframe reads only explicitly closed timestamp; gap vs unknown',(){
    const script='''//@version=6
indicator("External")
[h,l] = request.security("EX:Y",timeframe.period,[high,low])
plot(h)
plot(l)''';
    int cutoff=0;
    final p=PineV6LanguageProgram.compile(script,context:PineExecutionContext(tickerId:'EX:X',timeframePeriod:'1',
      externalLookup:(symbol,tf,stamp,through){
        expect(symbol,'EX:Y');expect(tf,'1');expect(through,stamp+60000);
        expect(through,lessThanOrEqualTo(cutoff*60000));
        if(stamp==60000)return const PineExternalBar(null);
        return PineExternalBar(TradeCandle(10,12,8,11,timestampMs:stamp));
      }));
    final r=p.newInstance();
    try{
      cutoff=3;r.rebuild(_Poison(bars,3),3);
      expect(r.outputs.map((x)=>x.values).toList(),[[12,12,12],[8,8,8]]);
      cutoff=1;r.rebuild(_Poison(bars,1),1);
      expect(r.outputs.first.values,[12]);
    }finally{r.close();}
    final unknown=PineV6LanguageProgram.compile(script,context:PineExecutionContext(tickerId:'EX:X',timeframePeriod:'1',externalLookup:(symbol,tf,stamp,through)=>null));
    expect(()=>unknown.evaluate(bars),throwsA(isA<PineRuntimeException>()));
  });
}
