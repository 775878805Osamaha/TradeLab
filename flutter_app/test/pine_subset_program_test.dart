import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/candle_prefix.dart';
import 'package:tradelab_flutter/chart/chart_indicator_engine.dart';
import 'package:tradelab_flutter/chart/chart_indicator_library.dart';
import 'package:tradelab_flutter/chart/pine_subset_program.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

class _ReadGuard extends ListBase<TradeCandle> {
  _ReadGuard(this.bars);
  final List<TradeCandle> bars;
  final List<int> reads = [];
  @override
  int get length => bars.length;
  @override
  set length(int value) => throw UnsupportedError('immutable');
  @override
  TradeCandle operator [](int index) {
    reads.add(index);
    return bars[index];
  }
  @override
  void operator []=(int index, TradeCandle value) =>
      throw UnsupportedError('immutable');
}

void main() {
  List<TradeCandle> bars(List<double> closes) =>
      closes.map((v) => TradeCandle(v, v + 1, v - 1, v))
          .toList(growable: false);

  test('multiplot compiler handles inputs, named series, TA and styles', () {
    const source = '''//@version=6
indicator("Two moving averages", overlay=true)
period = input.int(3, "Fast period")
fast = ta.sma(close, period)
slow = ta.ema(close, 4)
difference = fast - slow
plot(fast, "Fast", color=color.orange, linewidth=3)
plot(difference, title="Gap", style=plot.style_histogram, color=color.teal)''';
    final program = PineSubsetProgram.compile(source);
    expect(program.overlay, isTrue);
    expect(program.title, 'Two moving averages');
    final plots = program.evaluate(bars([10, 20, 30, 40, 50]));
    expect(plots, hasLength(2));
    expect(plots[0].title, 'Fast');
    expect(plots[0].values, [null, null, 20, 30, 40]);
    expect(plots[0].argbColor, 0xFFFF9800);
    expect(plots[0].width, 3);
    expect(plots[1].title, 'Gap');
    expect(plots[1].histogram, isTrue);
    expect(plots[1].values.take(2), [null, null]);
    expect(plots[1].values[2], closeTo(20 - 20.4, 1e-9));
    expect(plots[1].values[4], closeTo(40 - 36.944, 1e-9));
  });

  test('history references align to source index without future lookahead', () {
    const source = '''
indicator("References", overlay=true)
prior = close[1]
basis = (high + low + close) / 3
plot(prior)
plot(basis - prior)
''';
    final program = PineSubsetProgram.compile(source);
    final result = program.evaluate(bars([10, 20, 30, 40]));
    expect(result[0].values, [null, 10, 20, 30]);
    expect(result[1].values, [null, 10, 10, 10]);
    final actual = _ReadGuard(bars([10, 20, 30, 999999]));
    final prefix = CandlePrefix(actual, 3);
    actual.reads.clear();
    final replay = program.evaluate(prefix);
    expect(replay[0].values, [null, 10, 20]);
    expect(actual.reads.every((i) => i < 3), isTrue);
  });

  test('Pine expressions support source arithmetic, math and valid na', () {
    const source = '''
indicator("Math", overlay=false)
old = close[2]
raw = (close - old) / old * 100
plot(nz(raw, -1))
plot(math.abs(raw))
plot(math.max(open, close), "Max")
plot(ta.roc(close,2), "ROC")
''';
    final program = PineSubsetProgram.compile(source);
    expect(program.overlay, isFalse);
    final result = program.evaluate(bars([10, 20, 30, 50]));
    expect(result[0].values, [-1, -1, 200, 150]);
    expect(result[1].values, [null, null, 200, 150]);
    expect(result[2].values, [10, 20, 30, 50]);
    expect(result[3].values, [null, null, 200, 150]);
  });

  test('Pine compile executes EMA/RSI/highest/lowest/change formula', () {
    const source = '''
indicator("Momentum", overlay=false)
n = input.int(2, "Period")
a = ta.highest(high,n)
b = ta.lowest(low,n)
r = ta.rsi(close,n)
plot(a-b, "Range")
plot(r, "RSI")
plot(ta.change(close,n))
''';
    final output = PineSubsetProgram.compile(source)
        .evaluate(bars([10, 11, 12, 13, 14]));
    expect(output, hasLength(3));
    expect(output[0].values, [null, 3, 3, 3, 3]);
    expect(output[1].values.take(2), [null, null]);
    expect(output[1].values.skip(2), [100, 100, 100]);
    expect(output[2].values, [null, null, 2, 2, 2]);
  });

  test('Pine source compiles and renders through active indicator cache', () {
    const source = '''//@version=6
indicator("Bands", overlay=true)
a = ta.sma(close, 2)
plot(a, "Middle")
plot(a + 2, "Upper", color=color.green)
plot(a - 2, "Lower", color=color.red)''';
    const script = ChartSavedIndicatorScript(
      id: 'script-bands', name: 'Three plots', source: source);
    final supported = script.supportedIndicator();
    expect(supported, isNotNull);
    expect(supported!.kind, ChartIndicatorKind.pine);
    expect(supported.separatePane, isFalse);
    final registered = const ChartIndicatorLibraryState()
        .saveScript(script).toggleActive('script-bands');
    expect(registered.active.single.id, 'script-bands');
    final cache = ChartIndicatorSeriesCache();
    final values = cache.get(bars([10, 20, 30, 40]), supported);
    expect(values.plots, hasLength(3));
    expect(values.plots[0].values, [null, 15, 25, 35]);
    expect(values.plots[1].values, [null, 17, 27, 37]);
    expect(values.plots[2].values, [null, 13, 23, 33]);
    final restored = ChartIndicatorLibraryState.decode(registered.encode());
    expect(restored.active.single.kind, ChartIndicatorKind.pine);
  });

  test('multi-plot non-overlay Pine receives independent study pane', () {
    const source = '''indicator("Two lines", overlay=false)
momentum = ta.roc(close, 2)
plot(momentum, "ROC")
plot(ta.sma(momentum, 2), "Signal")''';
    const script = ChartSavedIndicatorScript(
        id: 'script-osc', name: 'Momentum', source: source);
    final ind = script.supportedIndicator();
    expect(ind, isNotNull);
    expect(ind!.kind, ChartIndicatorKind.pine);
    expect(ind.separatePane, isTrue);
    final actual = ChartIndicatorEngine.compute(
        bars([10, 11, 12, 13, 14]), ind);
    expect(actual.plots, hasLength(2));
    expect(actual.plots[0].values.take(2), [null, null]);
    expect(actual.plots[1].values.take(3), [null, null, null]);
    expect(actual.plots[0].values[2], closeTo(20, 1e-10));
    expect(actual.plots[1].values[3],
        closeTo((20 + 100 * 2 / 11) / 2, 1e-10));
  });

  test('unsupported syntax returns explicit rejection rather than fake plot', () {
    final bad = <String>[
      'strategy("not supported")\nplot(close)',
      'indicator("A", overlay=true)\nif close > open\n    plot(close)',
      'indicator("A", overlay=true)\nplotshape(close)',
      'indicator("A", overlay=true)\nrequest.security("X","D",close)\nplot(close)',
      'indicator("A", overlay=true)\nx := close\nplot(x)',
      'indicator("A", overlay=true)\nplot(close[5001])',
      'indicator("A", overlay=true)\nplot(ta.ema(close, 0))',
      'indicator("A", overlay=true)\nplot(ta.ema(close, 501))',
      'indicator("A", overlay=true)\nplot(close, offset=1)',
      'indicator("A", overlay=true)\nplot(close, color=color.unknown)',
      'indicator("A", overlay=true)\nplot(close + unknown)',
      'indicator("A", overlay=true)\na = b\nb = 2\nplot(a)',
      'indicator("A", overlay=true)\nplot(close / (open - open))\nalert("X")',
      'indicator("A", overlay=true)\nplot(close); plot(high)',
      'indicator("A", overlay=true)\nplot(close, linewidth=9)',
    ];
    for (final source in bad) {
      expect(PineSubsetProgram.tryCompile(source), isNull,
          reason: 'Must reject unsupported syntax: ' + source);
      try {
        PineSubsetProgram.compile(source);
        fail('Unsupported program compiled: ' + source);
      } on PineSubsetException catch (error) {
        expect(error.message, isNotEmpty);
        expect(error.line, greaterThanOrEqualTo(0));
      }
    }
  });

  test('arithmetic division by zero is na and cannot manufacture values', () {
    final plot = PineSubsetProgram.compile(
        'indicator("Zero", overlay=false)\nplot(close / (open-open))');
    final output = plot.evaluate(bars([10, 20, 30]));
    expect(output.single.values, [null, null, null]);
  });

  test('strict parser resource limits reject overlong and excessive plots', () {
    final many = 'indicator("Many", overlay=true)\n' +
        List<String>.filled(9, 'plot(close)').join('\n');
    expect(PineSubsetProgram.tryCompile(many), isNull);
    final nesting = '('.padRight(25, '(') + 'close' + ')'.padRight(25, ')');
    expect(PineSubsetProgram.tryCompile(
        'indicator("Depth", overlay=true)\nplot(' + nesting + ')'), isNull);
    expect(PineSubsetProgram.tryCompile(List<String>.filled(15001, 'a').join()), isNull);
  });

  test('120k source cache computes multi-plot once per revealed snapshot', () {
    const source = '''indicator("Large", overlay=true)
a = ta.ema(close, 20)
b = ta.sma(close, 50)
plot(a)
plot(b)
plot(a-b)''';
    const script = ChartSavedIndicatorScript(
        id: 'script-large', name: 'Large indicator', source: source);
    final indicator = script.supportedIndicator()!;
    final actual = _ReadGuard(List<TradeCandle>.generate(120000, (i) {
      final v = 100.0 + math.sin(i / 30);
      return TradeCandle(v, v + 1, v - 1, v);
    }));
    final cache = ChartIndicatorSeriesCache();
    final first = cache.get(actual, indicator);
    expect(first.plots, hasLength(3));
    expect(first.plots.last.values.length, 120000);
    actual.reads.clear();
    for (var n = 0; n < 50; n++) {
      expect(cache.get(actual, indicator), same(first));
    }
    expect(actual.reads, isEmpty);
    final prefix = CandlePrefix(actual, 119999);
    actual.reads.clear();
    expect(cache.get(prefix, indicator).plots.first.values.length, 119999);
    expect(actual.reads.every((i) => i < 119999), isTrue);
  });
}
