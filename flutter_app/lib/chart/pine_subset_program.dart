import 'dart:math' as math;
import 'dart:collection';

import '../data/tradelab_data.dart';

/// A deliberately bounded Pine v5/v6 *indicator-series* interpreter.
/// This does not claim to implement the entire Pine language.
///
/// Supported:
/// - indicator("title", overlay=true|false)
/// - prior single-assignment numeric variables, input.int/float defaults
/// - open/high/low/close/hl2/hlc3/ohlc4 and history [0..5000]
/// - + - * /, parentheses and numeric constants
/// - ta.sma/ema/rsi(source, simpleLength), ta.roc(source, simpleLength),
///   ta.highest/lowest(source, simpleLength), ta.change(source, simpleLength)
/// - math.abs(x), math.min/max(x,y), nz(x[,fallback])
/// - up to 8 named plot(expr), optional color/linewidth/histogram style
///
/// No loops, if/else, variables reassigned with :=, request.security,
/// strategies, drawings, alerts, user functions or dynamic series periods.
/// Anything outside the grammar is rejected with a concrete line number
/// BEFORE evaluating source bars. No eval, reflection or network access.
class PineSubsetException implements Exception {
  const PineSubsetException(this.line, this.message);
  final int line;
  final String message;
  @override
  String toString() => 'السطر ' + line.toString() + ': ' + message;
}

class PineSubsetPlot {
  const PineSubsetPlot(this.title, this.values,
      {this.histogram = false, this.argbColor, this.width = 2});
  final String title;
  final List<double?> values;
  final bool histogram;
  final int? argbColor;
  final int width;
}

class _PineStatement {
  const _PineStatement(this.name, this.expression, this.line);
  final String name;
  final _PineExpr expression;
  final int line;
}

class _PinePlotStatement {
  const _PinePlotStatement(this.expr, this.title, this.line,
      {this.histogram = false, this.color, this.width = 2});
  final _PineExpr expr;
  final String title;
  final int line;
  final bool histogram;
  final int? color;
  final int width;
}

abstract class _PineExpr {
  const _PineExpr();
}

class _PineValue extends _PineExpr {
  const _PineValue(this.value);
  final double value;
}

class _PineName extends _PineExpr {
  const _PineName(this.name);
  final String name;
}

class _PineHistory extends _PineExpr {
  const _PineHistory(this.name, this.offset);
  final String name;
  final int offset;
}

class _PineUnary extends _PineExpr {
  const _PineUnary(this.operator, this.value);
  final String operator;
  final _PineExpr value;
}

class _PineBinary extends _PineExpr {
  const _PineBinary(this.operator, this.left, this.right);
  final String operator;
  final _PineExpr left;
  final _PineExpr right;
}

class _PineCall extends _PineExpr {
  const _PineCall(this.name, this.args);
  final String name;
  final List<_PineExpr> args;
}

class _PineExpressionParser {
  _PineExpressionParser(String source, this.line) {
    var index = 0;
    final name = RegExp(r'[A-Za-z_][A-Za-z_0-9.]*');
    final number = RegExp(r'(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)');
    while (index < source.length) {
      final c = source[index];
      if (c.trim().isEmpty) {
        index++;
        continue;
      }
      final match = name.matchAsPrefix(source, index) ??
          number.matchAsPrefix(source, index);
      if (match != null) {
        tokens.add(match.group(0)!);
        index = match.end;
      } else if ('+-*/(),[]'.contains(c)) {
        tokens.add(c);
        index++;
      } else {
        throw PineSubsetException(line,
            'رمز غير مدعوم في التعبير: ' + c);
      }
      if (tokens.length > 180) {
        throw PineSubsetException(line, 'التعبير أطول من الحد الآمن');
      }
    }
  }

  final int line;
  final List<String> tokens = [];
  int index = 0;
  int nesting = 0;

