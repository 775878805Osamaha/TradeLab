import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/pine_v6_frontend.dart';
import 'package:tradelab_flutter/chart/pine_subset_program.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

List<TradeCandle> _bars() => List.generate(16, (i) {
  final close=20.0 + ((i*i)%7) + i/3;
  return TradeCandle(close,close+1,close-1,close);
});
void main(){
  const front=PineV6Frontend();
  bool hasCode(PineFrontendResult r,String code) =>
      r.diagnostics.any((d)=>d.code==code);

  test('lexer preserves line/column, indent/dedent, comments and colors',(){
    final lex=const PineV6Lexer().lex('''//@version=6
indicator("Demo")
var color ink = #FF0088
if close > open
    ink := color.red // source color
plot(close, title="C")''');
    expect(lex.diagnostics,isEmpty);
    expect(lex.tokens.where((t)=>t.kind==PineTokenKind.indent),hasLength(1));
    expect(lex.tokens.where((t)=>t.kind==PineTokenKind.dedent),hasLength(1));
    final assign=lex.tokens.firstWhere((t)=>t.text==':=');
    expect(assign.span.line,5);
    expect(assign.span.column,9);
    expect(lex.tokens.any((t)=>t.kind==PineTokenKind.color&&
        t.text=='#FF0088'),isTrue);
    expect(lex.tokens.last.kind,PineTokenKind.eof);
  });

  test('lexer supports parentheses continuation and unparenthesized line wrap',(){
    const sample='''indicator("Wrap")
x = (open +
    high +
        close) / 3
y = close +
  open
plot(x + y)''';
    final result=const PineV6Lexer().lex(sample);
    expect(result.diagnostics,isEmpty);
    expect(result.tokens.where((t)=>t.kind==PineTokenKind.indent),isEmpty);
    expect(front.prepare(sample).status,PineFrontendStatus.parsedButNotExecutable);
  });

  test('lexer supports escaped strings, exponents, operators and triple quotes',(){
    final lex=const PineV6Lexer().lex(
      'indicator("""multi\nline""")\na = 1.2e-3 >= 0.0 and true\n');
    expect(lex.diagnostics,isEmpty);
    expect(lex.tokens.any((t)=>t.text=='1.2e-3'),isTrue);
    expect(lex.tokens.any((t)=>t.text=='>='),isTrue);
    expect(lex.tokens.where((t)=>t.kind==PineTokenKind.string).first.text,
      contains('multi\nline'));
  });

  test('lexer reports source positions for invalid indentation and colors',(){
    final result=const PineV6Lexer().lex('indicator("X")\nif true\n  plot(#123)\n');
    expect(result.diagnostics.map((e)=>e.code),
      containsAll(['indent_width','invalid_color']));
    expect(result.diagnostics.first.line,3);
  });

  test('AST builds typed var/varip, := and nested if with history',(){
    final code='''indicator("Types")
var int count = 0
varip float last = na
if close > open
    count := count + 1
    last := close[1]
plot(count)''';
    final parsed=front.prepare(code);
    expect(parsed.hasErrors,isFalse,reason:parsed.message);
    expect(parsed.status,PineFrontendStatus.parsedButNotExecutable);
    final statements=parsed.ast.statements;
    expect(statements[1],isA<PineVariableStatement>());
    expect((statements[1] as PineVariableStatement).mode,'var');
    expect((statements[2] as PineVariableStatement).mode,'varip');
    final branch=statements[3] as PineIfStatement;
    expect(branch.thenBody,hasLength(2));
    final assign=branch.thenBody[1] as PineAssignmentStatement;
    expect(assign.value,isA<PineHistoryExpression>());
    final tree=jsonDecode(parsed.ast.snapshot);
    expect(tree['body'][3]['node'],'if');
    expect(tree['body'][3]['then'][1]['value']['node'],'history');
  });

  test('AST parses switch, for/while, function body and named arguments',(){
    final code='''indicator("Flow")
choose(float a, float b = 2) =>
    result = a + b
    result
var int total = 0
for i = 0 to 3 by 1
    total += i
while total < 10
    total := total + 1
switch total
    2 => total
    => choose(a=close, b=3)
plot(total)''';
    final result=front.prepare(code);
    expect(result.hasErrors,isFalse,reason:result.message);
    expect(result.status,PineFrontendStatus.parsedButNotExecutable);
    expect(result.ast.statements.whereType<PineFunctionStatement>(),hasLength(1));
    expect(result.ast.statements.whereType<PineForStatement>(),hasLength(1));
    expect(result.ast.statements.whereType<PineWhileStatement>(),hasLength(1));
    final sw=result.ast.statements.whereType<PineSwitchStatement>().single;
    expect(sw.arms,hasLength(2));
    final call=(sw.arms.last.body.single as PineExpressionStatement).expression
      as PineCallExpression;
    expect(call.arguments.map((a)=>a.name),['a','b']);
  });

  test('AST stores ternary condition and member calls',(){
    final result=front.prepare('''indicator("Conditional")
x = close > open ? ta.ema(close, 3) : math.abs(open-close)
plot(x)''');
    expect(result.hasErrors,isFalse,reason:result.message);
    final declaration=result.ast.statements[1] as PineVariableStatement;
    final expr=declaration.value as PineTernaryExpression;
    expect((expr.thenValue as PineCallExpression).name,'ta.ema');
    expect((expr.elseValue as PineCallExpression).name,'math.abs');
  });

  test('parser error recovery emits two independent locations',(){
    final result=front.prepare('''indicator("Bad")
a = )
b = ?
plot(close)''');
    expect(result.hasErrors,isTrue);
    expect(result.diagnostics.where((e)=>e.stage==PineDiagnosticStage.parser)
      .length,greaterThanOrEqualTo(2));
    expect(result.diagnostics.every((e)=>e.line>=1&&e.column>=1),isTrue);
  });

  test('semantic reports undefined names and scope-local variable escapes',(){
    final result=front.prepare('''indicator("Scope")
if close > open
    int local = 3
x = local + missing
plot(close)''');
    expect(result.hasErrors,isTrue);
    expect(result.diagnostics.where((d)=>d.code=='undefined_name').length,
      greaterThanOrEqualTo(2));
  });

  test('semantic rejects same-scope redeclarations and type mismatch',(){
    final result=front.prepare('''indicator("Mismatch")
int x = 1
float x = 2
bool flag = close
plot(x)''');
    expect(hasCode(result,'duplicate_name'),isTrue);
    expect(hasCode(result,'type_mismatch'),isTrue);
  });

  test('semantic checks qualifier lattice const input simple series',(){
    final bad=front.prepare('''indicator("Qualifiers")
const float price = close
input int length = input.int(4)
plot(price)''');
    expect(hasCode(bad,'qualifier_mismatch'),isTrue);
    final ok=front.prepare('''indicator("Qualifiers")
input int length = input.int(4)
series float price = close
plot(ta.sma(price, length))''');
    expect(ok.hasErrors,isFalse,reason:ok.message);
    expect(ok.canExecute,isFalse);
  });

  test('semantic blocks plot and plotshape inside local if/function scopes',(){
    final a=front.prepare('''indicator("Local plot")
if close > open
    plot(close)
plot(close)''');
    expect(hasCode(a,'plot_local_scope'),isTrue);
    final b=front.prepare('''indicator("Local shape")
f(float x) =>
    plotshape(x)
plot(close)''');
    expect(hasCode(b,'plot_local_scope'),isTrue);
    expect(b.diagnostics.firstWhere((d)=>d.code=='plot_local_scope').line,3);
  });

  test('semantic rejects illegal function reassignment of global state',(){
    final checked=front.prepare('''indicator("Globals")
var int counter = 0
increase() =>
    counter := counter + 1
plot(counter)''');
    expect(hasCode(checked,'function_global_reassignment'),isTrue);
  });

  test('semantic rejects bool na and incompatible ternary branches',(){
    final checked=front.prepare('''indicator("Bad Types")
bool enabled = na
x = close > open ? "str" : 1
plot(close)''');
    expect(hasCode(checked,'bool_na'),isTrue);
    expect(hasCode(checked,'ternary_type'),isTrue);
  });

  test('unsupported but well-formed Pine returns clean refusal, never fake execution',(){
    final checked=front.prepare('''//@version=6
indicator("Loop")
var int x = 0
for i = 0 to 3
    x += i
plot(x)''');
    expect(checked.status,PineFrontendStatus.parsedButNotExecutable,
      reason:checked.message);
    expect(checked.diagnostics.last.code,'not_yet_supported');
    expect(()=>checked.evaluateSupported(_bars()),
      throwsA(isA<PineFrontendExecutionException>()));
  });

  test('all three frontend passes enforce cooperative deadlines',(){
    const source='''indicator("Budgets")
plot(close)''';
    final lex=const PineV6Lexer(maxDuration:Duration.zero).lex(source);
    expect(lex.diagnostics.map((d)=>d.code),contains('lexer_timeout'));

    final many='indicator("Many")\n'+List.generate(
      100,(i)=>'v'+i.toString()+' = '+i.toString()).join('\n')+
      '\nplot(close)';
    final tokens=const PineV6Lexer().lex(many).tokens;
    final parsed=PineV6Parser(tokens,maxDuration:Duration.zero).parse();
    expect(parsed.diagnostics.map((d)=>d.code),contains('parser_timeout'));

    final complete=PineV6Parser(tokens).parse();
    final semantic=PineV6SemanticAnalyzer(
      maxDuration:Duration.zero).analyze(complete.ast);
    expect(semantic.diagnostics.map((d)=>d.code),
      contains('semantic_timeout'));
  });

  test('source budget rejects large untrusted input without running it',(){
    final checked=front.prepare(List.filled(61000,'a').join());
    expect(checked.status,PineFrontendStatus.invalid);
    expect(hasCode(checked,'source_limit'),isTrue);
  });

  test('semantic error messages include exact line and column',(){
    final checked=front.prepare('''indicator("Where")
x = unknown
plot(close)''');
    final error=checked.diagnostics.firstWhere((d)=>d.code=='undefined_name');
    expect(error.line,2);
    expect(error.column,5);
    expect(error.toString(),contains('2:5'));
  });

  test('old executable subset matches bulk evaluator for every fixture',(){
    final sources=<String>[
      '''indicator("MA", overlay=true)
n = input.int(3, "N")
a = ta.sma(close,n)
b = ta.ema(close,4)
plot(a,"SMA",color=color.orange,linewidth=3)
plot(b,"EMA",style=plot.style_histogram)''',
      '''indicator("Momentum",overlay=false)
r = ta.rsi(close,3)
plot(r)
plot(ta.roc(close,2))''',
      '''indicator("Range",overlay=false)
hi = ta.highest(high,3)
lo = ta.lowest(low,3)
plot(hi-lo)
plot(ta.change(close,2))''',
      '''indicator("Arithmetic",overlay=true)
prior = close[1]
diff = (high + low + close)/3-prior
plot(nz(diff,-1))
plot(math.max(open,close))''',
      '''indicator("Absolute and minima",overlay=true)
distance = math.abs(close-open)
support = math.min(low,open)
plot(distance)
plot(support)''',
    ];
    final candles=_bars();
    for(final source in sources) {
      final result=front.prepare(source);
      expect(result.canExecute,isTrue,reason:result.message);
      final baseline=PineSubsetProgram.compile(source).evaluate(candles);
      final updated=result.evaluateSupported(candles);
      expect(updated.length,baseline.length);
      for(var p=0;p<baseline.length;p++){
        expect(updated[p].values,baseline[p].values,
          reason:'Plot '+p.toString());
        expect(updated[p].title,baseline[p].title);
        expect(updated[p].width,baseline[p].width);
        expect(updated[p].argbColor,baseline[p].argbColor);
        expect(updated[p].histogram,baseline[p].histogram);
      }
    }
  });
  test('explicit Pine version 5 is rejected before numeric subset execution',(){
    const source='//@version=5\nindicator("Old")\nplot(close)';
    final result=front.prepare(source);
    expect(result.canExecute,isFalse);
    expect(result.status,PineFrontendStatus.invalid);
    final diagnostic=result.diagnostics.firstWhere((d)=>
        d.code=='version_mismatch');
    expect(diagnostic.line,1);
    expect(diagnostic.column,1);
    expect(diagnostic.message,contains('v6'));
    expect(() => result.evaluateSupported(_bars()),
        throwsA(isA<PineFrontendExecutionException>()));
  });

  test('explicit v6 and untagged supported numeric scripts remain executable',(){
    const body='indicator("Tagged")\nplot(ta.sma(close, 3))';
    for(final source in <String>['//@version=6\n'+body,body]){
      final result=front.prepare(source);
      expect(result.canExecute,isTrue,reason:result.message);
      expect(result.diagnostics,isEmpty);
      final legacy=PineSubsetProgram.compile(source).evaluate(_bars());
      final actual=result.evaluateSupported(_bars());
      expect(actual.single.values,legacy.single.values);
    }
  });

  test('v6 named function arguments bind declared parameters in any order',(){
    final report=front.prepare('''//@version=6
indicator("Named args")
combine(int first, simple float second = 2.0) =>
    first + second
result = combine(second=3.0, first=2)
plot(close)''');
    expect(report.hasErrors,isFalse,reason:report.message);
    expect(report.status,PineFrontendStatus.parsedButNotExecutable,
        reason:'User functions remain Stage 3 runtime work');
    expect(report.diagnostics.any((e)=>e.code=='not_yet_supported'),isTrue);
  });

  test('semantic analyzer checks unknown, missing, duplicate, wrong-type '
      'and too-strong-qualifier function arguments',(){
    final report=front.prepare('''//@version=6
indicator("Argument validation")
combine(int first, simple float second = 2.0) =>
    first + second
badName = combine(first=2, unexpected=3)
badType = combine(first="wrong")
missingRequired = combine(second=3.0)
duplicateProvided = combine(2, first=3)
tooStrong = combine(first=2, second=close)
plot(close)''');
    final codes=report.diagnostics.map((e)=>e.code).toList();
    expect(codes,containsAll(<String>[
      'unknown_named_argument',
      'function_argument_type',
      'missing_function_argument',
      'duplicate_parameter_argument',
      'function_argument_qualifier',
    ]),reason:report.message);
    expect(report.hasErrors,isTrue);
    expect(report.canExecute,isFalse);
    expect(report.diagnostics.every((e)=>e.line>0&&e.column>0),isTrue);
  });

}
