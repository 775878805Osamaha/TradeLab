import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/pine_v6_frontend.dart';
import 'package:tradelab_flutter/chart/pine_v6_language_runtime.dart';
import 'package:tradelab_flutter/chart/pine_runtime_core.dart';

const frontend=PineV6Frontend();
PineFrontendResult prepare(String body)=>frontend.prepare('//@version=6\nindicator("syntax")\n$body\nplot(close)');
PineDiagnostic error(PineFrontendResult result,String code)=>result.diagnostics.firstWhere((d)=>d.code==code);
void refuses(String body){
  final source='//@version=6\nindicator("syntax")\n$body\nplot(close)';
  final result=frontend.prepare(source);
  expect(result.hasErrors,isFalse,reason:result.diagnostics.join('\n'));
  expect(result.status,PineFrontendStatus.parsedButNotExecutable);
  expect(result.canExecute,isFalse);
  expect(()=>result.evaluateSupported([]),throwsA(isA<PineFrontendExecutionException>()));
  expect(()=>PineV6LanguageProgram.compile(source),throwsA(isA<PineRuntimeException>()));
}

void main(){
  test('tuple declaration AST spans, order, typed literal outputs',(){
    final r=prepare('[a, b, c] = [1, close, true]\nx = a + b\nflag = c and true');
    expect(r.hasErrors,isFalse,reason:r.diagnostics.join('\n'));
    final node=r.ast.statements[1] as PineTupleDeclarationStatement;
    expect(node.targets.map((x)=>x.name),['a','b','c']);
    expect(node.targets.map((x)=>x.span.column),[2,5,8]);
    expect(node.span.line,3);
    expect(node.toJson()['node'],'tuple_declare');
    expect(node.value,isA<PineTupleExpression>());
    final use=r.ast.statements[2] as PineVariableStatement;
    expect(r.semantic.inferred[use.value]!.type,PineBaseType.floatType);
    refuses('[a, b] = [1,2]');
  });
  test('known tuple function signatures: only semantic binding',(){
    for(final expr in ['ta.macd(close, 12, 26, 9)','ta.dmi(14, 14)','ta.bb(close,20,2)']){
      refuses('[a, b, c] = $expr');
    }
    refuses('[a, b] = ta.supertrend(3,10)');
    refuses('[a, b] = request.security("X", "60", [open, close])');
    refuses('f() => [1, true]\n[a,b] = f()\nflag = b and true');
  });
  test('tuple arity and scalar reject at exact location',(){
    final a=error(prepare('[a,b] = [1,2,3]'),'tuple_arity');
    expect([a.line,a.column],[3,1]);
    final b=error(prepare('[a,b] = 1'),'tuple_required');
    expect([b.line,b.column],[3,9]);
    expect(error(prepare('[a,b] = ta.macd(close,12,26,9)'),'tuple_arity').line,3);
  });
  test('tuple duplicate and reassign errors; repeated discard allowed',(){
    final d=error(prepare('[a, a] = [1,2]'),'duplicate_name');
    expect([d.line,d.column],[3,5]);
    expect(error(prepare('a = 1\n[a,b] = [1,2]'),'duplicate_name').line,4);
    final q=error(prepare('[a,b] := [1,2]'),'tuple_reassignment');
    expect([q.line,q.column],[3,7]);
    refuses('[_, _, x] = [1, 2, 3]');
    expect(error(prepare('[_, x] = [1,2]\ny = _'),'undefined_name').line,4);
  });
  test('tuple invalid target and local scope diagnostics',(){
    final d=error(prepare('[a, 2] = [1,2]'),'expected_identifier');
    expect([d.line,d.column],[3,5]);
    expect(error(prepare('if true\n    [a,b] = [1,2]\nx = a'),'undefined_name').line,5);
  });
  test('comma statements preserve order and same lexical scope',(){
    final r=prepare('if true\n    a = math.max(1,2), b = a + 1, alert("ok")');
    expect(r.hasErrors,isFalse,reason:r.diagnostics.join('\n'));
    final node=r.ast.statements[1] as PineIfStatement;
    final seq=node.thenBody.single as PineSequenceStatement;
    expect(seq.statements,hasLength(3));
    expect(seq.toJson()['node'],'sequence');
    expect(seq.statements[0].span.column,5);
    expect(seq.statements[1].span.column,24);
    expect((seq.statements[2] as PineExpressionStatement).expression,isA<PineCallExpression>());
    refuses('a = 1, b = a + 1');
  });
  test('comma sequence still checks scope and errors',(){
    final d=error(prepare('if true\n    a = 1, b = missing'),'undefined_name');
    expect([d.line,d.column],[4,16]);
    final trailing=error(prepare('a = 1,'),'expected_sequence_statement');
    expect(trailing.line,3);
    expect(error(prepare('if true\n    a = 1, plot(close)'),'plot_local_scope').line,4);
  });
  test('na literal and callable are distinct; int cast parses and is gated',(){
    final r=prepare('float a = na\nx = na(a)\ny = int(close)');
    expect(r.hasErrors,isFalse,reason:r.diagnostics.join('\n'));
    expect((r.ast.statements[1] as PineVariableStatement).value,isA<PineLiteralExpression>());
    final call=(r.ast.statements[2] as PineVariableStatement).value as PineCallExpression;
    expect(call.name,'na');
    expect(r.semantic.inferred[call]!.type,PineBaseType.boolType);
    final cast=(r.ast.statements[3] as PineVariableStatement).value;
    expect(r.semantic.inferred[cast]!.type,PineBaseType.intType);
    refuses('x = int(close)');
    expect(error(prepare('x = int("x")'),'cast_type').line,3);
    expect(error(prepare('x = int(1,2)'),'cast_arity').line,3);
  });
  test('typed map declaration and generic constructor AST; comparison unaffected',(){
    final r=prepare('var map<int, float> values = map.new<int, float>()\nx = close < open');
    expect(r.hasErrors,isFalse,reason:r.diagnostics.join('\n'));
    final decl=r.ast.statements[1] as PineReferenceVariableStatement;
    expect(decl.typeName,'map');
    expect(decl.typeArguments.map((t)=>t.name),['int','float']);
    expect(decl.mode,'var');
    final constructor=decl.value as PineCallExpression;
    expect(constructor.name,'map.new');
    expect(constructor.callee,isA<PineGenericReferenceExpression>());
    expect((r.ast.statements[2] as PineVariableStatement).value,isA<PineBinaryExpression>());
    refuses('var map<int,float> m = map.new<int,float>()');
  });
  test('map type mismatch and invalid generic arity diagnosed',(){
    expect(error(prepare('var map<int,float> m = map.new<int,int>()'),'reference_type_mismatch').line,3);
    expect(error(prepare('var map<int> m = na'),'map_type_arity').line,3);
  });
  test('table type parses as reference; table library remains unsupported',(){
    final r=prepare('var table t = table.new(position.top_right,2,3)');
    final node=r.ast.statements[1] as PineReferenceVariableStatement;
    expect(node.typeName,'table');
    expect(r.diagnostics.where((d)=>d.stage==PineDiagnosticStage.parser),isEmpty);
    expect(r.canExecute,isFalse);
    expect(()=>PineV6LanguageProgram.compile('indicator("T")\nvar table t = na\nplot(close)'),throwsA(isA<PineRuntimeException>()));
  });
}
