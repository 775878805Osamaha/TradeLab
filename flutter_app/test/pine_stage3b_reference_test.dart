import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/pine_function_registry.dart';
import 'package:tradelab_flutter/chart/pine_runtime_core.dart';
import 'package:tradelab_flutter/chart/pine_ta_library.dart';
import 'package:tradelab_flutter/chart/pine_v6_language_runtime.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';
import 'pine_stage3b_ta_test.dart' show GuardedBars;

const names=['ta.ema','ta.rsi','ta.atr','ta.rma'];
const classification='مختبرة داخليًا بمعادلة مستقلة';
double number(Object? x) {
  if(x is! num || !x.isFinite)throw FormatException('Invalid numeric fixture value: $x');
  return x.toDouble();
}
TradeCandle candle(List row,{int offset=0}){
  final o=number(row[offset]),h=number(row[offset+1]),
      l=number(row[offset+2]),c=number(row[offset+3]);
  if(h<math.max(o,c)||l>math.min(o,c)||h<l){
    throw const FormatException('Invalid OHLC ordering');
  }
  return TradeCandle(o,h,l,c);
}
void equalValue(double? actual,Object? reference,String label,
    {double absTol=2e-8,double relTol=2e-11}){
  if(reference==null){expect(actual,isNull,reason:label);return;}
  final ref=number(reference);
  expect(actual,isNotNull,reason:label);
  expect(actual!.isFinite,isTrue,reason:label);
  expect(actual,closeTo(ref,math.max(absTol,ref.abs()*relTol)),reason:label);
}
List<double?> libraryValues(String name,int n,List<TradeCandle> bars){
  final budget=PineRuntimeBudget();
  final state=PineTaState(PineFunctionRegistry.ta[name]!,budget);
  try{
    return [for(var i=0;i<bars.length;i++)
      state.step(name=='ta.atr'?[n]:[bars[i].close,n],
          bars[i],i==0?null:bars[i-1].close) as double?];
  }finally{budget.stop();}
}
PineV6LanguageProgram program(String name,int length,{bool advanced=true}){
  final call=name=='ta.atr'?'$name($length)':'$name(close, $length)';
  final marker=advanced?'var int marker = 0\n':'';
  return PineV6LanguageProgram.compile('//@version=6\nindicator("Long reference")\n${marker}plot($call)');
}
void compareSeries(List<double?> actual,List expected,String label,
    {int start=0,double absTol=2e-8,double relTol=2e-11}){
  expect(actual.length,expected.length,reason:label);
  for(var i=start;i<expected.length;i++){
    equalValue(actual[i],expected[i],'$label bar ${i+1}',absTol:absTol,relTol:relTol);
  }
}
void main(){
  final doc=jsonDecode(File('test/fixtures/pine_stage3b_ohlcv_long.json').readAsStringSync()) as Map;
  final bars=[for(final row in doc['bars'] as List)candle(row as List)];
  final expected=doc['expected'] as Map;
  final checkpoints=(doc['checkpointsOneBased'] as List).cast<int>();
  test('360-bar fixture integrity and truthful support matrix',(){
    expect(doc['seed'],20261124);
    expect(doc['barCount'],360);
    expect(bars.length,360);
    expect(checkpoints,containsAll([1,10,50,300]));
    final matrix=jsonDecode(File('test/fixtures/pine_stage3b_support.json').readAsStringSync()) as List;
    expect(matrix.map((e)=>e['name']).toSet(),PineFunctionRegistry.ta.keys.toSet());
    for(final row in matrix){
      expect(row['status'],classification);
      expect(row['verification'],'internal_independent_formula');
      expect(row['tradingView'],names.contains(row['name'])?'pending_exact_head_ci':'not_verified');
      expect((row['longReference'] as String).startsWith('seeded-360-ohlcv-v2'),names.contains(row['name']));
    }
    for(final row in doc['bars'] as List){expect(number(row[4]),greaterThanOrEqualTo(0));}
  });
  for(final n in [14,50]){
    for(final name in names){
      final ref=expected['$n'][name] as List;
      test('$name($n) full 360-bar independent reference and warmup',(){
        final actual=libraryValues(name,n,bars);
        compareSeries(actual,ref,'library $name($n)');
        final first=name=='ta.ema'?1:name=='ta.rsi'?n+1:n;
        expect(actual.take(first-1),everyElement(isNull));
        expect(actual[first-1],isNotNull);
        for(final bar in checkpoints){
          equalValue(actual[bar-1],ref[bar-1],'explicit checkpoint $name($n) bar $bar');
        }
        compareSeries(program(name,n).evaluate(bars).single.values,ref,'advanced $name($n)');
      });
      test('$name($n) long Replay seeks and continuation',(){
        final instance=program(name,n).newInstance();
        final guarded=GuardedBars(bars,360);
        try{
          for(final count in [360,1,10,50,300]){
            guarded.cutoff=count;instance.rebuild(guarded,count);
            compareSeries(instance.outputs.single.values,ref.take(count).toList(),'Replay $name($n) cutoff $count');
          }
          guarded.cutoff=360;
          for(var i=300;i<360;i++){instance.advance(guarded[i]);}
          compareSeries(instance.outputs.single.values,ref,'Replay continuation $name($n)');
        }finally{instance.close();}
      });
      if(name=='ta.ema'||name=='ta.rsi'){
        test('$name($n) legacy route against independent long reference',(){
          final p=program(name,n,advanced:false);
          expect(p.legacy,isNotNull,reason:'Must exercise existing legacy path');
          compareSeries(p.evaluate(bars).single.values,ref,'legacy $name($n)');
        });
      }
    }
  }
  final capture=File('test/fixtures/tradingview/pine_stage3b_actual.json');
  test('optional genuine TradingView export comparison (EMA RSI ATR RMA)',(){
    final data=jsonDecode(capture.readAsStringSync()) as Map;
    expect(data['schemaVersion'],1);
    expect(data['source'],'TradingView actual export only');
    for(final k in ['symbol','timeframe','exportedAtUtc','session','timezone','historyStartUtc','historyAlignmentNote']){
      expect(data[k],isA<String>(),reason:k);
      expect((data[k] as String).trim(),isNotEmpty,reason:k);
    }
    final exported=DateTime.parse(data['exportedAtUtc'] as String);
    final historyStart=DateTime.parse(data['historyStartUtc'] as String);
    expect(exported.isUtc,isTrue);expect(historyStart.isUtc,isTrue);
    expect(data['chartType'],'standard candles');expect(data['timezone'],'UTC');
    expect(data['length'],14);
    expect(data['columns'],['timeUtc','open','high','low','close','volume','ema','rsi','atr','rma']);
    final rows=data['rows'] as List;
    expect(rows.length,greaterThanOrEqualTo(300));
    final start=data['compareFromBarOneBased'] as int;
    expect(start,inInclusiveRange(1,rows.length-49),reason:'At least 50 comparison rows required');
    final absTol=number(data['absoluteTolerance']),relTol=number(data['relativeTolerance']);
    expect(absTol,inInclusiveRange(0,0.000001));
    expect(relTol,inInclusiveRange(0,0.00000001));
    DateTime? last;
    for(final row in rows){
      expect(row,isA<List>());expect(row.length,10);
      final time=DateTime.parse(row[0] as String);
      expect(time.isUtc,isTrue);
      if(last==null){expect(time,historyStart);}else{expect(time.isAfter(last),isTrue);}
      last=time;
      expect(number(row[5]),greaterThanOrEqualTo(0));
      for(var i=6;i<10;i++){if(row[i]!=null)number(row[i]);}
    }
    expect(exported.isBefore(last!),isFalse);
    final source=[for(final row in rows)candle(row as List,offset:1)];
    for(var k=0;k<names.length;k++){
      final ref=[for(final row in rows)row[k+6]];
      expect(ref.skip(start-1).any((v)=>v!=null),isTrue,reason:names[k]);
      compareSeries(program(names[k],14).evaluate(source).single.values,ref,
          'TradingView ${data['symbol']} ${names[k]}',start:start-1,absTol:absTol,relTol:relTol);
    }
  },skip:capture.existsSync()?false:'SKIP: no additional optional JSON capture; the fixed genuine CSV is tested separately by pine_stage3b_tradingview_csv_test.dart.');
}
