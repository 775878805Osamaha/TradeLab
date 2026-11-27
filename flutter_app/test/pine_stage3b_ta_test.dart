import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/pine_function_registry.dart';
import 'package:tradelab_flutter/chart/chart_indicator_library.dart';
import 'package:tradelab_flutter/chart/chart_indicator_engine.dart';
import 'package:tradelab_flutter/chart/pine_runtime_core.dart';
import 'package:tradelab_flutter/chart/pine_ta_library.dart';
import 'package:tradelab_flutter/chart/pine_v6_language_runtime.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

class GuardedBars extends ListBase<TradeCandle>{
  GuardedBars(this.bars,this.cutoff);
  final List<TradeCandle> bars;
  int cutoff;
  @override int get length=>bars.length;
  @override set length(int n)=>throw UnsupportedError('read only');
  @override TradeCandle operator[](int i){
    if(i>=cutoff)throw StateError('future read $i >= $cutoff');
    return bars[i];
  }
  @override void operator[]=(int i,TradeCandle v)=>throw UnsupportedError('read only');
}
void compare(Object? actual,Object? expected){
  if(expected is List){
    expect(actual,isA<List>());
    final list=actual as List;
    expect(list.length,expected.length);
    for(var i=0;i<list.length;i++){compare(list[i],expected[i]);}
  }else if(expected is num){
    expect(actual,isA<num>());expect(actual,closeTo(expected.toDouble(),1e-8));
  }else{expect(actual,expected);}
}
List<Object?> argsFor(String name,double? x){
  switch(name){
    case 'ta.atr':return [2];
    case 'ta.tr':return [true];
    case 'ta.macd':return [x,2,3,2];
    case 'ta.bb':return [x,2,2];
    case 'ta.stdev':return [x,2,true];
    case 'ta.crossover':case 'ta.crossunder':return [x,13.5];
    default:return [x,2];
  }
}
void main(){
  final fixture=jsonDecode(File('test/fixtures/pine_stage3b_ohlcv.json').readAsStringSync()) as Map;
  final matrix=jsonDecode(File('test/fixtures/pine_stage3b_support.json').readAsStringSync()) as List;
  final bars=[for(final row in fixture['bars'] as List)
    TradeCandle((row[0] as num).toDouble(),(row[1] as num).toDouble(),
        (row[2] as num).toDouble(),(row[3] as num).toDouble())];
  final expected=fixture['expected'] as Map;
  test('support matrix is exhaustive and fixture-backed',(){
    expect(matrix.map((r)=>r['name']).toSet(),PineFunctionRegistry.ta.keys.toSet());
    expect(expected.keys.toSet(),PineFunctionRegistry.ta.keys.toSet());
    expect(matrix.length,PineFunctionRegistry.ta.length);
    for(final row in matrix){
      expect(row['formulaReference'],'manual-ohlcv-v1');
      expect((expected[row['name']] as List).length,bars.length);
      expect(row['runtime'],PineFunctionRegistry.ta[row['name']]!.tupleResult
          ?'library-only':'closed-bar scalar');
    }
  });
  for(final row in matrix){
    final name=row['name'] as String;
    final signature=PineFunctionRegistry.ta[name]!;
    List<Object?> prefix(List<TradeCandle> input,int count,{bool gap=false,int missingAt=0}){
      final budget=PineRuntimeBudget();
      final state=PineTaState(signature,budget);
      try{return [for(var i=0;i<count;i++)state.step(argsFor(name,gap&&i==missingAt?null:input[i].close),
          input[i],i==0?null:input[i-1].close)];}finally{budget.stop();}
    }
    final series=expected[name] as List;
    test('$name independent manual OHLCV reference',(){
      compare(prefix(bars,bars.length),series);
    });
    test('$name na and warmup policy',(){
      final actual=prefix(bars,bars.length,gap:true);
      if(name=='ta.tr'){
        final state=PineTaState(signature,PineRuntimeBudget());
        expect(state.step([false],bars.first,null),isNull);
        compare(actual,series);
      }else if(name=='ta.atr'){
        expect(actual.first,isNull);compare(actual,series);
      }else if(signature.booleanResult){
        expect(actual[0],isFalse);expect(actual[1],isFalse);
      }else if(signature.tupleResult){
        expect(actual.first,[null,null,null]);
        if(name=='ta.bb')expect(actual[1],[null,null,null]);
      }else{
        expect(actual.first,isNull);
        if(!['ta.ema'].contains(name))expect(actual[1],isNull);
        if(['ta.rsi','ta.change','ta.roc'].contains(name))expect(actual[2],isNull);
      }
      // Missing source after warm-up must not become an invented zero or
      // read a later bar. These are explicitly internal policy assertions.
      final middle=prefix(bars,bars.length,gap:true,missingAt:3);
      if(name=='ta.tr'||name=='ta.atr'){compare(middle,series);}
      else if(signature.booleanResult){expect(middle[3],isFalse);expect(middle[4],isFalse);}
      else if(name=='ta.bb'||name=='ta.macd'){
        expect(middle[3],isA<List>());
        if(name=='ta.bb')compare(middle[3],middle[2]);
      }else if(['ta.sma','ta.ema','ta.rma','ta.wma','ta.stdev'].contains(name)){
        compare(middle[3],middle[2]);
      }else{expect(middle[3],isNull);}
    });
    test('$name Replay prefix 6 -> 2 -> 4, no future read',(){
      final guarded=GuardedBars(bars,6);
      if(signature.tupleResult){
        compare(prefix(guarded,6),series);
        guarded.cutoff=2;compare(prefix(guarded,2),series.take(2).toList());
        guarded.cutoff=4;compare(prefix(guarded,4),series.take(4).toList());
        return;
      }
      final call='$name(${row['call']})';
      final expression=signature.booleanResult?'$call ? 1 : 0':call;
      // Force the advanced route for legacy names, preserving the legacy executor.
      final program=PineV6LanguageProgram.compile('indicator("Batch 1")\nvar int marker = 0\nplot($expression)');
      final instance=program.newInstance();
      final values=[for(final v in series) v is bool?(v?1:0):v];
      try{
        instance.rebuild(guarded,6);compare(instance.outputs.single.values,values);
        guarded.cutoff=2;instance.rebuild(guarded,2);
        compare(instance.outputs.single.values,values.take(2).toList());
        guarded.cutoff=4;instance.rebuild(guarded,4);
        compare(instance.outputs.single.values,values.take(4).toList());
        final second=program.newInstance()..rebuild(guarded,4);
        compare(second.outputs.single.values,values.take(4).toList());second.close();
      }finally{instance.close();}
    });
  }
  test('registry refuses missing, duplicate and unknown arguments',(){
    final s=PineFunctionRegistry.ta['ta.rma']!;
    expect(()=>s.bind([null]),throwsA(isA<PineRuntimeException>()));
    expect(()=>s.bind(['source','source']),throwsA(isA<PineRuntimeException>()));
    expect(()=>s.bind(['source','bogus']),throwsA(isA<PineRuntimeException>()));
  });
  test('registry rejects malformed TA calls before reading bars',(){
    for(final call in ['ta.rma(close, 0)','ta.rma(close, 501)',
        'ta.rma(close, 2.5)','ta.rma(close, true)','ta.tr(1)',
        'ta.rma(close)','ta.rma(close, unknown=2)']){
      expect(()=>PineV6LanguageProgram.compile('indicator("Invalid")\nplot($call)'),
          throwsA(isA<PineRuntimeException>()),reason:call);
    }
  });
  test('new scalar source needs no artificial advanced statement',(){
    final p=PineV6LanguageProgram.compile('indicator("RMA")\nplot(ta.rma(close, 2))');
    compare(p.evaluate(bars).single.values,expected['ta.rma']);
    const saved=ChartSavedIndicatorScript(id:'script-stage3b-rma',name:'RMA',
        source:'indicator("RMA")\nplot(ta.rma(close, 2))');
    final definition=saved.supportedIndicator();
    expect(definition,isNotNull,reason:saved.compileError);
    compare(ChartIndicatorEngine.compute(bars,definition!).plots.single.values,
        expected['ta.rma']);
  });
}
