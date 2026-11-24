import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';
import 'pine_stage3b_reference_test.dart' show libraryValues, program;
import 'pine_stage3b_ta_test.dart' show GuardedBars;

const capturePath='test/fixtures/tradingview/4_5778588908598075071.csv';
const functions=['ta.ema','ta.rsi','ta.atr','ta.rma'];
const tolerance=1e-6;
const startIndex=300;
const excludedIndex=998;
const scope='TVC:GOLD 1h, length 14, indices 300..997, abs <= 1e-6';

class Capture {
  Capture(this.times,this.bars,this.volumes,this.references);
  final List<DateTime> times;
  final List<TradeCandle> bars;
  final List<double> volumes;
  final Map<String,List<double>> references;
  static Capture read() {
    final lines=const LineSplitter().convert(File(capturePath).readAsStringSync());
    if(lines.length!=1000||lines.first!='Date,Message'){
      throw const FormatException('Unexpected original CSV row count/header');
    }
    final times=<DateTime>[],bars=<TradeCandle>[],volumes=<double>[];
    final refs={for(final name in functions)name:<double>[]};
    // This exact export has one quoted Message field, twelve comma-delimited
    // fields inside, and an unquoted ISO Date column. Reject malformed input.
    for(var i=1;i<lines.length;i++){
      final row=RegExp(r'^([^,]+),"([^"]+)"$').firstMatch(lines[i]);
      if(row==null)throw FormatException('Invalid CSV row $i');
      final fields=row.group(2)!.split(',');
      if(fields.length!=12||fields[0]!='TVC:GOLD'||fields[1]!='60'){
        throw FormatException('Wrong symbol/timeframe/field count row $i');
      }
      final time=DateTime.fromMillisecondsSinceEpoch(int.parse(fields[2]),isUtc:true);
      if(time!=DateTime.parse(row.group(1)!).toUtc()||
          (times.isNotEmpty&&!time.isAfter(times.last))){
        throw FormatException('Non-monotonic or inconsistent timestamps at row $i');
      }
      final vals=fields.skip(3).map(double.parse).toList();
      if(vals.any((v)=>!v.isFinite)||vals[1]<vals[0]||vals[1]<vals[3]||
          vals[2]>vals[0]||vals[2]>vals[3]||vals[1]<vals[2]||vals[4]<0){
        throw FormatException('Invalid OHLCV row $i');
      }
      times.add(time);
      // Preserve volume separately: TradeCandle currently accepts OHLC only.
      // None of the four selected functions consumes volume.
      bars.add(TradeCandle(vals[0],vals[1],vals[2],vals[3]));
      volumes.add(vals[4]);
      for(var j=0;j<functions.length;j++){refs[functions[j]]!.add(vals[5+j]);}
    }
    return Capture(times,bars,volumes,refs);
  }
  List<TradeCandle> get closed=>List.unmodifiable(bars.take(excludedIndex));
}

// Report absolute/relative maxima independently. Relative error is
// abs(actual-ref)/abs(ref), dimensionless; undefined for zero reference.
Map<String,Object?> stats(List<double?> actual,List<double> ref,int from,int to){
  double maxAbs=-1,maxRel=-1;
  int? absIndex,relIndex,firstValid;
  var missing=0,over=0,undefinedRelative=0;
  for(var i=from;i<to;i++){
    final v=actual[i];
    if(v==null){missing++;continue;}
    if(!v.isFinite)throw StateError('Nonfinite output at $i');
    firstValid??=i;
    final diff=(v-ref[i]).abs();
    if(diff>tolerance)over++;
    if(diff>maxAbs){maxAbs=diff;absIndex=i;}
    if(ref[i]==0){undefinedRelative++;continue;}
    final relative=diff/ref[i].abs();
    if(relative>maxRel){maxRel=relative;relIndex=i;}
  }
  return {'from':from,'toExclusive':to,'count':to-from,'na':missing,
    'firstValid':firstValid,'overTolerance':over,
    'maxAbs':absIndex==null?null:maxAbs,'maxAbsIndex':absIndex,
    'maxRel':relIndex==null?null:maxRel,'maxRelIndex':relIndex,
    'undefinedRelative':undefinedRelative,
    'firstActual':actual[from],'firstReference':ref[from],
    'lastActual':actual[to-1],'lastReference':ref[to-1]};
}

