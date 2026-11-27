import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/pine_v6_language_runtime.dart';
import 'package:tradelab_flutter/chart/pine_subset_program.dart';
import 'dart:typed_data';
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
indicator("Tuple indicators")
[m,s,h] = ta.macd(close,12,26,9)
[dp,dm,a] = ta.dmi(14,14)
[st,d] = ta.supertrend(3.0,10)
plot(m)
plot(s)
plot(h)
plot(dp)
plot(dm)
plot(a)
plot(st)
plot(d)''';
void main(){
  final bars=<TradeCandle>[],ref=<List<double?>>[];
  setUpAll((){
    final bytes=File('test/fixtures/tradingview/pine-logs-TradeLab Reference Logs V2.csv').readAsBytesSync();
    expect(sha256.convert(bytes).toString(),'6a052a535dc4bf77d3687a10446e9572bdf523a3bc80e2fe728a2c290899da7f');
    final lines=const LineSplitter().convert(utf8.decode(bytes));expect(lines.length,5336);
    for(final l in lines.skip(1).take(5334)){
      final f=l.substring(l.indexOf(',"')+2,l.length-1).split(',');
      expect(f.length,26);
      bars.add(TradeCandle(double.parse(f[2]),double.parse(f[3]),double.parse(f[4]),double.parse(f[5]),timestampMs:int.parse(f[1]),volume:double.parse(f[6])));
      ref.add(f.skip(7).map((s)=>s=='NaN'?null:double.parse(s)).toList());
    }
  });
  test('real Pine tuple interpreter, MACD/DMI/Supertrend V2 exact masks and values',(){
    final p=PineV6LanguageProgram.compile(source);expect(p.legacy,isNull);
    final v=p.evaluate(bars).map((p)=>p.values).toList();
    final names=['macdL','macdS','macdH','diP','diM','adx','stV','stD'];
    for(var c=0;c<8;c++){
      int na=0,bad=0;double maxError=0;int? maxIndex;
      for(var i=0;i<bars.length;i++){
        final x=v[c][i],y=ref[i][c];
        if((x==null)!=(y==null)){na++;continue;}
        if(x==null||y==null)continue;
        final e=(x-y).abs();if(maxIndex==null||e>maxError){maxIndex=i;maxError=e;}
        if(e>1e-6)bad++;
      }
      print('TV_V2_INTERPRETER '+jsonEncode({'name':names[c],'rows':bars.length,'na_mismatches':na,'numeric_mismatches':bad,'max_abs_error':maxError,'max_index':maxIndex}));
      expect(na,0,reason:names[c]);expect(bad,0,reason:names[c]);
    }
    expect([for(final c in [0,1,2,3,4,5,6])v[c].indexWhere((x)=>x!=null)],[25,33,33,14,14,27,0]);
    expect(v[6][0],0);expect(v[7][0],1);
    expect(v[6].sublist(1,9),List<double?>.filled(8,null));
  });
  test('tuple interpreter replay 3000 to 1000 to 3000 and future poison',(){
    final p=PineV6LanguageProgram.compile(source),direct=p.evaluate(bars),r=p.newInstance();
    try{
      for(final n in [3000,1000,3000]){
        r.rebuild(_Poison(bars,n),n);
        for(var c=0;c<direct.length;c++)expect(r.outputs[c].values,direct[c].values.take(n).toList());
      }
    }finally{r.close();}
  });
  test('EMA general SMA seed vs unchanged standalone legacy, V2 independent oracle',(){
    for(final length in [3,20,50,200]){
      final script='//@version=6\nindicator("EMA compatibility")\nplot(ta.ema(close,$length))';
      final old=PineV6LanguageProgram.compile(script),fresh=PineV6LanguageProgram.compile(script,preferGeneral:true);
      expect(old.legacy,isNotNull);expect(fresh.legacy,isNull);
      final legacy=old.evaluate(bars).single.values,v=fresh.evaluate(bars).single.values;
      final standalone=PineSubsetProgram.compile(script).evaluateIncrementally(bars).single.values;
      final legacyBits=ByteData(8),standaloneBits=ByteData(8);
      for(var i=0;i<bars.length;i++){
        expect(legacy[i]==null,standalone[i]==null);
        if(legacy[i]!=null){
          legacyBits.setFloat64(0,legacy[i]!);standaloneBits.setFloat64(0,standalone[i]!);
          expect(legacyBits.getUint64(0),standaloneBits.getUint64(0),reason:'legacy bit pattern $length/$i');
        }
      }
      const warmupEnd={3:21,20:179,50:451,200:1872};
      double? expected;int mask=0,changed=0,last=-1;double sum=0;
      for(var i=0;i<bars.length;i++){
        final x=bars[i].close;
        if(i<length){sum+=x;if(i==length-1)expected=sum/length;}
        else{expected=(2*x+(length-1)*expected!)/(length+1);}
        if(expected==null){expect(v[i],isNull);}else{expect(v[i],closeTo(expected,1e-6));}
        if((legacy[i]==null)!=(v[i]==null)){mask++;last=i;}
        else if(legacy[i]!=null&&v[i]!=null&&(legacy[i]!-v[i]!).abs()>1e-6){changed++;last=i;}
      }
      expect(mask,length-1);
      // Fixed per-length V2 boundary, measured on prior CI, not derived from the candidate.
      final boundary=warmupEnd[length]!;
      expect(last,lessThan(boundary));
      for(var i=boundary;i<bars.length;i++)expect(v[i],closeTo(legacy[i]!,1e-6));
      print('EMA_COMPAT '+jsonEncode({'length':length,'na_mismatch':mask,'numeric_over_1e6':changed,'last_affected_index':last,'affected':mask+changed}));
    }
    const code='//@version=6\nindicator("Leading na")\nplot(ta.ema(close[1],3))';
    final v=PineV6LanguageProgram.compile(code,preferGeneral:true).evaluate(bars.take(8).toList()).single.values;
    expect(v.take(3),[null,null,null]);expect(v[3],closeTo((bars[0].close+bars[1].close+bars[2].close)/3,1e-6));
  });
  test('default general AST EMA and explicit general route both use SMA',(){
    const code='//@version=6\nindicator("AST EMA compatibility")\nf(float x) => ta.ema(x,3)\nplot(f(close))';
    final candles=[for(final x in [2.0,4.0,8.0,16.0]) TradeCandle(x,x+1,x-1,x)];
    final old=PineV6LanguageProgram.compile(code);
    final seeded=PineV6LanguageProgram.compile(code,preferGeneral:true);
    expect(old.legacy,isNull);
    expect(seeded.legacy,isNull);
    final v=old.evaluate(candles).single.values;
    expect(seeded.evaluate(candles).single.values,v);
    expect(v.take(2),[null,null]);
    expect(v[2],closeTo(14/3,1e-6));
    expect(v[3],closeTo((14/3+16)/2,1e-6));
  });
  test('real Pine tuple-returning UDF and nested independent call paths',(){
    const code='''//@version=6
indicator("Tuple function")
f(float x) =>
    [x, x + 1]
[a,b] = f(close)
plot(a)
plot(b)''';
    final v=PineV6LanguageProgram.compile(code).evaluate(bars.take(10).toList());
    expect(v[0].values,bars.take(10).map((x)=>x.close).toList());
    expect(v[1].values,bars.take(10).map((x)=>x.close+1).toList());
    const nested='''//@version=6
indicator("Nested call paths")
inner(float x) =>
    ta.sma(x,2)
outer(float x) =>
    inner(x)
plot(outer(close))
plot(outer(close + 100))''';
    final n=PineV6LanguageProgram.compile(nested).evaluate(bars.take(10).toList());
    expect(n[0].values.first,isNull);expect(n[1].values.first,isNull);
    for(var i=1;i<10;i++)expect(n[1].values[i]!-n[0].values[i]!,closeTo(100,1e-6));
  });
}
