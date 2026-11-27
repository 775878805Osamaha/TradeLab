import 'dart:collection';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/pine_v6_frontend.dart';
import 'package:tradelab_flutter/chart/pine_v6_language_runtime.dart';
import 'package:tradelab_flutter/chart/pine_runtime_core.dart';
import 'package:tradelab_flutter/chart/chart_indicator_library.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

PineFrontendResult prepare(String body)=>const PineV6Frontend().prepare(
    '//@version=6\nstrategy("Registry")\n$body');
PineSemanticResult full(String source){
  final lexed=const PineV6Lexer().lex(source);
  expect(lexed.diagnostics,isEmpty);
  final parsed=PineV6Parser(lexed.tokens).parse();
  expect(parsed.diagnostics,isEmpty);
  return PineV6SemanticAnalyzer.forDiagnosticAudit().analyze(parsed.ast);
}
// A rejection must happen before either evaluator touches chart data.
class _UnreadableBars extends ListBase<TradeCandle> {
  int reads=0;
  Never _read(){reads++;throw StateError('Execution accessed candles before rejection');}
  @override int get length=>_read();
  @override set length(int value)=>throw StateError('Unexpected mutation');
  @override TradeCandle operator [](int index)=>_read();
  @override void operator []=(int index,TradeCandle value)=>throw StateError('Unexpected mutation');
}