void compareCapture(String route,String name,List<double?> actual,List<double> ref,
    {int end=excludedIndex,bool early=true}){
  expect(actual.length,end);
  if(early){
    final warm=stats(actual,ref,0,startIndex);
    // Diagnostics only: historical state before the CSV start is unknown.
    // ignore: avoid_print
    // ignore: avoid_print
  print('TV_CAPTURE_STATS ${jsonEncode({'route':route,'function':name,'window':'warmup','stats':warm})}');
  }
  final result=stats(actual,ref,startIndex,end);
  print('TV_CAPTURE_STATS ${jsonEncode({'route':route,'function':name,'window':'reference','stats':result})}');
  expect(result['na'],0,reason:'$route $name missing reference-window output');
  expect(result['overTolerance'],0,reason:'$route $name exceeds absolute 1e-6: $result');
  expect(result['maxAbs'],lessThanOrEqualTo(tolerance),reason:'$route $name');
}

void main(){
  final capture=Capture.read();
  final closed=capture.closed;
  test('genuine original TVC:GOLD CSV integrity, last indicative excluded',(){
    expect(capture.bars.length,999);
    expect(capture.volumes.length,999);
    expect(capture.times.first,DateTime.utc(2026,9,24,2));
    expect(capture.times.last,DateTime.utc(2026,11,24,12));
    expect(closed.length,998);
    expect(excludedIndex-startIndex,698);
  });
  for(final name in functions){
    final ref=capture.references[name]!;
    test('$name(14) actual TradingView CSV library and Pine runtime absolute parity',(){
      final library=libraryValues(name,14,closed);
      final script=program(name,14);
      expect(script.legacy,isNull,reason:'Must exercise advanced Pine runtime');
      final direct=script.evaluate(closed).single.values;
      compareCapture('library',name,library,ref);
      compareCapture('pine',name,direct,ref);
      expect(direct,library,reason:'Advanced script and library agree across full prefix');
      if(name=='ta.ema'||name=='ta.rsi'){
        final legacy=program(name,14,advanced:false);
        expect(legacy.legacy,isNotNull);
        compareCapture('legacy',name,legacy.evaluate(closed).single.values,ref);
      }
    });
    test('$name(14) genuine CSV Replay 700 -> 400 -> 700 and no future access',(){
      final p=program(name,14);
      final direct=p.evaluate(closed.take(700).toList()).single.values;
      final guarded=GuardedBars(closed,0);
      final instance=p.newInstance();
      try{
        for(var i=0;i<700;i++){guarded.cutoff=i+1;instance.advance(guarded[i]);}
        final first=instance.outputs.single.values;
        expect(first,direct);
        compareCapture('replay700-first',name,first,ref,end:700,early:false);
        guarded.cutoff=400;instance.rebuild(guarded,400);
        final rewound=instance.outputs.single.values;
        expect(rewound,direct.take(400).toList());
        compareCapture('replay400',name,rewound,ref,end:400,early:false);
        for(var i=400;i<700;i++){guarded.cutoff=i+1;instance.advance(guarded[i]);}
        final resumed=instance.outputs.single.values;
        expect(resumed,direct);
        expect(resumed,first);
        compareCapture('replay700-resumed',name,resumed,ref,end:700,early:false);
      }finally{instance.close();}
    });
  }
  test('external parity matrix scope cannot extend beyond the tested capture',(){
    final rows=jsonDecode(File('test/fixtures/pine_stage3b_support.json').readAsStringSync()) as List;
    for(final row in rows){
      if(functions.contains(row['name'])){
        final external=row['externalReference'] as Map;
        expect(external['symbol'],'TVC:GOLD');
        expect(external['timeframe'],'1h');
        expect(external['length'],14);
        expect(external['absoluteTolerance'],tolerance);
        expect(external['startIndex'],startIndex);
        expect(external['endIndexExclusive'],excludedIndex);
        expect(external['status'],'pending_exact_head_ci');
      }else{
        expect(row['externalReference'],isNull);
        expect(row['tradingView'],'not_verified');
      }
    }
  });
}
