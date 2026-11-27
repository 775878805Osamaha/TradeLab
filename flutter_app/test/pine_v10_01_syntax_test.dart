import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/pine_v6_frontend.dart';
import 'package:tradelab_flutter/chart/pine_v6_language_runtime.dart';
import 'package:tradelab_flutter/chart/pine_runtime_core.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

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

// Preserve frontend/AST assertions; newly executable syntax must now prove values.
List<List<double?>> executes(String body,List<String> plots,{int count=40}){
  final source='//@version=6\nindicator("syntax execution")\n$body\n'+
      plots.map((p)=>'plot($p)').join('\n');
  final p=PineV6LanguageProgram.compile(source);
  expect(p.legacy,isNull);
  final bars=List.generate(count,(_)=>const TradeCandle(10,11,9,10));
  return p.evaluate(bars).map((p)=>p.values).toList();
}

void main(){
  test('tuple declaration AST spans, order, typed literal outputs',(){
    final r=prepare('f() => [1, close, true]\n[a, b, c] = f()\nx = a + b\nflag = c and true');
    expect(r.hasErrors,isFalse,reason:r.diagnostics.join('\n'));
    final node=r.ast.statements[2] as PineTupleDeclarationStatement;
    expect(node.targets.map((x)=>x.name),['a','b','c']);
    expect(node.targets.map((x)=>x.span.column),[2,5,8]);
    expect(node.span.line,4);
    expect(node.toJson()['node'],'tuple_declare');
    expect(node.value,isA<PineCallExpression>());
    final fn=r.ast.statements[1] as PineFunctionStatement;
    expect((fn.body.single as PineExpressionStatement).expression,isA<PineTupleExpression>());
    final use=r.ast.statements[3] as PineVariableStatement;
    expect(r.semantic.inferred[use.value]!.type,PineBaseType.floatType);
    expect(r.semantic.inferred[use.value]!.qualifier,PineQualifier.series);
    expect(executes('f() => [1,2]\n[a, b] = f()', ['a','b'],count:2), [[1,1],[2,2]]);
  });
  test('known tuple signatures execute verified values; unsupported tuples stay gated',(){
    final macd=executes('[a,b,c] = ta.macd(close,12,26,9)', ['a','b','c']);
    expect(macd[0], [for(var i=0;i<40;i++) i<25?null:0]);
    for(final p in macd.skip(1)){
      expect(p, [for(var i=0;i<40;i++) i<33?null:0]);
    }
    final dmi=executes('[a,b,c] = ta.dmi(14,14)', ['a','b','c']);
    for(final p in dmi.take(2)){
      expect(p,[for(var i=0;i<40;i++) i<14?null:0]);
    }
    expect(dmi[2],[for(var i=0;i<40;i++) i<27?null:0]);
    final st=executes('[a,b] = ta.supertrend(3,10)', ['a','b']);
    expect(st[0],[for(var i=0;i<40;i++) i==0?0:i<9?null:16]);
    expect(st[1],List.filled(40,1));
    refuses('[a,b,c] = ta.bb(close,20,2)');
    refuses('[a, b] = request.security("X", "60", [open, close])');
    expect(executes('f() => [1, true]\n[a,b] = f()\nflag = b and true',
      ['a','flag ? 1 : 0'],count:2),[[1,1],[1,1]]);
  });
  test('tuple arity and scalar reject at exact location',(){
    final a=error(prepare('[a,b] = ta.macd(close,12,26,9)'),'tuple_arity');
    expect([a.line,a.column],[3,1]);
    final b=error(prepare('[a,b] = 1'),'tuple_required');
    expect([b.line,b.column],[3,9]);
    expect(error(prepare('[a,b] = [1,2]'),'tuple_source').line,3);
    expect(error(prepare('[a,b] = request.security("X","60",close)'),'tuple_required').line,3);
  });
  test('tuple duplicate and reassign errors; repeated discard allowed',(){
    final d=error(prepare('[a, a] = ta.supertrend(3,10)'),'duplicate_name');
    expect([d.line,d.column],[3,5]);
    expect(error(prepare('a = 1\n[a,b] = ta.supertrend(3,10)'),'duplicate_name').line,4);
    final q=error(prepare('[a,b] := [1,2]'),'tuple_reassignment');
    expect([q.line,q.column],[3,7]);
    expect(executes('[_, _, x] = ta.macd(close,12,26,9)', ['x']).single,
      [for(var i=0;i<40;i++) i<33?null:0]);
    expect(error(prepare('[_, x] = ta.supertrend(3,10)\ny = _'),'undefined_name').line,4);
  });
  test('tuple invalid target and local scope diagnostics',(){
    final d=error(prepare('[a, 2] = [1,2]'),'expected_identifier');
    expect([d.line,d.column],[3,5]);
    expect(error(prepare('if true\n    [a,b] = ta.supertrend(3,10)\nx = a'),'undefined_name').line,5);
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
    expect(executes('a = 1, b = a + 1', ['a','b'],count:2),[[1,1],[2,2]]);
    expect(executes('f() => a = 1, [a, close]\n[x,y] = f()', ['x','y'],count:2),[[1,1],[10,10]]);
  });
  test('comma sequence still checks scope and errors',(){
    final d=error(prepare('if true\n    a = 1, b = missing'),'undefined_name');
    expect([d.line,d.column],[4,16]);
    final trailing=error(prepare('a = 1,'),'expected_sequence_statement');
    expect(trailing.line,3);
    expect(error(prepare('if true\n    a = 1, plot(close)'),'plot_local_scope').line,4);
  });
  test('unsupported notices do not consume semantic error capacity',(){
    final body=List.generate(50,(i)=>'a$i = int(close)').join('\n');
    final r=prepare('$body\nbad = missing');
    final d=error(r,'undefined_name');
    expect([d.line,d.column],[53,7]);
    expect(r.semantic.diagnostics.where((d)=>d.code=='syntax_only'),hasLength(48));
    expect(r.hasErrors,isTrue);
  });
  test('na literal and callable are distinct; int cast parses and executes',(){
    final r=prepare('float a = na\nx = na(a)\ny = int(close)');
    expect(r.hasErrors,isFalse,reason:r.diagnostics.join('\n'));
    expect((r.ast.statements[1] as PineVariableStatement).value,isA<PineLiteralExpression>());
    final call=(r.ast.statements[2] as PineVariableStatement).value as PineCallExpression;
    expect(call.name,'na');
    expect(r.semantic.inferred[call]!.type,PineBaseType.boolType);
    final cast=(r.ast.statements[3] as PineVariableStatement).value;
    expect(r.semantic.inferred[cast]!.type,PineBaseType.intType);
    expect(executes('x = int(close / 3)', ['x'],count:2),[[3,3]]);
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
    expect(executes('var map<int,float> m = map.new<int,float>()\nmap.put(m,1,close)', ['map.get(m,1)'],count:2),[[10,10]]);
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
