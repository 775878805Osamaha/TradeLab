import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/pine_v6_frontend.dart';
import 'package:tradelab_flutter/chart/pine_v6_language_runtime.dart';
import 'package:tradelab_flutter/chart/pine_runtime_core.dart';

PineFrontendResult prepare(String body)=>const PineV6Frontend().prepare(
    '//@version=6\nstrategy("Registry")\n$body');
PineSemanticResult full(String source){
  final lexed=const PineV6Lexer().lex(source);
  expect(lexed.diagnostics,isEmpty);
  final parsed=PineV6Parser(lexed.tokens).parse();
  expect(parsed.diagnostics,isEmpty);
  return PineV6SemanticAnalyzer.forDiagnosticAudit().analyze(parsed.ast);
}
void main(){
  test('typed known library symbols, both time forms and both lookahead values',(){
    final r=prepare('int stamp = time\nint sessionTime = time("60","0700-2000")\n'
        'string tickerId = ticker.heikinashi(ticker.standard(syminfo.tickerid))\n'
        'float a = request.security(tickerId,"60",close,lookahead=barmerge.lookahead_on)\n'
        'float b = request.security(tickerId,"60",close,lookahead=barmerge.lookahead_off)\n'
        'float c = strategy.closedtrades.exit_price(0)\n'
        'var table t = table.new(position.top_right,2,2)\n'
        'table.cell(t,0,0,"ok",text_size=size.small)\n'
        'strategy.entry("L",strategy.long)\nstrategy.exit("X","L",stop=close)\n'
        'alert("ok",alert.freq_once_per_bar_close)');
    expect(r.hasErrors,isFalse,reason:r.diagnostics.join('\n'));
    expect(r.semantic.diagnostics.where((d)=>d.code=='known_unimplemented'),isNotEmpty);
    expect(r.canExecute,isFalse);
  });
  test('generic map value and previous-value return are typed, not unknown',(){
    final r=prepare('var map<int,float> m = map.new<int,float>()\n'
        'float a = map.get(m,1)\nfloat b = map.put(m,1,2.5)');
    expect(r.hasErrors,isFalse,reason:r.diagnostics.join('\n'));
    final calls=r.semantic.inferred.entries.where((e)=>e.key is PineCallExpression);
    expect(calls.where((e)=>(e.key as PineCallExpression).name=='map.get').single.value.type,PineBaseType.floatType);
    expect(calls.where((e)=>(e.key as PineCallExpression).name=='map.put').single.value.type,PineBaseType.floatType);
    for(final bad in ['map.get(m,"key")','map.put(m,1,"value")','map.get(3,1)']){
      expect(prepare('var map<int,float> m = map.new<int,float>()\n$bad').hasErrors,isTrue,reason:bad);
    }
  });
  test('known signature rejects incorrect types, names and arity',(){
    for(final bad in ['time(2)','time("60",bogus="x")','ticker.heikinashi(2)',
      'strategy.closedtrades.exit_price(2.5)','strategy.entry("L",true)',
      'strategy.exit("X",bogus=close)','table.new(position.top_right,2)',
      'table.cell(3,0,0)','input.bool(3)','request.security("X","60",close,lookahead=true)']){
      final r=prepare(bad);
      expect(r.hasErrors,isTrue,reason:bad);
    }
  });
  test('inject exact typo variants in memory; original fixture never written',(){
    final source=File('test/fixtures/pine/ahv10.pine').readAsStringSync();
    final replacements={
      'ta.ema':'ta.emaa','str.contains':'str.containz','strategy.entry':'strategy.entri',
      'table.cell':'table.celll','map.get':'map.gett','ticker.standard':'ticker.standart',
      'barmerge.lookahead_off':'barmerge.lookahead_offf',
      'strategy.closedtrades.exit_price':'strategy.closedtrades.exit_pricee',
      'position.top_right':'position.topright',
      'alert.freq_once_per_bar_close':'alert.freq_once_per_bar_closee',
    };
    for(final entry in replacements.entries){
      expect(source,contains(entry.key));
      final result=full(source.replaceFirst(entry.key,entry.value));
      expect(result.completed,isTrue);
      expect(result.diagnostics.any((d)=>
          (d.code=='unknown_function'||d.code=='undefined_name')&&
          d.message.contains(entry.value)),isTrue,reason:entry.value);
    }
    expect(File('test/fixtures/pine/ahv10.pine').readAsStringSync(),source);
    final original=full(source);
    expect(original.completed,isTrue);
    expect(original.lastVisitedLine,443);
    expect(original.diagnostics.where((d)=>d.severity==PineDiagnosticSeverity.error),isEmpty,
        reason:original.diagnostics.join('\n'));
    expect(original.diagnostics.where((d)=>d.code=='syntax_only'),hasLength(17));
  });
  test('recognized unsupported calls cannot enter existing execution paths',(){
    for(final body in ['x = time("60","0700-2000")','x = ticker.standard("X")',
      'var table t = table.new(position.top_right,1,1)',
      'var map<int,float> m = map.new<int,float>()','strategy.entry("L",strategy.long)']){
      final source='//@version=6\nindicator("Guard")\n$body\nplot(close)';
      final r=const PineV6Frontend().prepare(source);
      expect(r.hasErrors,isFalse,reason:r.diagnostics.join('\n'));
      expect(r.canExecute,isFalse);
      expect(()=>r.evaluateSupported([]),throwsA(isA<PineFrontendExecutionException>()));
      expect(()=>PineV6LanguageProgram.compile(source),throwsA(isA<PineRuntimeException>()));
    }
  });
}
