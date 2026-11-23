import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_indicator_library.dart';
import 'package:tradelab_flutter/chart/pine_frontend.dart';
import 'package:tradelab_flutter/chart/pine_subset_program.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  test('v6 lexer handles indentation, inline comments, colors and operators',
      () {
    final scan = PineLexer.scan('''//@version=6
indicator("Tokens", overlay=true)
var color shade = #FF0088
if close >= open // trailing comment
    shade := color.red
plot(close, title="A")
''');
    expect(scan.version, 6);
    expect(scan.diagnostics, isEmpty);
    expect(scan.tokens.where((t) =>
        t.kind == PineTokenKind.indent), hasLength(1));
    expect(scan.tokens.where((t) =>
        t.kind == PineTokenKind.dedent), hasLength(1));
    expect(scan.tokens.any((t) => t.kind == PineTokenKind.color &&
        t.text == '#FF0088'), isTrue);
    expect(scan.tokens.any((t) => t.text == ':='), isTrue);
    expect(scan.tokens.any((t) => t.text == '>='), isTrue);
    expect(scan.tokens.any((t) => t.text == 'comment'), isFalse);
  });

  test('v6 lexer accepts parentheses-wrapped and operator-wrapped lines '
      'plus triple-quoted multiline strings', () {
    final scan = PineLexer.scan('''//@version=6
indicator("Wrapped")
total = (open +
    high +
    low)
gap = total +
  close
string message = """First
second"""
plot(total, title="OK")
''');
    expect(scan.diagnostics, isEmpty);
    expect(scan.tokens.where((t) =>
        t.kind == PineTokenKind.indent), isEmpty,
        reason: 'Continuation indentation is not a local block');
    expect(scan.tokens.any((t) => t.kind == PineTokenKind.string &&
        t.text.contains('First\nsecond')), isTrue);
    expect(scan.tokens.any((t) => t.text == 'total'), isTrue);
  });

  test('parser AST snapshots cover v6 var/varip, update and named arguments',
      () {
    final result = PineFrontend.analyze('''//@version=6
indicator("Source", overlay=false)
var float accumulator = na
varip int ticks = 0
accumulator := close[1] + math.max(high, low)
plot(accumulator, title="A")
''');
    final snapshot = result.ast.snapshot();
    expect(snapshot, contains('"node":"script"'));
    expect(snapshot, contains('"persistence":"variable"'));
    expect(snapshot, contains('"persistence":"intrabar"'));
    expect(snapshot, contains('"node":"reassignment"'));
    expect(snapshot, contains('"node":"history"'));
    expect(snapshot, contains('"name":"title"'));
    expect(snapshot, contains('"name":"math.max"'));
    expect(result.canExecute, isFalse,
        reason: 'Stage 2 must never execute var or varip');
    expect(result.diagnostics.any((d) =>
        d.code == 'runtime_unavailable'), isTrue);
  });

  test('parser represents functions, if/else, for/while, switch and ternary',
      () {
    final analysis = PineFrontend.analyze('''//@version=6
indicator("Structure")
var float total = na
inc(simple float x, int n = 2) =>
    float y = x + n
    y
if close > open
    total := inc(close, n=2)
else
    total := close
for i = 1 to 4 by 1
    total += i
while total < 100
    total += 2
switch close
    1 => total := close
    => total := open
direction = close > open ? 1 : -1
plot(total)
''');
    final nodes = analysis.ast.statements.map((s) =>
        s.toJson()['node']).toList();
    expect(nodes, containsAll([
      'function', 'if', 'for', 'while', 'switch', 'declaration',
    ]));
    expect(analysis.ast.snapshot(), contains('"node":"ternary"'));
    expect(analysis.hasSyntaxErrors, isFalse,
        reason: analysis.diagnosticMessage ?? '');
    expect(analysis.canExecute, isFalse);
  });

  test('invalid global-only visuals are rejected only when nested in scope',
      () {
    const local = '''//@version=6
indicator("Invalid scope")
if close > open
    plotshape(true)
plot(close)''';
    final report = PineFrontend.analyze(local);
    final errors = report.diagnostics.where((d) =>
        d.code == 'global_only').toList();
    expect(errors, hasLength(1));
    expect(errors.single.line, 4);
    expect(errors.single.column, 5);
    final global = PineFrontend.analyze(
        'indicator("Valid")\nplotshape(close > open)');
    expect(global.diagnostics.any((d) =>
        d.code == 'global_only'), isFalse,
        reason: 'plotshape allowed at global scope, even if unexecutable');
    expect(global.canExecute, isFalse);
  });

  test('semantic diagnostics recover multiple independent errors with spans',
      () {
    final out = PineFrontend.analyze('''indicator("Problems")
bad = missingName
int count = "wrong"
bad = 3
simple float price = close
plot(close)''');
    final codes = out.diagnostics.map((d) => d.code).toList();
    expect(codes, containsAll([
      'unknown_symbol', 'type_mismatch',
      'duplicate_symbol', 'qualifier_mismatch',
    ]));
    expect(out.diagnostics.every((e) =>
        e.line > 0 && e.column > 0), isTrue);
  });

  test('unknown name in local scope and local nested plots are errors', () {
    final report = PineFrontend.analyze('''indicator("Local")
if true
    int temporary = 4
plot(temporary)
''');
    expect(report.diagnostics.any((d) =>
        d.code == 'unknown_symbol' && d.line == 4), isTrue);
  });

  test('invalid history indices, untyped na, bad reassignment and recursion '
      'receive semantic diagnostics', () {
    final report = PineFrontend.analyze('''indicator("Errors")
raw = na
missing := 5
f(int x) =>
    f(x)
bad = close[1.5]
plot(close)
''');
    final codes = report.diagnostics.map((e) => e.code).toList();
    expect(codes, containsAll([
      'na_requires_type', 'unknown_symbol',
      'recursive_function', 'history_index',
    ]));
  });

  test('syntax parser recovery produces multiple errors without throwing',
      () {
    final analysis = PineFrontend.analyze('''indicator("Recover")
first =
second =
plot(close)
''');
    expect(analysis.diagnostics.where((d) =>
        d.kind == PineDiagnosticKind.syntax).length,
        greaterThanOrEqualTo(2));
    expect(analysis.ast.statements, isNotEmpty);
  });

  test('analysis resource guards reject huge input and zero deadline', () {
    final huge = PineFrontend.analyze(
        List<String>.filled(20000, 'x').join());
    expect(huge.diagnostics.any((d) =>
        d.kind == PineDiagnosticKind.resource), isTrue);
    expect(huge.canExecute, isFalse);
    final timed = PineFrontend.analyze('indicator("T")\nplot(close)',
        deadline: Duration.zero);
    expect(timed.diagnostics.any((d) =>
        d.kind == PineDiagnosticKind.resource), isTrue);
    expect(timed.canExecute, isFalse);
  });

  test('unsupported v6 scripts save cleanly without evaluating fake data',
      () {
    const script = ChartSavedIndicatorScript(
      id: 'script-control-flow', name: 'Safe AST',
      source: 'indicator("A")\n'
          'var float n = 1\nif close > open\n    n := n + 1\n'
          'plot(n)',
    );
    expect(script.supportedIndicator(), isNull);
    expect(script.compileError, contains('غير مدعوم'));
    expect(script.frontendAnalysis.canExecute, isFalse);
    expect(script.frontendAnalysis.ast.snapshot(),
        contains('"node":"if"'));
  });


  test('Pine v6 strictly rejects numeric conditions and logical operands', () {
    final bad = PineFrontend.analyze('''//@version=6
indicator("V6 bool")
if close
    plot(close)
value = close ? high : low
flag = close and open
inverse = not high
plot(close)''');
    final mismatches = bad.diagnostics.where((d) =>
        d.code == 'type_mismatch').toList();
    expect(mismatches.length, greaterThanOrEqualTo(4),
        reason: bad.diagnosticMessage);
    expect(mismatches.any((d) => d.line == 3), isTrue);
    expect(mismatches.any((d) => d.line == 5), isTrue);
    expect(mismatches.any((d) => d.line == 6), isTrue);
    expect(mismatches.any((d) => d.line == 7), isTrue);
    expect(bad.canExecute, isFalse);
  });

  test('Pine v6 allows explicit bool casting and boolean expressions', () {
    final valid = PineFrontend.analyze('''//@version=6
indicator("Explicit boolean")
bool signal = bool(close)
if signal and (high > low)
    signal := not signal
plot(close)''');
    expect(valid.hasSyntaxErrors, isFalse,
        reason: valid.diagnosticMessage);
    expect(valid.diagnostics.any((d) =>
        d.code == 'type_mismatch' || d.code == 'unknown_function'), isFalse,
        reason: valid.diagnosticMessage);
    expect(valid.canExecute, isFalse,
        reason: 'Control-flow AST must not execute in Stage 2');
  });

  test('direct na comparisons are semantically rejected in v6', () {
    final bad = PineFrontend.analyze(
      'indicator("na comparison")\nflag = close == na\nplot(close)');
    expect(bad.diagnostics.any((d) =>
        d.code == 'na_comparison' && d.line == 2), isTrue,
        reason: bad.diagnosticMessage);
    final good = PineFrontend.analyze(
      'indicator("na function")\nflag = na(close)\nplot(close)');
    expect(good.diagnostics.any((d) =>
        d.code == 'na_comparison' || d.code == 'unknown_function'), isFalse);
  });

  test('EMA and RSI length require simple int or weaker qualifier', () {
    final rejected = PineFrontend.analyze('''indicator("qualifier")
dynamic = ta.ema(close, bar_index)
again = ta.rsi(close, length=bar_index)
plot(dynamic)''');
    final errors = rejected.diagnostics.where((d) =>
        d.code == 'argument_qualifier').toList();
    expect(errors, hasLength(2), reason: rejected.diagnosticMessage);
    final allowed = PineFrontend.analyze('''indicator("qualified")
length = input.int(5, "Length")
moving = ta.ema(close, length)
plot(moving)''');
    expect(allowed.diagnostics, isEmpty,
        reason: allowed.diagnosticMessage);
    expect(allowed.canExecute, isTrue,
        reason: 'Supported numeric input source must remain executable');
  });


  test('differential route preserves all supported numeric-subset outputs',
      () {
    final candles = <TradeCandle>[
      for (var i = 0; i < 40; i++)
        TradeCandle(10.0 + i, 12.0 + i, 8.0 + i, 10.0 + i),
    ];
    final programs = <String>[
      'indicator("SMA")\nplot(ta.sma(close, 5))',
      'indicator("Math", overlay=false)\n'
          'a = close[1]\nplot(nz(a, -1))\nplot(math.abs(a - close))',
      'indicator("EMA", overlay=true)\n'
          'n = input.int(3, "Length")\n'
          'e = ta.ema(close, n)\nplot(e, color=color.orange)',
      'indicator("TA")\n'
          'x = ta.rsi(close, 3)\n'
          'plot(x)\nplot(ta.roc(close, 4))\n'
          'plot(ta.highest(high, 4)-ta.lowest(low,4))',
      'indicator("Arithmetic", overlay=false)\n'
          'left = (high + low) / 2\n'
          'plot(left)\nplot((left - close) / close)',
    ];
    for (final source in programs) {
      final original = PineSubsetProgram.compile(source);
      final result = PineFrontend.analyze(source);
      expect(result.diagnostics, isEmpty, reason: source);
      expect(result.canExecute, isTrue, reason: source);
      final oldValues = original.evaluate(candles);
      final newValues = result.executable!.evaluate(candles);
      expect(newValues.length, oldValues.length);
      for (var i = 0; i < oldValues.length; i++) {
        expect(newValues[i].values, oldValues[i].values, reason: source);
      }
    }
  });
}
