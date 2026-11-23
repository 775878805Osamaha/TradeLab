import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/pine_indicator_instance.dart';
import 'package:tradelab_flutter/chart/pine_runtime_core.dart';
import 'package:tradelab_flutter/chart/pine_subset_program.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

class _ObservedBars extends ListBase<TradeCandle> {
  _ObservedBars(this._source);
  final List<TradeCandle> _source;
  final List<int> reads = [];

  @override
  int get length => _source.length;
  @override
  set length(int value) => throw UnsupportedError('immutable fixture');
  @override
  TradeCandle operator [](int index) {
    reads.add(index);
    return _source[index];
  }
  @override
  void operator []=(int index, TradeCandle value) =>
      throw UnsupportedError('immutable fixture');
}

List<TradeCandle> _bars(List<double> closes) =>
    closes.map((close) =>
        TradeCandle(close, close + 2, close - 2, close))
        .toList(growable: false);

void main() {
  const priceSource = '''//@version=6
indicator("Instance EMA", overlay=true)
n = input.int(2, "Length")
smooth = ta.ema(close, n)
plot(smooth, title="EMA")
plot(close[1], title="Prior")''';

  test('two active copies use the same saved source with independent inputs '
       'and independent persistent state', () {
    final manager = PineIndicatorInstances();
    manager.saveDefinition(PineIndicatorDefinition.compile(
        'saved-ema', priceSource));
    final fast = manager.add(instanceId: 'fast',
        definitionId: 'saved-ema', inputs: const {'n': 2});
    final slow = manager.add(instanceId: 'slow',
        definitionId: 'saved-ema', inputs: const {'n': 4});
    fast.persistentState['counter'] = PineValue.numeric(4);
    expect(slow.persistentState, isEmpty);
    final source = _bars([10, 20, 30, 40, 50, 60]);
    for (final bar in source) {
      fast.advance(bar);
      slow.advance(bar);
    }
    expect(fast.completedBars, 6);
    expect(slow.completedBars, 6);
    expect(fast.outputs[0].values.last, isNot(slow.outputs[0].values.last));
    expect(fast.outputs[0].values.last, closeTo(50.8230452675, 1e-6));
    manager.remove('fast');
    expect(manager.instance('fast'), isNull);
    expect(manager.instance('slow'), same(slow));
    expect(manager.definition('saved-ema'), isNotNull,
        reason: 'Removing the view must never delete saved Pine source');
    slow.advance(TradeCandle(70, 72, 68, 70));
    expect(slow.completedBars, 7);
    manager.closeAll();
    expect(manager.definition('saved-ema'), isNotNull);
  });

  test('explicit numeric na propagates but comparison to na is false in v6', () {
    const na = PineValue.na;
    final eight = PineValue.numeric(8);
    expect(PineValue.arithmetic('+', na, eight).isNa, isTrue);
    expect(PineValue.arithmetic('*', eight, na).isNa, isTrue);
    expect(PineValue.arithmetic('/', eight, PineValue.numeric(0)).isNa, isTrue);
    for (final op in ['==', '!=', '<', '<=', '>', '>=']) {
      final value = PineValue.compare(op, na, eight);
      expect(value.type, PineValueType.boolean);
      expect(value.boolean, isFalse, reason: op);
    }
    expect(PineValue.compare('>=', eight, PineValue.numeric(7)).boolean,
        isTrue);
  });

  test('numeric history uses na, v6 boolean history uses false, and '
       'ring storage is bounded', () {
    final numeric = PineSeries(historyLimit: 2);
    final flags = PineSeries(
        historyLimit: 2, type: PineValueType.boolean);
    expect(numeric.history(1).isNa, isTrue);
    expect(flags.history(1).boolean, isFalse);
    numeric.append(PineValue.numeric(3));
    numeric.append(PineValue.na);
    flags.append(PineValue.trueValue);
    flags.append(PineValue.falseValue);
    expect(numeric.history(0).isNa, isTrue);
    expect(numeric.history(1).number, 3);
    expect(numeric.history(2).isNa, isTrue);
    expect(flags.history(0).boolean, isFalse);
    expect(flags.history(1).boolean, isTrue);
    expect(flags.history(2).boolean, isFalse);
    numeric.append(PineValue.numeric(5));
    expect(numeric.history(2).isNa, isTrue);
    expect(numeric.history(1).isNa, isTrue);
    expect(numeric.history(0).number, 5);
    numeric.reset();
    expect(numeric.length, 0);
    expect(numeric.history(0).isNa, isTrue);
  });

  test('numeric source history and math na agree with legacy subset engine', () {
    const source = '''indicator("History", overlay=false)
prior = close[2]
ratio = (close - prior) / prior * 100
plot(prior)
plot(ratio)
plot(nz(ratio, -1))''';
    final program = PineSubsetProgram.compile(source);
    final candles = _bars([10, 20, 40, 80, 160]);
    final legacy = program.evaluate(candles);
    final streamed = program.evaluateIncrementally(candles);
    for (var i = 0; i < legacy.length; i++) {
      expect(streamed[i].values, legacy[i].values);
    }
    expect(streamed[0].values.take(2), [null, null]);
    expect(streamed[2].values.take(2), [-1.0, -1.0]);
  });

  test('every supported TA function produces same deterministic series '
       'in legacy and streaming evaluation', () {
    const source = '''indicator("TA matrix", overlay=false)
a = ta.sma(close, 3)
b = ta.ema(close, 4)
c = ta.rsi(close, 3)
d = ta.highest(high, 4)
e = ta.lowest(low, 4)
f = ta.change(close, 2)
g = ta.roc(close, 2)
plot(a)
plot(b)
plot(c)
plot(d)
plot(e)
plot(f)
plot(g)''';
    final prices = _bars([
      10, 11, 13, 12, 15, 17, 15, 18, 16, 18, 19, 20, 18, 17,
    ]);
    final program = PineSubsetProgram.compile(source);
    final legacy = program.evaluate(prices);
    final run1 = program.evaluateIncrementally(prices);
    final run2 = program.evaluateIncrementally(prices);
    for (var i = 0; i < legacy.length; i++) {
      for (var bar = 0; bar < prices.length; bar++) {
        final expected = legacy[i].values[bar];
        final actual = run1[i].values[bar];
        if (expected == null) {
          expect(actual, isNull, reason: 'plot $i / bar $bar');
        } else {
          expect(actual, closeTo(expected, 1e-9),
              reason: 'plot $i / bar $bar');
        }
      }
      expect(run2[i].values, run1[i].values);
    }
  });

  test('steps, retained memory and deadline fail closed with explicit codes',
      () {
    final definition = PineIndicatorDefinition.compile(
        'budgeted', priceSource);
    final limitedSteps = PineIndicatorInstance(
      instanceId: 'steps', definition: definition,
      limits: const PineRuntimeLimits(
        maxSteps: 90, maxHistory: 8, maxStoredValues: 300),
    );
    PineRuntimeException? error;
    try {
      for (final candle in _bars(List<double>.generate(200, (i) => i + 1.0))) {
        limitedSteps.advance(candle);
      }
    } on PineRuntimeException catch (e) {
      error = e;
    }
    expect(error?.code, 'step_limit');
    expect(() => limitedSteps.advance(
        TradeCandle(1, 2, 0, 1)),
        throwsA(isA<PineRuntimeException>()));

    expect(() => PineIndicatorInstance(
      instanceId: 'memory', definition: definition,
      limits: const PineRuntimeLimits(
        maxHistory: 8, maxStoredValues: 5)),
      throwsA(isA<PineRuntimeException>().having(
        (e) => e.code, 'code', 'memory_limit')));

    expect(() => PineIndicatorInstance(
      instanceId: 'deadline', definition: definition,
      limits: const PineRuntimeLimits(
        maxHistory: 8, maxStoredValues: 300,
        timeout: Duration.zero)),
      throwsA(isA<PineRuntimeException>().having(
        (e) => e.code, 'code', 'timeout')));
  });

  test('Replay reveal, advance and rewind rebuild from correct prefix '
       'without inspecting future candles or retaining prior values', () {
    final manager = PineIndicatorInstances();
    manager.saveDefinition(PineIndicatorDefinition.compile(
        'replay-study', priceSource));
    final instance = manager.add(instanceId: 'r',
        definitionId: 'replay-study', inputs: const {'n': 2});
    final actual = _ObservedBars(_bars([
      10, 20, 30, 40, 50, 99999, 99999, 99999,
    ]));
    instance.rebuild(actual, 3);
    expect(actual.reads, everyElement(lessThan(3)));
    final atThree = instance.outputs.map((p) => p.values.toList()).toList();
    actual.reads.clear();
    instance.rebuild(actual, 5);
    expect(actual.reads, everyElement(lessThan(5)));
    expect(instance.outputs[0].values.length, 5);
    actual.reads.clear();
    instance.persistentState['old-run'] = PineValue.numeric(999);
    instance.rebuild(actual, 3);
    expect(actual.reads, everyElement(lessThan(3)));
    expect(instance.persistentState, isEmpty);
    expect(instance.outputs.map((p) => p.values).toList(), atThree);

    final fresh = manager.add(instanceId: 'fresh',
        definitionId: 'replay-study', inputs: const {'n': 2});
    fresh.rebuild(actual, 3);
    expect(fresh.outputs.map((p) => p.values).toList(), atThree);
    expect(instance.outputs[1].values, [null, 10, 20]);
  });

  test('invalid Replay cutoff and unsupported source fail cleanly', () {
    final definition = PineIndicatorDefinition.compile(
        'safe', priceSource);
    final instance = PineIndicatorInstance(
        instanceId: 'live', definition: definition);
    expect(() => instance.rebuild(_bars([1, 2]), 3),
        throwsA(isA<PineRuntimeException>().having(
            (e) => e.code, 'code', 'invalid_cutoff')));
    expect(() => PineIndicatorDefinition.compile(
      'invalid', 'indicator("X")\nplotshape(close)'),
        throwsA(isA<PineSubsetException>()));
  });
}
