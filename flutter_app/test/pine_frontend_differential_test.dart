import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_indicator_library.dart';
import 'package:tradelab_flutter/chart/pine_frontend.dart' as old;
import 'package:tradelab_flutter/chart/pine_v6_frontend.dart' as canonical;
import 'package:tradelab_flutter/chart/pine_subset_program.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  test('both frontends and legacy executor preserve seven numeric fixtures', () {
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
      'indicator("Math families", overlay=false)\n'
          'base = input.float(1.25, "Base")\n'
          'plot(math.max(open, close) + base, color=color.purple)\n'
          'plot(math.min(open, low), title="Minimum")',
      'indicator("Change and styles", overlay=true)\n'
          'delta = ta.change(close, 2)\n'
          'plot(delta, style=plot.style_histogram, color=color.green)\n'
          'plot(ta.sma(close, 3), linewidth=4, title="Trend")',
    ];
    for (final source in programs) {
      final legacy = PineSubsetProgram.compile(source);
      final previous = old.PineFrontend.analyze(source);
      final current = const canonical.PineV6Frontend().prepare(source);
      expect(previous.canExecute, isTrue, reason: previous.diagnosticMessage);
      expect(current.canExecute, isTrue, reason: current.message);
      expect(previous.executable!.overlay, legacy.overlay, reason: source);
      expect(current.legacyProgram!.overlay, legacy.overlay, reason: source);
      final baseline = legacy.evaluate(candles);
      final previousPlots = previous.executable!.evaluate(candles);
      final currentPlots = current.evaluateSupported(candles);
      for (final result in [previousPlots, currentPlots]) {
        expect(result.length, baseline.length, reason: source);
        for (var i = 0; i < baseline.length; i++) {
          expect(result[i].values, baseline[i].values, reason: source);
          expect(result[i].title, baseline[i].title, reason: source);
          expect(result[i].width, baseline[i].width, reason: source);
          expect(result[i].argbColor, baseline[i].argbColor, reason: source);
          expect(result[i].histogram, baseline[i].histogram, reason: source);
        }
      }
    }
  });

  test('canonical frontend preserves old immutable parameter rule', () {
    const source = '''//@version=6
indicator("Immutable parameter")
f(float x) =>
    x := x + 1
    x
plot(f(close))''';
    final previous = old.PineFrontend.analyze(source);
    final current = const canonical.PineV6Frontend().prepare(source);
    expect(previous.diagnostics.any((d) => d.code == 'immutable_parameter'),
        isTrue, reason: previous.diagnosticMessage);
    expect(current.diagnostics.any((d) =>
        d.code == 'immutable_parameter' && d.line == 4), isTrue,
        reason: current.message);
    expect(current.hasErrors, isTrue);
    const saved = ChartSavedIndicatorScript(
        id: 'script-immutable', name: 'Immutable', source: source);
    expect(saved.supportedIndicator(), isNull);
  });

  test('canonical frontend rejects negative history before evaluating bars', () {
    const source = '''//@version=6
indicator("Future read")
plot(close[-1])''';
    final current = const canonical.PineV6Frontend().prepare(source);
    expect(current.diagnostics.any((d) =>
        d.code == 'history_index' && d.line == 3), isTrue,
        reason: current.message);
    expect(current.hasErrors, isTrue);
    const saved = ChartSavedIndicatorScript(
        id: 'script-future', name: 'Future', source: source);
    expect(saved.supportedIndicator(), isNull);
  });
}
