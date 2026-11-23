import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/pine_subset_program.dart';
import 'package:tradelab_flutter/chart/pine_v6_frontend.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

/// Finite generated differential corpus for every currently documented
/// numeric builtin family, source form, and output style. This is NOT a
/// mathematical proof for all possible Pine programs. No V10 or user strategy.
void main() {
  final prices = List<TradeCandle>.unmodifiable([
    for (var i = 0; i < 96; i++)
      TradeCandle(
        40.0 + ((i * 17) % 31) - 1.0,
        40.0 + ((i * 17) % 31) + 3.0,
        40.0 + ((i * 17) % 31) - 4.0,
        40.0 + ((i * 17) % 31),
      ),
  ]);

  void check(String source) {
    final baseline = PineSubsetProgram.compile(source);
    final routed = const PineV6Frontend().prepare(source);
    expect(routed.diagnostics.where((d) =>
        d.severity == PineDiagnosticSeverity.error), isEmpty,
        reason: 'v6 frontend rejected valid subset:\n' + source + '\n' +
            (routed.message ?? ''));
    expect(routed.canExecute, isTrue,
        reason: 'New gate lost support for old compiler:\n' + source + '\n' +
            (routed.message ?? ''));
    final expected = baseline.evaluate(prices);
    final actual = routed.evaluateSupported(prices);
    expect(actual.length, expected.length, reason: source);
    for (var i = 0; i < expected.length; i++) {
      expect(actual[i].values, expected[i].values,
          reason: 'Mismatch in plot ' + i.toString() + ':\n' + source);
      expect(actual[i].title, expected[i].title, reason: source);
      expect(actual[i].argbColor, expected[i].argbColor, reason: source);
      expect(actual[i].histogram, expected[i].histogram, reason: source);
      expect(actual[i].width, expected[i].width, reason: source);
    }
  }

  test('seven ta families x seven sources x three lengths '
      'exactly match the old evaluator', () {
    const functions = [
      'ta.sma', 'ta.ema', 'ta.rsi', 'ta.roc',
      'ta.highest', 'ta.lowest', 'ta.change',
    ];
    const sources = [
      'open', 'high', 'low', 'close', 'hl2', 'hlc3', 'ohlc4',
    ];
    const lengths = [2, 3, 5];
    var samples = 0;
    for (final fn in functions) {
      for (final source in sources) {
        for (final length in lengths) {
          check('''//@version=6
indicator("Generated TA matrix", overlay=false)
out = $fn($source, $length)
plot(out, title="Value", color=color.red, linewidth=2)''');
          samples++;
        }
      }
    }
    expect(samples, 147);
  });

  test('math, nz, history, and input families keep exact output', () {
    const sources = ['open', 'high', 'low', 'close', 'hl2', 'hlc3', 'ohlc4'];
    const expressions = [
      'math.abs(close - open)',
      'math.min(high, low)',
      'math.max(open, close)',
      'nz(close[1], 0)',
      'nz(hl2[2], -1)',
      '(close - open) / 2',
      '(high + low + close) / 3',
      'close[1] * 2 + open',
      '(hlc3 - ohlc4) / close',
    ];
    var samples = 0;
    for (final expr in expressions) {
      check('''indicator("Arithmetic", overlay=true)
out = $expr
plot(out, title="Value")''');
      samples++;
    }
    for (final source in sources) {
      check('''indicator("Number", overlay=false)
a = input.float(1.25, "Offset")
n = input.int(3, "Length")
value = ta.sma($source, n)
plot(value + a, title="Weighted", color=color.orange)
plot(math.min($source, close), title="Low", color=color.green)''');
      samples++;
    }
    expect(samples, 16);
  });

  test('output styles and plot metadata exactly match', () {
    const formats = [
      'plot(close)',
      'plot(close, title="Close", color=color.blue)',
      'plot(ta.ema(close,3), linewidth=4, title="EMA")',
      'plot(close, style=plot.style_histogram, color=color.purple)',
      'plot(high, style=plot.style_columns, color=color.red)',
      'plot(close, title="One")\nplot(open, title="Two")',
    ];
    for (final format in formats) {
      check('indicator("Style matrix", overlay=false)\n$format');
    }
    expect(formats.length, 6);
  });
}
