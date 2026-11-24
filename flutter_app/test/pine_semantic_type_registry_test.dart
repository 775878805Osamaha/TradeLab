import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/pine_v6_frontend.dart';

PineFrontendResult prepare(String source)=>const PineV6Frontend().prepare(source);
Iterable<PineDiagnostic> errors(PineFrontendResult r)=>r.diagnostics
    .where((d)=>d.severity==PineDiagnosticSeverity.error);

void main(){
  test('math.max selects exact numeric overload and qualifier',(){
    final r=prepare('int a = math.max(2, 3)\nfloat b = math.max(2, 3.5)\n'
        'int c = math.max(bar_index, 0)\nfloat d = math.max(close, 1)');
    expect(errors(r),isEmpty);
    final calls=r.semantic.inferred.entries
        .where((e)=>e.key is PineCallExpression).map((e)=>e.value).toList();
    expect(calls.map((t)=>t.type),[PineBaseType.intType,PineBaseType.floatType,
      PineBaseType.intType,PineBaseType.floatType]);
    expect(calls.map((t)=>t.qualifier),[PineQualifier.constant,PineQualifier.constant,
      PineQualifier.series,PineQualifier.series]);
  });
  test('math.max rejects nonnumeric, missing and wrong result type',(){
    for(final source in ['x = math.max(true, 3)','x = math.max("2", 3)',
        'x = math.max()','int x = math.max(2, 3.5)','x = math.max(2, bogus=3)']){
      expect(errors(prepare(source)),isNotEmpty,reason:source);
    }
  });
  test('contains and chart properties return correct typed values',(){
    final r=prepare('bool a = str.contains("GOLD", "G")\n'
        'bool b = str.contains(str="A", source=syminfo.ticker)\n'
        'simple bool c = timeframe.isminutes and chart.is_standard\n'
        'bool d = c and barstate.isconfirmed\n'
        'simple float tick = syminfo.mintick\n'
        'float e = b ? tick : 1.0');
    expect(errors(r),isEmpty);
    final calls=r.semantic.inferred.entries
        .where((e)=>e.key is PineCallExpression).map((e)=>e.value).toList();
    expect(calls.map((t)=>t.type),[PineBaseType.boolType,PineBaseType.boolType]);
    expect(calls.map((t)=>t.qualifier),[PineQualifier.constant,PineQualifier.simple]);
  });
  test('real type errors and invalid contains signatures still fail',(){
    for(final source in ['string x = str.contains("A","A")',
        'x = str.contains(3,"A")','x = str.contains("A")',
        'x = str.contains("A", bogus="B")',
        'bool x = syminfo.mintick','string x = timeframe.isminutes',
        'int x = chart.is_standard','simple bool x = barstate.isconfirmed',
        'x = 10 and true']){
      expect(errors(prepare(source)),isNotEmpty,reason:source);
    }
  });
}