  String? get current => index < tokens.length ? tokens[index] : null;
  bool accept(String token) {
    if (current != token) return false;
    index++;
    return true;
  }

  void expect(String token) {
    if (!accept(token)) {
      throw PineSubsetException(line, 'متوقع ' + token);
    }
  }

  _PineExpr parse() {
    if (tokens.isEmpty) {
      throw PineSubsetException(line, 'تعبير فارغ');
    }
    final result = _addition();
    if (current != null) {
      throw PineSubsetException(line, 'صيغة غير مكتملة عند ' + current!);
    }
    return result;
  }

  _PineExpr _addition() {
    var expr = _multiplication();
    while (current == '+' || current == '-') {
      final op = tokens[index++];
      expr = _PineBinary(op, expr, _multiplication());
    }
    return expr;
  }

  _PineExpr _multiplication() {
    var expr = _unary();
    while (current == '*' || current == '/') {
      final op = tokens[index++];
      expr = _PineBinary(op, expr, _unary());
    }
    return expr;
  }

  _PineExpr _unary() {
    if (accept('-')) return _PineUnary('-', _unary());
    if (accept('+')) return _unary();
    return _primary();
  }

  _PineExpr _primary() {
    if (++nesting > 20) {
      throw PineSubsetException(line, 'تداخل تعبيرات أكبر من الحد الآمن');
    }
    try {
      if (accept('(')) {
        final expr = _addition();
        expect(')');
        return expr;
      }
      final token = current;
      if (token == null) {
        throw PineSubsetException(line, 'تعبير غير مكتمل');
      }
      index++;
      final number = double.tryParse(token);
      if (number != null) {
        if (!number.isFinite) {
          throw PineSubsetException(line, 'عدد غير منتهٍ');
        }
        return _PineValue(number);
      }
      if (!RegExp(r'^[A-Za-z_][A-Za-z_0-9.]*$').hasMatch(token)) {
        throw PineSubsetException(line, 'اسم غير صالح: ' + token);
      }
      if (accept('(')) {
        final args = <_PineExpr>[];
        if (!accept(')')) {
          do {
            args.add(_addition());
            if (args.length > 3) {
              throw PineSubsetException(line, 'عدد وسائط أكبر من المدعوم');
            }
          } while (accept(','));
          expect(')');
        }
        return _PineCall(token, args);
      }
      if (accept('[')) {
        final raw = current;
        final offset = raw == null ? null : int.tryParse(raw);
        if (offset == null || offset < 0 || offset > 5000) {
          throw PineSubsetException(line, 'مرجع الشمعة يجب أن يكون 0..5000');
        }
        index++;
        expect(']');
        return _PineHistory(token, offset);
      }
      return _PineName(token);
    } finally {
      nesting--;
    }
  }
}

class PineSubsetProgram {
  PineSubsetProgram._(
      this.title, this.overlay, this.constants,
      this.statements, this.plots);

  final String title;
  final bool overlay;
  final Map<String, double> constants;
  final List<_PineStatement> statements;
  final List<_PinePlotStatement> plots;

  static const _sourceFields = <String>{
    'open','high','low','close','hl2','hlc3','ohlc4',
  };
  static const _functions = <String, int>{
    'ta.sma':2, 'ta.ema':2, 'ta.rsi':2, 'ta.roc':2,
    'ta.highest':2, 'ta.lowest':2, 'ta.change':2,
    'math.abs':1, 'math.min':2, 'math.max':2,
    'nz':-1,
  };
  static const _colors = <String, int>{
    'color.blue': 0xFF2962FF,
    'color.red': 0xFFF44336,
    'color.green': 0xFF4CAF50,
    'color.orange': 0xFFFF9800,
    'color.purple': 0xFF9C27B0,
    'color.teal': 0xFF009688,
    'color.yellow': 0xFFFFEB3B,
    'color.white': 0xFFFFFFFF,
    'color.black': 0xFF000000,
    'color.gray': 0xFF9E9E9E,
    'color.aqua': 0xFF00BCD4,
    'color.fuchsia': 0xFFFF00FF,
  };

