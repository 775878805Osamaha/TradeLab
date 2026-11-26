import 'dart:collection';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/pine_runtime_core.dart';
import 'package:tradelab_flutter/chart/pine_series_primitives.dart';

class _Prefix extends ListBase<double?> {
  _Prefix(this.data,this.cutoff);
  final List<double?> data;
  final int cutoff;
  final reads=<int>[];
  @override int get length=>data.length;
  @override set length(int value)=>throw UnsupportedError('readonly');
  @override double? operator[](int i){
    if(i>=cutoff)throw StateError('future candle read');
    reads.add(i);return data[i];
  }
  @override void operator[]=(int i,double? value)=>throw UnsupportedError('readonly');
}

List<double?> pivots(List<double?> data,int cutoff,{required bool high,int left=2,int right=2}){
  final budget=PineRuntimeBudget();
  final state=PinePivotState(budget,capacity:16,high:high);
  try{return [for(var i=0;i<cutoff;i++)state.step(i,data[i],left,right)];}
  finally{budget.stop();}
}

void main(){
  test('call history current, historical na, ring wrap and bounds',(){
    final budget=PineRuntimeBudget();
    final h=PineCommittedHistory<double>(budget,capacity:3);
    expect(h.read(0),isNull);
    h.commit(0,10);
    expect(h.read(0),10);
    expect(h.read(1),isNull);
    h.commit(1,null);
    h.commit(2,30);
    expect([h.read(0),h.read(1),h.read(2)],[30,null,10]);
    h.commit(3,40);
    expect([h.read(0),h.read(1),h.read(2)],[40,30,null]);
    expect(()=>h.read(-1),throwsA(isA<PineRuntimeException>()));
    expect(()=>h.read(3),throwsA(isA<PineRuntimeException>()));
    budget.stop();
  });
  test('call history boolean missing value and independent scopes',(){
    final budget=PineRuntimeBudget();
    final a=PineCommittedHistory<bool>(budget,capacity:3,missing:false);
    final b=PineCommittedHistory<bool>(budget,capacity:3,missing:false);
    a.commit(0,true);
    b.commit(0,false);
    expect(a.read(0),isTrue);
    expect(a.read(1),isFalse);
    expect(b.read(0),isFalse);
    expect(()=>a.commit(0,false),throwsA(isA<PineRuntimeException>()));
    expect(()=>a.commit(2,false),throwsA(isA<PineRuntimeException>()));
    a.commit(1,false);
    expect(a.read(1),isTrue);
    budget.stop();
  });
  test('barssince na before event, zero on event, reset and isolated state',(){
    final budget=PineRuntimeBudget();
    final a=PineBarsSinceState(budget),b=PineBarsSinceState(budget);
    expect([for(final v in [false,true,false,false,true])a.step(v)],[null,0,1,2,0]);
    expect([for(final v in [false,false,true,false])b.step(v)],[null,null,0,1]);
    budget.stop();
  });
  test('high pivot appears at confirmation, not the center bar',(){
    expect(pivots([1,3,5,3,1],5,high:true),[null,null,null,null,5]);
  });
  test('low pivot appears at confirmation, not the center bar',(){
    expect(pivots([5,3,1,3,5],5,high:false),[null,null,null,null,1]);
  });
  test('pivot missing window stays missing; unverified ties fail closed',(){
    expect(pivots([1,null,5,3,1],5,high:true),[null,null,null,null,null]);
    expect(()=>pivots([1,5,5,3,1],5,high:true),throwsA(
        isA<PineRuntimeException>().having((e)=>e.code,'code','unverified_pivot_tie')));
  });
  test('pivotlow equal older left leg is accepted at confirmation',(){
    expect(pivots([5,1,1,3,5],5,high:false),[null,null,null,null,1]);
  });
  test('pivotlow equal newer right leg disqualifies the center',(){
    expect(pivots([5,3,1,1,5],5,high:false),[null,null,null,null,null]);
  });
  test('pivotlow right equality wins over allowed left equality',(){
    expect(pivots([5,1,1,1,5],5,high:false),[null,null,null,null,null]);
  });
  test('pivots match independent strict-extremum reference across unique series',(){
    final source=<double?>[for(var i=0;i<101;i++)((i*37)%101).toDouble()];
    for(final high in [true,false]){
      final actual=pivots(source,source.length,high:high,left:3,right:4);
      final expected=<double?>[];
      for(var i=0;i<source.length;i++){
        if(i<7){expected.add(null);continue;}
        final center=i-4;
        final value=source[center]!;
        final window=source.sublist(i-7,i+1);
        final extreme=window.every((v)=>v==value||(high?v!<value:v!>value));
        expected.add(extreme?value:null);
      }
      expect(actual,expected);
    }
  });
  test('pivot Replay prefix, seek, future poison and separate calls',(){
    final source=<double?>[1,3,5,3,1,9,2,0,8];
    final protected=_Prefix(source,5);
    final prefix=pivots(protected,5,high:true);
    expect(prefix,[null,null,null,null,5]);
    expect(protected.reads,[0,1,2,3,4]);
    expect(pivots(source,source.length,high:true).take(5),prefix);
    expect(pivots(source,3,high:true),prefix.take(3));
    expect(pivots(source,5,high:true),prefix);
  });
  test('bounded history memory and pivot length refusal',(){
    final budget=PineRuntimeBudget(const PineRuntimeLimits(maxStoredValues:3));
    expect(()=>PineCommittedHistory<double>(budget,capacity:4),throwsA(isA<PineRuntimeException>()));
    budget.stop();
    final b=PineRuntimeBudget();
    final state=PinePivotState(b,capacity:5,high:true);
    expect(()=>state.step(0,1,3,2),throwsA(isA<PineRuntimeException>()));
    expect(state.step(0,1,2,2),isNull);
    b.stop();
  });
}
