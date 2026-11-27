import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/candle_prefix.dart';
import 'package:tradelab_flutter/chart/chart_heikin_ashi.dart';
import 'package:tradelab_flutter/chart/pine_function_registry.dart';
import 'package:tradelab_flutter/chart/pine_indicator_seed_candidates.dart';
import 'package:tradelab_flutter/chart/pine_runtime_core.dart';
import 'package:tradelab_flutter/chart/pine_series_primitives.dart';
import 'package:tradelab_flutter/chart/pine_ta_library.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

const fixture='test/fixtures/tradingview/pine-logs-TradeLab Reference Logs V2.csv';
const fingerprint='6a052a535dc4bf77d3687a10446e9572bdf523a3bc80e2fe728a2c290899da7f';
const names=['macdL','macdS','macdH','diP','diM','adx','stV','stD','haO','haH','haL','haC',
  'ph','pl','barssince','sma','stdev','highest','lowest'];
const tolerance=1e-6;

class _Capture {
  final List<TradeCandle> bars=[];
  final List<double> volumes=[];
  final List<int> times=[];
  final List<List<double?>> reference=[];
  _Capture(){
    final bytes=File(fixture).readAsBytesSync();
    expect(sha256.convert(bytes).toString(),fingerprint);
    final lines=const LineSplitter().convert(utf8.decode(bytes));
    expect(lines.first,'Date,Message');
    expect(lines.length,5336);
    for(final line in lines.skip(1)){
      final split=line.indexOf(',"');
      expect(split,greaterThan(0));
      expect(line.endsWith('"'),isTrue);
      final fields=line.substring(split+2,line.length-1).split(',');
      expect(fields.length,26);
      expect(fields[0],'TVC:GOLD');
      final ts=int.parse(fields[1]);
      expect(DateTime.parse(line.substring(0,split)).millisecondsSinceEpoch,ts);
      if(times.isNotEmpty)expect(ts,greaterThan(times.last));
      final values=fields.skip(2).map((s)=>s=='NaN'?null:double.parse(s)).toList();
      expect(values.whereType<double>().every((v)=>v.isFinite),isTrue);
      times.add(ts);
      bars.add(TradeCandle(values[0]!,values[1]!,values[2]!,values[3]!,timestampMs:ts,volume:values[4]));
      volumes.add(values[4]!);
      reference.add(values.sublist(5));
    }
    // Preserve original file; last row is never used as calculation input.
    bars.removeLast();volumes.removeLast();times.removeLast();reference.removeLast();
    expect(bars.length,5334);
  }
}
class _Poison<T> extends ListBase<T>{
  _Poison(this.data,this.cutoff);
  final List<T> data;
  final int cutoff;
  @override int get length=>data.length;
  @override set length(int value)=>throw UnsupportedError('readonly');
  @override T operator[](int i){
    if(i>=cutoff)throw StateError('future data read: $i / $cutoff');
    return data[i];
  }
  @override void operator[]=(int i,T value)=>throw UnsupportedError('readonly');
}

// Candidate/library functions receive only OHLCV, never oracle values.
List<List<double?>> calculate(List<TradeCandle> raw,List<double> volume,int count){
  final budget=PineRuntimeBudget();
  final macd=PineSeededMacd(budget,fast:12,slow:26,signal:9);
  final dmi=PineDmiCandidate(budget,length:14,smoothing:14);
  final st=PineSupertrendCandidate(budget,factor:3,length:10);
  final ph=PinePivotState(budget,capacity:32,high:true),pl=PinePivotState(budget,capacity:32,high:false);
  final since=PineBarsSinceState(budget);
  PineTaState ta(String n)=>PineTaState(PineFunctionRegistry.ta[n]!,budget);
  final sma=ta('ta.sma'),sd=ta('ta.stdev'),hh=ta('ta.highest'),ll=ta('ta.lowest');
  final bars=CandlePrefix(raw,count);
  final ha=ChartHeikinAshi.build(bars);
  final result=<List<double?>>[];
  try{
    for(var i=0;i<count;i++){
      final b=bars[i],previous=i==0?null:bars[i-1].close;
      if(b.timestampMs==null||b.volume!=volume[i])throw StateError('OHLCV metadata mismatch at bar '+i.toString());
      final m=macd.step(b.close),d=dmi.step(b),s=st.step(b),h=ha[i];
      result.add([m.line,m.signal,m.histogram,d.plus,d.minus,d.adx,s.value,s.direction.toDouble(),
        h.open,h.high,h.low,h.close,ph.step(i,b.high,5,5),pl.step(i,b.low,5,5),
        since.step(b.close>b.open)?.toDouble(),sma.step([b.volume,20],b,previous) as double?,
        sd.step([b.close,20,true],b,previous) as double?,hh.step([b.high,20],b,previous) as double?,
        ll.step([b.low,20],b,previous) as double?]);
    }
    return result;
  }finally{budget.stop();}
}