  static PineSubsetProgram? tryCompile(String source) {
    try {
      return compile(source);
    } on PineSubsetException {
      return null;
    }
  }

  static PineSubsetProgram compile(String source) {
    if (source.length > 15000) {
      throw const PineSubsetException(0, 'حجم الكود أكبر من الحد المسموح');
    }
    final lines = source.split('\n');
    final effective = <(int, String)>[];
    for (var i = 0; i < lines.length; i++) {
      final text = lines[i].trim();
      if (text.isEmpty || text.startsWith('//')) continue;
      if (lines[i].startsWith(' ') || lines[i].startsWith('\t')) {
        throw PineSubsetException(i + 1,
            'الأوامر الداخلية والكتل غير مدعومة بعد');
      }
      effective.add((i + 1, text));
    }
    if (effective.isEmpty) {
      throw const PineSubsetException(0, 'الكود فارغ');
    }
    final declaration = RegExp(
      r'''^indicator\(\s*["']([^"']{1,80})["']\s*(?:,\s*overlay\s*=\s*(true|false)\s*)?\)$''')
        .firstMatch(effective.first.$2);
    if (declaration == null) {
      throw PineSubsetException(effective.first.$1,
          'يلزم تعريف indicator("...", overlay=true/false)');
    }
    final overlay = declaration.group(2) == 'true';
    final constants = <String, double>{};
    final statements = <_PineStatement>[];
    final plots = <_PinePlotStatement>[];
    final known = <String>{..._sourceFields};
    var drawingStarted = false;
    for (final (line, instruction) in effective.skip(1)) {
      if (instruction.startsWith('plot(') && instruction.endsWith(')')) {
        drawingStarted = true;
        if (plots.length >= 8) {
          throw PineSubsetException(line, 'الحد الأقصى 8 خطوط للمؤشر');
        }
        final parts = _splitArguments(
            instruction.substring(5, instruction.length - 1), line);
        if (parts.isEmpty || parts.first.isEmpty) {
          throw PineSubsetException(line, 'plot يحتاج قيمة');
        }
        final expr = _PineExpressionParser(parts.first, line).parse();
        _checkExpression(expr, known, constants, line);
        var label = 'Plot ' + (plots.length + 1).toString();
        var histogram = false;
        int? color;
        var width = 2;
        var positionalName = false;
        for (final option in parts.skip(1)) {
          final titleMatch = RegExp(r'''^title\s*=\s*["']([^"']{1,80})["']$''')
              .firstMatch(option);
          final positional = RegExp(r'''^["']([^"']{1,80})["']$''')
              .firstMatch(option);
          if (titleMatch != null || (positional != null && !positionalName)) {
            label = (titleMatch ?? positional)!.group(1)!;
            positionalName = true;
          } else if (option == 'style=plot.style_histogram' ||
              option == 'style = plot.style_histogram' ||
              option == 'style=plot.style_columns') {
            histogram = true;
          } else if (option == 'style=plot.style_line' ||
              option == 'style = plot.style_line') {
            histogram = false;
          } else if (option.startsWith('color=')) {
            color = _colors[option.substring(6).trim()];
            if (color == null) {
              throw PineSubsetException(line,
                  'لون plot غير مدعوم: ' + option);
            }
          } else if (option.startsWith('linewidth=')) {
            final amount = int.tryParse(option.substring(10).trim());
            if (amount == null || amount < 1 || amount > 5) {
              throw PineSubsetException(line, 'linewidth يجب أن يكون 1..5');
            }
            width = amount;
          } else {
            throw PineSubsetException(line,
                'خاصية plot غير مدعومة: ' + option);
          }
        }
        plots.add(_PinePlotStatement(expr, label, line,
            histogram: histogram, color: color, width: width));
        continue;
      }
      if (drawingStarted) {
        throw PineSubsetException(line,
            'التعريفات يجب أن تسبق plot');
      }
      final assignment = RegExp(
        r'^(?:(?:float|int)\s+)?([A-Za-z_][A-Za-z_0-9]*)\s*=\s*(.+)$')
          .firstMatch(instruction);
      if (assignment == null || statements.length + constants.length >= 16) {
        throw PineSubsetException(line,
            'تعريف غير مدعوم أو تم تجاوز 16 متغيرًا');
      }
      final name = assignment.group(1)!;
      if (known.contains(name) || _functions.containsKey(name)) {
        throw PineSubsetException(line, 'اسم متغير مكرر: ' + name);
      }
      final rhs = assignment.group(2)!;
      final input = RegExp(
        r'^input\.(int|float)\(\s*(-?(?:[0-9]+(?:\.[0-9]+)?))\s*(?:,\s*["\x27][^"\x27]{0,80}["\x27])?\s*\)$')
          .firstMatch(rhs);
      if (input != null) {
        final value = double.parse(input.group(2)!);
        if (input.group(1) == 'int' && value != value.roundToDouble()) {
          throw PineSubsetException(line, 'input.int يجب أن يكون عددًا صحيحًا');
        }
        if (!value.isFinite || value.abs() > 1000000) {
          throw PineSubsetException(line, 'قيمة input غير مدعومة');
        }
        constants[name] = value;
      } else {
        final expr = _PineExpressionParser(rhs, line).parse();
        _checkExpression(expr, known, constants, line);
        statements.add(_PineStatement(name, expr, line));
      }
      known.add(name);
    }
    if (plots.isEmpty) {
      throw const PineSubsetException(0, 'يلزم plot واحد على الأقل');
    }
    return PineSubsetProgram._(
        declaration.group(1)!, overlay, constants, statements, plots);
  }

