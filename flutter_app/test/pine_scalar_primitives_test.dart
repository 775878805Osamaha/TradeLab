import 'dart:collection';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/pine_runtime_core.dart';
import 'package:tradelab_flutter/chart/pine_scalar_primitives.dart';

class _GuardedPrefix extends ListBase<double?> {
  _GuardedPrefix(this.values,this.cutoff);
  final List<double?> values;
  final int cutoff;
  final List<int> reads=[];
  @override int get length=>values.length;
  @override set length(int n)=>throw UnsupportedError('read only');
  @override double? operator[](int i){
    if(i>=cutoff)throw StateError('future access');
    reads.add(i);return values[i];
  }
  @override void operator[]=(int i,double? value)=>throw UnsupportedError('read only');
}

List<double?> replay(List<double?> source,int cutoff,int length) {
  final budget=PineRuntimeBudget();
  final sum=PineRollingSum(budget,capacity:8);
  try{return [for(var i=0;i<cutoff;i++)sum.step(source[i],length)];}
  finally{budget.stop();}
}

void main(){
  test('floor signed values, integers, and na',(){
    expect([for(final n in <num?>[-2.3,-2,0,2.9,null,double.nan,double.infinity])
      PineScalarPrimitives.floor(n)],[-3,-2,0,2,null,null,null]);
  });
  test('sign signed values, negative zero and na',(){
    expect([for(final n in <num?>[-5,-0.0,5,null,double.nan])
      PineScalarPrimitives.sign(n)],[-1.0,0.0,1.0,null,null]);
  });
  test('sum warms up on non-na samples, skips na, supports changing length',(){
    final budget=PineRuntimeBudget();
    final sum=PineRollingSum(budget,capacity:5);
    expect(sum.step(1,3),isNull);
    expect(sum.step(null,3),isNull);
    expect(sum.step(2,3),isNull);
    expect(sum.step(3,3),6);
    expect(sum.step(null,3),6);
    expect(sum.step(4,2),7);
    expect(sum.step(5,5),15);
    expect(sum.step(6,5),20);
    expect(()=>sum.step(99,0),throwsA(isA<PineRuntimeException>()));
    expect(()=>sum.step(99,6),throwsA(isA<PineRuntimeException>()));
    expect(sum.step(null,1),6);
    budget.stop();
  });
  test('sum independent reference over deterministic missing and variable lengths',(){
    final budget=PineRuntimeBudget();
    final state=PineRollingSum(budget,capacity:12);
    final history=<double>[];
    for(var i=0;i<200;i++){
      final value=i%7==0?null:((i*19)%37-18).toDouble();
      final length=i%12+1;
      if(value!=null)history.add(value);
      double? expected;
      if(history.length>=length){
        expected=0;
        for(var j=history.length-length;j<history.length;j++)expected=expected!+history[j];
      }
      expect(state.step(value,length),expected,reason:'sample '+i.toString());
    }
    budget.stop();
  });
  test('sum Replay prefix, seek and future poison with isolated state',(){
    final source=<double?>[1,null,2,3,4,9000,8000];
    final protected=_GuardedPrefix(source,5);
    final a=replay(protected,5,3);
    expect(a,[null,null,null,6,9]);
    expect(protected.reads,[0,1,2,3,4]);
    expect(replay(source,source.length,3).take(5),a);
    expect(replay(source,3,3),a.take(3));
    expect(replay(source,5,3),a);
    expect(replay([100,200,300],3,3),[null,null,600]);
  });
  test('sum reserves bounded state and refuses a too-small memory budget',(){
    final budget=PineRuntimeBudget(const PineRuntimeLimits(maxStoredValues:3));
    expect(()=>PineRollingSum(budget,capacity:4),throwsA(isA<PineRuntimeException>()));
    budget.stop();
  });
  test('scalar text: documented decimal patterns, bool, string and na',(){
    expect(PineScalarPrimitives.toText(12.5,format:'0.00'),'12.50');
    expect(PineScalarPrimitives.toText(-12.5,format:'#.##'),'-12.5');
    expect(PineScalarPrimitives.toText(123.456),'123.456');
    expect(PineScalarPrimitives.toText(7,format:'000'),'007');
    expect(PineScalarPrimitives.toText(0.125,format:'0.0%'),'12.5%');
    expect(PineScalarPrimitives.toText(true),'true');
    expect(PineScalarPrimitives.toText('original'),'original');
    expect(PineScalarPrimitives.toText(null),'NaN');
    expect(()=>PineScalarPrimitives.toText(1,format:'mintick'),throwsA(isA<PineRuntimeException>()));
    expect(()=>PineScalarPrimitives.toText([1,2]),throwsA(isA<PineRuntimeException>()));
  });
  test('format_time explicit UTC, offset, leap date and na epoch',(){
    expect(PineScalarPrimitives.formatTime(0,format:'yyyy-MM-dd HH:mm:ss',timezone:'UTC'),'1970-01-01 00:00:00');
    expect(PineScalarPrimitives.formatTime(0,format:'yyyy-MM-dd HH:mm',timezone:'UTC-05:30'),'1969-12-31 18:30');
    expect(PineScalarPrimitives.formatTime(null,format:'MM-dd',timezone:'UTC'),'01-01');
    expect(PineScalarPrimitives.formatTime(DateTime.utc(2024,2,29,23,59).millisecondsSinceEpoch,
        format:'yyyy-MM-dd HH:mm',timezone:'UTC+1'),'2024-03-01 00:59');
    expect(()=>PineScalarPrimitives.formatTime(0,format:'yyyy',timezone:'America/New_York'),throwsA(isA<PineRuntimeException>()));
    expect(()=>PineScalarPrimitives.formatTime(0,format:'MMMM',timezone:'UTC'),throwsA(isA<PineRuntimeException>()));
  });
  test('color transparency endpoints, midpoint, replacement and na',(){
    const red=PineRgba(255,0,0,23);
    expect(PineScalarPrimitives.withTransparency(red,0)!.argb,0xFFFF0000);
    expect(PineScalarPrimitives.withTransparency(red,50)!.argb,0x80FF0000);
    expect(PineScalarPrimitives.withTransparency(red,100)!.argb,0x00FF0000);
    expect(PineScalarPrimitives.withTransparency(null,0),isNull);
    expect(PineScalarPrimitives.withTransparency(red,null),isNull);
    expect(()=>PineScalarPrimitives.withTransparency(red,101),throwsA(isA<PineRuntimeException>()));
  });
}
