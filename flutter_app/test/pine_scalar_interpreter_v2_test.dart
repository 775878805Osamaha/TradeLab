import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/pine_v6_language_runtime.dart';
import 'package:tradelab_flutter/chart/pine_v6_frontend.dart';
import 'package:tradelab_flutter/chart/pine_runtime_core.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

const fixture='test/fixtures/tradingview/pine-logs-TradeLab Reference Logs V2.csv';
List<TradeCandle> capture(){
  final bytes=File(fixture).readAsBytesSync();
  expect(sha256.convert(bytes).toString(),'6a052a535dc4bf77d3687a10446e9572bdf523a3bc80e2fe728a2c290899da7f');
  final lines=const LineSplitter().convert(utf8.decode(bytes));
  expect(lines.length,5336);
  return [for(final line in lines.skip(1).take(5334))
    _bar(line.substring(line.indexOf(',"')+2,line.length-1).split(','))];
}
TradeCandle _bar(List<String> f){
  expect(f.length,26);expect(f[0],'TVC:GOLD');
  return TradeCandle(double.parse(f[2]),double.parse(f[3]),double.parse(f[4]),double.parse(f[5]),
    timestampMs:int.parse(f[1]),volume:double.parse(f[6]));
}
class _Poison extends ListBase<TradeCandle>{
  _Poison(this.data,this.cutoff);
  final List<TradeCandle> data;
  final int cutoff;
  @override int get length=>data.length;
  @override set length(int n)=>throw UnsupportedError('readonly');
  @override TradeCandle operator[](int i){
    if(i>=cutoff)throw StateError('Future read');
    return data[i];
  }
  @override void operator[]=(int i,TradeCandle v)=>throw UnsupportedError('readonly');
}

const numeric='''//@version=6
indicator("Scalar numeric")
float src = bar_index % 7 == 0 ? na : close
plot(math.floor(src / 10))
plot(math.sign(src - open))
plot(math.sum(length=5, source=src))
plot(math.max(open, close, high))
plot(math.min(open, close, low))
plot(math.abs(close-open))''';
const typed='''//@version=6
indicator("Scalar typed")
string s = str.tostring(math.floor(close), "#")
string p = "px:" + s
color c = color.new(color.olive, close > open ? 40 : 100)
plot(str.contains(p, "7") ? 1 : 0)
plot(str.format_time(bar_index * 3600000, "MM-dd", "UTC") == "01-02" ? 1 : 0)
plot(c == #80800099 ? 1 : c == #80800000 ? -1 : 0)
plot(str.tostring(na) == "NaN" ? 1 : 0)''';
void main(){
  late List<TradeCandle> bars;
  setUpAll(()=>bars=capture());
  test('actual Pine numeric script on 5334 reference OHLC bars, independent values and na',(){
    final p=PineV6LanguageProgram.compile(numeric);
    expect(p.legacy,isNull);
    final values=p.evaluate(bars).map((p)=>p.values).toList();
    expect(values.length,6);
    final history=<double>[];
    for(var i=0;i<bars.length;i++){
      final b=bars[i],x=i%7==0?null:b.close;
      if(x!=null)history.add(x);
      expect(values[0][i],x==null?null:(x/10).floor(),reason:'floor $i');
      expect(values[1][i],x==null?null:(x-b.open).sign,reason:'sign $i');
      if(history.length<5){expect(values[2][i],isNull);}
      else{
        final expected=history.skip(history.length-5).fold<double>(0,(a,b)=>a+b);
        expect(values[2][i],closeTo(expected,1e-6),reason:'sum $i');
      }
      expect(values[3][i],math.max(b.high,math.max(b.open,b.close)));
      expect(values[4][i],math.min(b.low,math.min(b.open,b.close)));
      expect(values[5][i],(b.close-b.open).abs());
    }
    final prepared=const PineV6Frontend().prepare(numeric);
    for(final n in ['math.floor','math.sign','math.sum']){
      expect(prepared.semantic.diagnostics.any((d)=>d.code=='known_unimplemented'&&d.message.endsWith(': '+n)),isFalse);
    }
  });
  test('actual Pine string and RGBA values, explicit UTC, and na on same OHLC',(){
    final p=PineV6LanguageProgram.compile(typed);
    expect(p.legacy,isNull);
    final v=p.evaluate(bars).map((p)=>p.values).toList();
    for(var i=0;i<bars.length;i++){
      final b=bars[i];
      expect(v[0][i],b.close.floor().toString().contains('7')?1:0);
      final t=DateTime.fromMillisecondsSinceEpoch(i*3600000,isUtc:true);
      expect(v[1][i],t.month==1&&t.day==2?1:0);
      expect(v[2][i],b.close>b.open?1:-1);
      expect(v[3][i],1);
    }
  });
  test('real Pine replay 3000 to 1000 to 3000, poisoned future on both scripts',(){
    for(final source in [numeric,typed]){
      final p=PineV6LanguageProgram.compile(source);
      final expected=p.evaluate(bars).map((x)=>x.values).toList();
      final instance=p.newInstance();
      try{
        for(final cutoff in [3000,1000,3000]){
          instance.rebuild(_Poison(bars,cutoff),cutoff);
          for(var i=0;i<expected.length;i++)expect(instance.outputs[i].values,expected[i].take(cutoff).toList());
        }
      }finally{instance.close();}
    }
  });
  test('unsupported market formats and exchange timezone remain rejected at compile',(){
    for(final expression in ['str.tostring(close, format.mintick)',
      'str.format_time(0, "MM-dd", "America/New_York")','str.format_time(0)']){
      expect(()=>PineV6LanguageProgram.compile('//@version=6\nindicator("Guard")\nstring x = '+expression+'\nplot(close)'),throwsA(isA<PineRuntimeException>()));
    }
  });
}