  static List<String> _splitArguments(String input, int line) {
    final parts = <String>[];
    var from = 0;
    var depth = 0;
    String? quote;
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (quote != null) {
        if (c == quote) quote = null;
        continue;
      }
      if (c == '"' || c == "'") {
        quote = c;
      } else if (c == '(' || c == '[') {
        depth++;
      } else if (c == ')' || c == ']') {
        depth--;
        if (depth < 0) {
          throw PineSubsetException(line, 'أقواس غير متوازنة');
        }
      } else if (c == ',' && depth == 0) {
        parts.add(input.substring(from, i).trim());
        from = i + 1;
      }
    }
    if (depth != 0 || quote != null) {
      throw PineSubsetException(line, 'أقواس أو علامات اقتباس غير مكتملة');
    }
    parts.add(input.substring(from).trim());
    return parts;
  }

  static int _length(_PineExpr expr, Map<String,double> constants, int line) {
    final value = switch (expr) {
      _PineValue(:final value) => value,
      _PineName(:final name) => constants[name],
      _PineUnary(operator: '-', value: _PineValue(value: final inner)) =>
        -inner,
      _ => null,
    };
    if (value == null || !value.isFinite ||
        value < 1 || value > 500 || value != value.roundToDouble()) {
      throw PineSubsetException(line,
          'طول ta يجب أن يكون ثابتًا صحيحًا من 1 إلى 500');
    }
    return value.toInt();
  }

  static void _checkExpression(_PineExpr expr, Set<String> known,
      Map<String, double> constants, int line) {
    switch (expr) {
      case _PineValue():
        return;
      case _PineName(:final name):
        if (!known.contains(name)) {
          throw PineSubsetException(line, 'متغير غير معروف: ' + name);
        }
      case _PineHistory(:final name):
        if (!known.contains(name)) {
          throw PineSubsetException(line, 'سلسلة غير معروفة: ' + name);
        }
      case _PineUnary(:final value):
        _checkExpression(value, known, constants, line);
      case _PineBinary(:final left, :final right):
        _checkExpression(left, known, constants, line);
        _checkExpression(right, known, constants, line);
      case _PineCall(:final name, :final args):
        final count = _functions[name];
        if (count == null || (count != -1 && args.length != count) ||
            (count == -1 && !(args.length == 1 || args.length == 2))) {
          throw PineSubsetException(line,
              'دالة غير مدعومة أو وسائط خاطئة: ' + name);
        }
        for (final arg in args) {
          _checkExpression(arg, known, constants, line);
        }
        if (name.startsWith('ta.')) {
          _length(args[1], constants, line);
        }
    }
  }

  /// Evaluates one full verified-source prefix using source-indexed nullable
  /// data. A missing history index is na, never the newest unseen candle.
  List<PineSubsetPlot> evaluate(List<TradeCandle> candles) {
    final size = candles.length;
    final variables = <String, List<double?>>{
      for (final entry in constants.entries)
        entry.key: List<double?>.filled(size, entry.value),
      'open': List<double?>.generate(size, (i) => candles[i].open),
      'high': List<double?>.generate(size, (i) => candles[i].high),
      'low': List<double?>.generate(size, (i) => candles[i].low),
      'close': List<double?>.generate(size, (i) => candles[i].close),
      'hl2': List<double?>.generate(size,
          (i) => (candles[i].high + candles[i].low) / 2),
      'hlc3': List<double?>.generate(size,
          (i) => (candles[i].high + candles[i].low + candles[i].close) / 3),
      'ohlc4': List<double?>.generate(size,
          (i) => (candles[i].open + candles[i].high +
                   candles[i].low + candles[i].close) / 4),
    };
    final memo = <_PineExpr, List<double?>>{};

    List<double?> eval(_PineExpr expr) {
      final cached = memo[expr];
      if (cached != null) return cached;
      late final List<double?> result;
      switch (expr) {
        case _PineValue(:final value):
          result = List<double?>.filled(size, value);
        case _PineName(:final name):
          result = variables[name]!;
        case _PineHistory(:final name, :final offset):
          final source = variables[name]!;
          result = List<double?>.generate(
              size, (i) => i >= offset ? source[i - offset] : null);
        case _PineUnary(:final operator, :final value):
          final source = eval(value);
          result = List<double?>.generate(size, (i) {
            final x = source[i];
            return x == null ? null : (operator == '-' ? -x : x);
          });
        case _PineBinary(:final operator, :final left, :final right):
          final a = eval(left);
          final b = eval(right);
          result = List<double?>.generate(size, (i) {
            final x = a[i];
            final y = b[i];
            if (x == null || y == null || (operator == '/' && y == 0)) {
              return null;
            }
            final answer = switch (operator) {
              '+' => x + y,
              '-' => x - y,
              '*' => x * y,
              _ => x / y,
            };
            return answer.isFinite ? answer : null;
          });
        case _PineCall(:final name, :final args):
          final values = args.map(eval).toList(growable: false);
          if (name == 'math.abs' || name == 'math.max' ||
              name == 'math.min' || name == 'nz') {
            result = List<double?>.generate(size, (i) {
              final x = values.first[i];
              final y = values.length > 1 ? values[1][i] : null;
              if (name == 'nz') return x ?? y ?? 0.0;
              if (x == null || (name != 'math.abs' && y == null)) {
                return null;
              }
              return switch (name) {
                'math.abs' => x.abs(),
                'math.max' => math.max(x, y!),
                _ => math.min(x, y!),
              };
            });
          } else {
            final period = _length(args[1], constants, 0);
            final source = values.first;
            result = switch (name) {
              'ta.sma' => _sma(source, period),
              'ta.ema' => _ema(source, period),
              'ta.rsi' => _rsi(source, period),
              'ta.roc' => _roc(source, period),
              'ta.change' => List<double?>.generate(size, (i) {
                if (i < period) return null;
                final x = source[i];
                final y = source[i - period];
                return x == null || y == null ? null : x - y;
              }),
              'ta.highest' => _extreme(source, period, true),
              _ => _extreme(source, period, false),
            };
          }
      }
      memo[expr] = result;
      return result;
    }

    for (final statement in statements) {
      variables[statement.name] = eval(statement.expression);
    }
    return [
      for (final item in plots)
        PineSubsetPlot(item.title, eval(item.expr),
            histogram: item.histogram,
            argbColor: item.color,
            width: item.width),
    ];
  }

  static List<double?> _sma(List<double?> source, int length) {
    final result = List<double?>.filled(source.length, null);
    var sum = 0.0;
    var count = 0;
    for (var i = 0; i < source.length; i++) {
      final x = source[i];
      if (x != null) {
        sum += x;
        count++;
      }
      if (i >= length) {
        final previous = source[i - length];
        if (previous != null) {
          sum -= previous;
          count--;
        }
      }
      if (i >= length - 1 && count == length) {
        result[i] = sum / length;
      }
    }
    return result;
  }

  static List<double?> _ema(List<double?> source, int length) {
    final result = List<double?>.filled(source.length, null);
    final alpha = 2 / (length + 1);
    double? state;
    for (var i = 0; i < source.length; i++) {
      final value = source[i];
      if (value != null) {
        state = state == null ? value : (alpha * value + (1 - alpha) * state);
      }
      result[i] = state;
    }
    return result;
  }

  static List<double?> _rsi(List<double?> source, int length) {
    final result = List<double?>.filled(source.length, null);
    if (source.length <= length) return result;
    double? previous;
    var gains = 0.0;
    var losses = 0.0;
    var samples = 0;
    double? avgGain;
    double? avgLoss;
    for (var i = 0; i < source.length; i++) {
      final value = source[i];
      if (value == null) continue;
      if (previous == null) {
        previous = value;
        continue;
      }
      final diff = value - previous;
      previous = value;
      if (avgGain == null || avgLoss == null) {
        gains += math.max(0.0, diff);
        losses += math.max(0.0, -diff);
        samples++;
        if (samples < length) continue;
        avgGain = gains / length;
        avgLoss = losses / length;
      } else {
        avgGain = (avgGain * (length - 1) + math.max(0.0, diff)) / length;
        avgLoss = (avgLoss * (length - 1) + math.max(0.0, -diff)) / length;
      }
      result[i] = avgLoss == 0
          ? 100.0 : (avgGain == 0 ? 0.0 : 100 - 100 / (1 + avgGain / avgLoss));
    }
    return result;
  }

  static List<double?> _roc(List<double?> source, int period) {
    return List<double?>.generate(source.length, (i) {
      if (i < period) return null;
      final current = source[i];
      final previous = source[i - period];
      if (current == null || previous == null || previous == 0) return null;
      final change = 100 * (current - previous) / previous;
      return change.isFinite ? change : null;
    });
  }

  static List<double?> _extreme(
      List<double?> source, int period, bool maximum) {
    final result = List<double?>.filled(source.length, null);
    // O(source length), not O(source * 500) during indicator compilation.
    // Keep verified source indices in one monotonic deque and track na
    // windows explicitly; no missing values are silently synthesized.
    final deque = ListQueue<int>();
    var missing = 0;
    for (var i = 0; i < source.length; i++) {
      final value = source[i];
      if (value == null) {
        missing++;
      } else {
        while (deque.isNotEmpty) {
          final tail = source[deque.last]!;
          if (maximum ? tail <= value : tail >= value) {
            deque.removeLast();
          } else {
            break;
          }
        }
        deque.addLast(i);
      }
      if (i >= period && source[i - period] == null) missing--;
      final oldest = i - period + 1;
      while (deque.isNotEmpty && deque.first < oldest) {
        deque.removeFirst();
      }
      if (i >= period - 1 && missing == 0 && deque.isNotEmpty) {
        result[i] = source[deque.first];
      }
    }
    return result;
  }
}