void assertRejectedBeforeEvaluation(String source,String symbol){
  final checked=const PineV6Frontend().prepare(source);
  expect(checked.hasErrors,isFalse,reason:checked.diagnostics.join('\n'));
  expect(checked.semantic.diagnostics.any((d)=>d.code=='known_unimplemented'&&
      d.message.endsWith(': '+symbol)),isTrue,reason:symbol);
  expect(checked.status,PineFrontendStatus.parsedButNotExecutable);
  expect(checked.legacyProgram,isNull,reason:'No legacy fallback');
  expect(checked.canExecute,isFalse);
  final bars=_UnreadableBars();
  expect(()=>checked.evaluateSupported(bars),throwsA(
      isA<PineFrontendExecutionException>().having((e)=>e.message,'message',
        contains('runtime not implemented yet'))));
  expect(()=>PineV6LanguageProgram.compile(source).evaluate(bars),throwsA(
      isA<PineRuntimeException>().having((e)=>e.code,'code',startsWith('unsupported_'))));
  expect(bars.reads,0,reason:'No partial evaluation');
  final saved=ChartSavedIndicatorScript(id:'guard',name:'Guard',source:source);
  expect(saved.supportedIndicator(),isNull,reason:'No saved-indicator fallback');
  expect(saved.compileError,contains('unsupported_'));
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
  group('Exact typo rejection (in-memory fixture)',(){
    final replacements={
      'ta.ema':'ta.emaa','str.contains':'str.containz','strategy.entry':'strategy.entri',
      'table.cell':'table.celll','map.get':'map.gett','ticker.standard':'ticker.standart',
      'barmerge.lookahead_off':'barmerge.lookahead_offf',
      'strategy.closedtrades.exit_price':'strategy.closedtrades.exit_pricee',
      'position.top_right':'position.topright',
      'alert.freq_once_per_bar_close':'alert.freq_once_per_bar_closee',
    };
    for(final entry in replacements.entries){
      test('rejects ${entry.value}',(){
        final file=File('test/fixtures/pine/ahv10.pine');
        final source=file.readAsStringSync();
        expect(source,contains(entry.key));
        final result=full(source.replaceFirst(entry.key,entry.value));
        expect(result.completed,isTrue);
        expect(result.diagnostics.any((d)=>
            (d.code=='unknown_function'||d.code=='undefined_name')&&
            d.message.contains(entry.value)),isTrue,reason:entry.value);
        expect(file.readAsStringSync(),source);
      });
    }
  });
  test('original fixture remains error-free and retains syntax-only notices',(){
    final source=File('test/fixtures/pine/ahv10.pine').readAsStringSync();
    final original=full(source);
    expect(original.completed,isTrue);
    expect(original.lastVisitedLine,443);
    expect(original.diagnostics.where((d)=>d.severity==PineDiagnosticSeverity.error),isEmpty,
        reason:original.diagnostics.join('\n'));
    // Three TA tuple declarations now execute; the two security tuples and
    // all other unsupported syntax are still diagnosed.
    expect(original.diagnostics.where((d)=>d.code=='syntax_only'),hasLength(14));
    final lines=source.split('\n');
    for(final name in ['ta.macd','ta.dmi','ta.supertrend']){
      final index=lines.indexWhere((l)=>l.startsWith('[')&&l.contains(name+'('));
      expect(index,greaterThanOrEqualTo(0));
      expect(original.diagnostics.any((d)=>d.code=='syntax_only'&&d.line==index+1),isFalse);
    }
    for(var i=0;i<lines.length;i++){
      if(lines[i].startsWith('[')&&lines[i].contains('request.security(')){
        expect(original.diagnostics.any((d)=>d.code=='syntax_only'&&d.line==i+1),isTrue);
      }
    }
  });
  test('recognized unsupported calls cannot enter existing execution paths',(){
    for(final body in ['x = time("60","0700-2000")','x = ticker.standard("X")',
      'var table t = table.new(position.top_right,1,1)',
      'strategy.entry("L",strategy.long)']){
      final source='//@version=6\nindicator("Guard")\n$body\nplot(close)';
      final r=const PineV6Frontend().prepare(source);
      expect(r.hasErrors,isFalse,reason:r.diagnostics.join('\n'));
      expect(r.canExecute,isFalse);
      expect(()=>r.evaluateSupported([]),throwsA(isA<PineFrontendExecutionException>()));
      expect(()=>PineV6LanguageProgram.compile(source),throwsA(isA<PineRuntimeException>()));
    }
  });
  // Test each of the sixteen formerly unresolved documented names on a
  // small script with a supported numeric plot before the forbidden call.
  final cases=<String,String>{
    'ticker.standard':'x = ticker.standard("X")',
    'ticker.heikinashi':'x = ticker.heikinashi("X")',
    'barmerge.lookahead_off':'x = barmerge.lookahead_off',
    'barmerge.lookahead_on':'x = barmerge.lookahead_on',
    'time':'x = time("60","0700-2000")',
    'strategy.closedtrades.exit_price':'x = strategy.closedtrades.exit_price(0)',
    'strategy.closedtrades.entry_price':'x = strategy.closedtrades.entry_price(0)',
    'strategy.closedtrades.size':'x = strategy.closedtrades.size(0)',
    'position.top_right':'x = position.top_right',
    'table.new':'var table t = table.new(position.top_right,1,1)',
    'table.cell':'var table t = table.new(position.top_right,1,1)\ntable.cell(t,0,0,"ok")',
    'strategy.entry':'strategy.entry("L",strategy.long)',
    'alert.freq_once_per_bar_close':'x = alert.freq_once_per_bar_close',
    'strategy.exit':'strategy.exit("X","L",stop=close)',
  };
  for(final entry in cases.entries){
    test('D rejects before reading a candle: ${entry.key}',(){
      final header=entry.key.startsWith('strategy.')?'strategy("Guard")':'indicator("Guard")';
      assertRejectedBeforeEvaluation('//@version=6\n$header\nplot(close)\n${entry.value}',entry.key);
    });
  }
  test('D map get/put now execute, missing key and prior value preserved',(){
    const source='''//@version=6
indicator("Map")
var map<int,float> m = map.new<int,float>()
old = map.put(m,1,close)
plot(old)
plot(map.get(m,1))
plot(map.get(m,2))''';
    final r=const PineV6Frontend().prepare(source);
    expect(r.hasErrors,isFalse,reason:r.diagnostics.join('\n'));
    expect(r.canExecute,isFalse,reason:'Standalone legacy route still gated');
    final p=PineV6LanguageProgram.compile(source);
    expect(p.legacy,isNull);
    final v=p.evaluate([const TradeCandle(1,3,0,2),const TradeCandle(2,4,1,3)]);
    expect(v.map((p)=>p.values).toList(),[[null,2],[2,3],[null,null]]);
  });
  test('D rejects unsupported call in unreachable branch before execution',(){
    assertRejectedBeforeEvaluation(
        '//@version=6\nindicator("Guard")\nplot(close)\nif false\n    x = ticker.standard("X")',
        'ticker.standard');
  });
  test('D rejects unsupported call in unused function before execution',(){
    assertRejectedBeforeEvaluation(
        '//@version=6\nindicator("Guard")\nf() => ticker.standard("X")\nplot(close)',
        'ticker.standard');
  });

}