Map<String,Object?> compareColumn(List<List<double?>> actual,List<List<double?>> expected,int col){
  var mismatchNa=0,mismatchNumeric=0,compared=0,excluded=0,finite=0;
  double maxError=0;
  int? firstBad,firstActual,firstExpected,maxErrorIndex;
  for(var i=0;i<actual.length;i++){
    final a=actual[i][col],e=expected[i][col];
    if(a!=null)firstActual??=i;
    if(e!=null)firstExpected??=i;
    if(col>=8&&col<=11&&i>=5273&&i<=5290){excluded++;continue;}
    compared++;
    if((a==null)!=(e==null)){mismatchNa++;firstBad??=i;continue;}
    if(a==null||e==null)continue;
    finite++;
    final error=(a-e).abs();
    if(maxErrorIndex==null||error>maxError){maxError=error;maxErrorIndex=i;}
    if(!a.isFinite||error>tolerance){mismatchNumeric++;firstBad??=i;}
  }
  return {'name':names[col],'rows':compared,'excluded':excluded,'finite_pairs':finite,
    'first_actual':firstActual,'first_expected':firstExpected,'na_mismatches':mismatchNa,
    'numeric_mismatches':mismatchNumeric,'max_abs_error':maxError,'max_abs_error_index':maxErrorIndex,'first_bad_index':firstBad};
}
void main(){
  late _Capture data;
  late List<List<double?>> actual;
  late List<Map<String,Object?>> metrics;
  setUpAll((){
    data=_Capture();
    actual=calculate(data.bars,data.volumes,data.bars.length);
    metrics=[for(var c=0;c<names.length;c++)compareColumn(actual,data.reference,c)];
    final dir=Directory('build/pine_audit')..createSync(recursive:true);
    File(dir.path+'/tradingview_v2_parity.json').writeAsStringSync(jsonEncode({
      'fixture_sha256':fingerprint,'tolerance':tolerance,'input_rows':5334,
      'last_row_excluded':true,'ha_exclusions':[5273,5290],'columns':metrics,
      'scope':'Dart calculation candidates and existing TA library; not interpreter activation',
      'git_sha':Platform.environment['GITHUB_SHA'],'run_id':Platform.environment['GITHUB_RUN_ID']
    }));
    for(final m in metrics){print('TV_V2_COLUMN '+jsonEncode(m));}
  });
  for(var c=0;c<names.length;c++){
    final col=c;
    test('TVC GOLD 1h actual CSV '+names[col]+' values and na mask',(){
      final m=metrics[col];
      expect(m['na_mismatches'],0,reason:jsonEncode(m));
      expect(m['numeric_mismatches'],0,reason:jsonEncode(m));
      expect(m['first_actual'],m['first_expected']);
    });
  }
  test('CSV exact reported warm-up and three low tie confirmation sites',(){
    expect([for(final c in [0,1,2,3,4,5,6,15,16,17,18])metrics[c]['first_actual']],
      [25,33,33,14,14,27,0,19,19,19,19]);
    expect(actual[0][6],0);expect(actual[0][7],1);
    for(var i=1;i<9;i++){expect(actual[i][6],isNull);}
    expect(actual[9][6],closeTo(data.reference[9][6]!,tolerance));
    for(final i in [3982,5067,5068]){
      expect(actual[i][13],data.reference[i][13],reason:'low tie $i');
    }
  });
  test('actual CSV replay 3000 -> 1000 -> 3000, poison OHLC and volume future',(){
    for(final count in [3000,1000,3000]){
      final result=calculate(_Poison(data.bars,count),_Poison(data.volumes,count),count);
      expect(result,actual.take(count).toList());
      for(var c=0;c<names.length;c++){
        final m=compareColumn(result,data.reference,c);
        expect(m['na_mismatches'],0,reason:jsonEncode(m));
        expect(m['numeric_mismatches'],0,reason:jsonEncode(m));
      }
    }
  });
}
