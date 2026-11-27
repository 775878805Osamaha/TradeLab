import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/pine_v6_language_runtime.dart';
import 'package:tradelab_flutter/chart/pine_runtime_core.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

class _Poison extends ListBase<TradeCandle>{
  _Poison(this.data,this.cutoff);
  final List<TradeCandle> data;final int cutoff;
  @override int get length=>data.length;
  @override set length(int n)=>throw UnsupportedError('readonly');
  @override TradeCandle operator[](int i){if(i>=cutoff)throw StateError('Future read');return data[i];}
  @override void operator[]=(int i,TradeCandle v)=>throw UnsupportedError('readonly');
}
const source='''//@version=6
indicator("History and series")
plot(ta.barssince(close > open))
plot(ta.pivothigh(high,5,5))
plot(ta.pivotlow(low,5,5))
plot(ta.pivotlow(5,5))
plot(ta.highest(high,20)[1])
plot(ta.lowest(low,20)[1])
plot(math.sum(close,5)[1])
plot(ta.sma(close,20)[1])''';
void main(){
  final bars=<TradeCandle>[],ref=<List<double?>>[];
  setUpAll((){
    final bytes=File('test/fixtures/tradingview/pine-logs-TradeLab Reference Logs V2.csv').readAsBytesSync();
    expect(sha256.convert(bytes).toString(),'6a052a535dc4bf77d3687a10446e9572bdf523a3bc80e2fe728a2c290899da7f');
    final lines=const LineSplitter().convert(utf8.decode(bytes));
    expect(lines.length,5336);
    for(final l in lines.skip(1).take(5334)){
      final f=l.substring(l.indexOf(',"')+2,l.length-1).split(',');
      expect(f.length,26);
      bars.add(TradeCandle(double.parse(f[2]),double.parse(f[3]),double.parse(f[4]),double.parse(f[5]),timestampMs:int.parse(f[1]),volume:double.parse(f[6])));
      ref.add(f.skip(7).map((s)=>s=='NaN'?null:double.parse(s)).toList());
    }
  });
  test('Pine interpreter against all V2 pivot/barssince columns and shifted rolling results',(){
    final p=PineV6LanguageProgram.compile(source);expect(p.legacy,isNull);
    final v=p.evaluate(bars).map((p)=>p.values).toList();
    for(var i=0;i<bars.length;i++){
      final wanted=<double?>[ref[i][14],ref[i][12],ref[i][13],ref[i][13],
        i==0?null:ref[i-1][17],i==0?null:ref[i-1][18],
        i<5?null:bars.sublist(i-5,i).fold<double>(0,(a,b)=>a+b.close),
        i<20?null:bars.sublist(i-20,i).fold<double>(0,(a,b)=>a+b.close)/20];
      for(var c=0;c<wanted.length;c++){
        if(wanted[c]==null){expect(v[c][i],isNull,reason:'col $c bar $i');}
        else{expect(v[c][i],closeTo(wanted[c]!,1e-6),reason:'col $c bar $i');}
      }
    }
  });
  test('Pine replay 3000 -> 1000 -> 3000 with poison future, exact outputs',(){
    final p=PineV6LanguageProgram.compile(source);
    final direct=p.evaluate(bars);
    final r=p.newInstance();
    try{
      for(final n in [3000,1000,3000]){
        r.rebuild(_Poison(bars,n),n);
        for(var c=0;c<direct.length;c++)expect(r.outputs[c].values,direct[c].values.take(n).toList());
      }
    }finally{r.close();}
  });
  test('first bool history is false and numeric history remains na',(){
    const code='''//@version=6
indicator("History bool")
bool positive = close > open
plot(positive[1] ? 1 : 0)
plot(close[1])
plot(str.contains("a","a")[1] ? 1 : 0)''';
    final p=PineV6LanguageProgram.compile(code);
    final v=p.evaluate([const TradeCandle(1,3,0,2),const TradeCandle(2,3,0,1)]);
    expect(v[0].values,[0,1]);expect(v[1].values,[null,2]);expect(v[2].values,[0,1]);
  });
  test('Pine pivotlow left/right ties and unverified high tie fails explicitly',(){
    const low='''//@version=6
indicator("Low ties")
plot(ta.pivotlow(low,2,2))''';
    List<TradeCandle> candles(List<double> xs)=>[for(final x in xs)TradeCandle(x+1,x+2,x,x+1)];
    expect(PineV6LanguageProgram.compile(low).evaluate(candles([5,1,1,3,5])).single.values,[null,null,null,null,1]);
    expect(PineV6LanguageProgram.compile(low).evaluate(candles([5,3,1,1,5])).single.values,[null,null,null,null,null]);
    const high='''//@version=6
indicator("High ties")
plot(ta.pivothigh(high,2,2))''';
    expect(()=>PineV6LanguageProgram.compile(high).evaluate(candles([1,5,5,2,1])),
      throwsA(isA<PineRuntimeException>().having((e)=>e.code,'code','unverified_pivot_tie')));
  });
}
