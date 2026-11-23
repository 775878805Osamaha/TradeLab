import 'dart:math' as math;

/// A deliberately small typed value boundary for the *numeric Pine subset*.
/// In Pine v6 booleans are never na. Arithmetic with numeric na is na, whereas
/// any valid comparison involving a missing numeric operand evaluates to false.
/// See https://www.tradingview.com/pine-script-docs/language/type-system/
enum PineValueType { number, boolean }

class PineValue {
  const PineValue._(this.type, this.number, this.boolean, this.isNa);

  static const PineValue na = PineValue._(
    PineValueType.number, null, null, true);
  static const PineValue falseValue = PineValue._(
    PineValueType.boolean, null, false, false);
  static const PineValue trueValue = PineValue._(
    PineValueType.boolean, null, true, false);

  final PineValueType type;
  final double? number;
  final bool? boolean;
  final bool isNa;

  factory PineValue.numeric(double? value) =>
      value == null || !value.isFinite
          ? PineValue.na
          : PineValue._(PineValueType.number, value, null, false);

  factory PineValue.logical(bool value) =>
      value ? PineValue.trueValue : PineValue.falseValue;

  static PineValue arithmetic(
      String operation, PineValue left, PineValue right) {
    if (left.type != PineValueType.number ||
        right.type != PineValueType.number) {
      throw const FormatException('Arithmetic requires numeric operands');
    }
    if (left.isNa || right.isNa) return PineValue.na;
    final x = left.number!;
    final y = right.number!;
    if (operation == '/' && y == 0) return PineValue.na;
    final value = switch (operation) {
      '+' => x + y,
      '-' => x - y,
      '*' => x * y,
      '/' => x / y,
      _ => throw FormatException('Unsupported arithmetic: ' + operation),
    };
    return PineValue.numeric(value);
  }

  /// All six v6 comparisons return an actual bool. Both == and != involving
  /// an na numeric operand return false; direct literal 'x == na' remains
  /// unsupported by the subset parser rather than being silently accepted.
  static PineValue compare(
      String operation, PineValue left, PineValue right) {
    if (left.isNa || right.isNa) return PineValue.falseValue;
    if (left.type != right.type) {
      throw const FormatException('Comparison operand type mismatch');
    }
    if (left.type == PineValueType.boolean) {
      if (operation != '==' && operation != '!=') {
        throw const FormatException('Boolean ordering not supported');
      }
      final equal = left.boolean == right.boolean;
      return PineValue.logical(operation == '==' ? equal : !equal);
    }
    final x = left.number!;
    final y = right.number!;
    return PineValue.logical(switch (operation) {
      '==' => x == y,
      '!=' => x != y,
      '<' => x < y,
      '<=' => x <= y,
      '>' => x > y,
      '>=' => x >= y,
      _ => throw FormatException('Unsupported comparison: ' + operation),
    });
  }

  @override
  String toString() => isNa
      ? 'na'
      : type == PineValueType.number
          ? number.toString()
          : boolean.toString();
}

/// Fixed-capacity history, independent of output-plot storage. No future
/// index can be read, and values older than the retained window return na.
/// A v6 boolean series instead returns false on insufficient history.
class PineSeries {
  PineSeries({required this.historyLimit,
      this.type = PineValueType.number})
      : assert(historyLimit > 0),
        _ring = List<PineValue>.filled(
            historyLimit, type == PineValueType.boolean
                ? PineValue.falseValue : PineValue.na);

  final int historyLimit;
  final PineValueType type;
  final List<PineValue> _ring;
  int _length = 0;

  int get length => _length;
  PineValue get _missing =>
      type == PineValueType.boolean ? PineValue.falseValue : PineValue.na;

  void append(PineValue value) {
    if (type != value.type) {
      throw const FormatException('Pine series value type mismatch');
    }
    _ring[_length % historyLimit] = value;
    _length++;
  }

  PineValue absolute(int index) {
    if (index < 0 || index >= _length ||
        _length - index > historyLimit) return _missing;
    return _ring[index % historyLimit];
  }

  PineValue history(int barsAgo) {
    if (barsAgo < 0) return _missing;
    return absolute(_length - 1 - barsAgo);
  }

  void reset() {
    _length = 0;
    _ring.fillRange(0, historyLimit, _missing);
  }
}

class PineRuntimeException implements Exception {
  const PineRuntimeException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => 'PineRuntimeException(' + code + '): ' + message;
}

/// Hard per-execution limits. A finite timeout is a cooperative deadline,
/// not preemption: the evaluator checks it on each bounded work interval.
/// Calls must not execute foreign code or unbounded native operations.
class PineRuntimeLimits {
  const PineRuntimeLimits({
    this.maxSteps = 20000000,
    this.maxStoredValues = 3000000,
    this.maxHistory = 5001,
    this.timeout = const Duration(seconds: 30),
  }) : assert(maxSteps > 0),
       assert(maxStoredValues > 0),
       assert(maxHistory > 0);

  final int maxSteps;
  final int maxStoredValues;
  final int maxHistory;
  final Duration timeout;
}

class PineRuntimeBudget {
  PineRuntimeBudget([this.limits = const PineRuntimeLimits()])
      : _clock = Stopwatch()..start();

  final PineRuntimeLimits limits;
  final Stopwatch _clock;
  int steps = 0;
  int storedValues = 0;

  void consume({int work = 1, int values = 0}) {
    if (work < 0 || values < 0) {
      throw ArgumentError('Negative Pine execution budget charge');
    }
    if (steps > limits.maxSteps - work) {
      throw const PineRuntimeException(
          'step_limit', 'Pine instruction budget exceeded');
    }
    if (storedValues > limits.maxStoredValues - values) {
      throw const PineRuntimeException(
          'memory_limit', 'Pine series storage budget exceeded');
    }
    steps += work;
    storedValues += values;
    // Periodic monotonic deadline check avoids a clock syscall per AST node.
    if (steps < 2 || steps % 256 < work) checkTime();
  }

  void checkTime() {
    if (_clock.elapsed >= limits.timeout) {
      throw const PineRuntimeException(
          'timeout', 'Pine execution deadline exceeded');
    }
  }

  void stop() => _clock.stop();

  /// Number of physical ring slots that will remain resident.
  void reserveHistory(int requested) {
    if (requested < 1 || requested > limits.maxHistory) {
      throw const PineRuntimeException(
          'history_limit', 'Pine history allocation exceeds configured cap');
    }
    consume(work: 0, values: requested);
  }
}

/// Protect a chart from storing a mutable list that is accidentally shared
/// between independent indicator instances or Replay sessions.
List<T> immutableSnapshot<T>(Iterable<T> source) =>
    List<T>.unmodifiable(source);

/// An explicitly bounded helper for numeric initialization when materializing
/// a prefix (used by regression tests, not a broker data source).
PineSeries numericPineHistory(Iterable<double?> values, int cap) {
  final series = PineSeries(historyLimit: math.max(1, cap));
  for (final value in values) {
    series.append(PineValue.numeric(value));
  }
  return series;
}
