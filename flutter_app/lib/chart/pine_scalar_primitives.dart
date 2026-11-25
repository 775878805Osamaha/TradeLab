import 'dart:collection';
import 'dart:math' as math;
import 'pine_runtime_core.dart';

/// Independent, closed-bar calculation candidates. No runtime registration
/// until reference and integration tests establish the supported signatures.
/// A missing numeric Pine value is null; no synthetic price or time context.
abstract final class PineScalarPrimitives {
  // https://www.tradingview.com/pine-script-reference/v6/#fun_math.floor
  static int? floor(num? number) {
    if (number == null || !number.isFinite) return null;
    // Dart native integers are signed 64 bit. Refuse out-of-range conversion.
    if (number < -9223372036854775808.0 ||
        number >= 9223372036854775808.0) {
      throw const PineRuntimeException('integer_range', 'Floor exceeds signed integer range');
    }
    return number.floor();
  }

  // https://www.tradingview.com/pine-script-reference/v6/#fun_math.sign
  static double? sign(num? number) {
    if (number == null || !number.isFinite) return null;
    return number < 0 ? -1.0 : number > 0 ? 1.0 : 0.0;
  }

  // https://www.tradingview.com/pine-script-docs/concepts/strings/
  // Candidate scalar decimal patterns only. Collections, preset tick/volume
  // formats and other patterns remain gated; no guessed instrument metadata.
  static String toText(Object? value, {String format = '#.########'}) {
    if (value == null || (value is num && !value.isFinite)) return 'NaN';
    if (value is bool || value is String) return value.toString();
    if (value is! num) {
      throw const PineRuntimeException('unsupported_string_value', 'Unsupported scalar conversion');
    }
    if (!RegExp(r'^[#0]{1,16}(?:\.[#0]{1,8})?%?$').hasMatch(format)) {
      throw const PineRuntimeException('unsupported_number_format', 'Number format requires a verified implementation');
    }
    final percent = format.endsWith('%');
    final pattern = percent ? format.substring(0, format.length - 1) : format;
    final pieces = pattern.split('.');
    final fraction = pieces.length == 2 ? pieces[1] : '';
    final minimumFraction = '0'.allMatches(fraction).length;
    final minimumInteger = math.max(1, '0'.allMatches(pieces[0]).length);
    final magnitude = value.abs() * (percent ? 100 : 1);
    if (!magnitude.isFinite || magnitude >= 1e15) {
      throw const PineRuntimeException('unsupported_number_range', 'Decimal formatting exceeds verified candidate range');
    }
    final fixed = magnitude.toStringAsFixed(fraction.length).split('.');
    final whole = fixed[0].padLeft(minimumInteger, '0');
    var tail = fixed.length == 2 ? fixed[1] : '';
    while (tail.length > minimumFraction && tail.endsWith('0')) {
      tail = tail.substring(0, tail.length - 1);
    }
    final negative = value < 0 && (fixed[0] != '0' || tail.contains(RegExp('[1-9]')));
    return (negative ? '-' : '') + whole + (tail.isEmpty ? '' : '.' + tail)
        + (percent ? '%' : '');
  }

  // https://www.tradingview.com/pine-script-docs/concepts/time/
  // Explicit UTC/fixed offset only. Exchange defaults and IANA/DST require
  // a real market context; never substitute device timezone. Per Pine docs,
  // na timestamp is interpreted as Unix epoch zero by str.format_time().
  static String formatTime(int? timestamp, {required String format,
      required String timezone}) {
    final zone = RegExp(r'^UTC(?:([+-])(\d{1,2})(?::(\d{2}))?)?$').firstMatch(timezone);
    if (zone == null) {
      throw const PineRuntimeException('unsupported_timezone', 'Only explicit UTC offsets are implemented in this candidate');
    }
    final hours = int.parse(zone.group(2) ?? '0');
    final minutes = int.parse(zone.group(3) ?? '0');
    if (hours > 14 || minutes > 59 || (hours == 14 && minutes != 0)) {
      throw const PineRuntimeException('timezone_range', 'UTC offset outside candidate range');
    }
    final offset = (hours * 60 + minutes) * (zone.group(1) == '-' ? -1 : 1);
    final int ms = timestamp ?? 0;
    if (ms.abs() > 8640000000000000 - 86400000) {
      throw const PineRuntimeException('timestamp_range', 'Timestamp outside safe DateTime range');
    }
    final date = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true)
        .add(Duration(minutes: offset));
    String pad(int n, int size) => n.toString().padLeft(size, '0');
    if (date.year < 1 || date.year > 9999) {
      throw const PineRuntimeException('unsupported_date_range', 'Only Gregorian years 1 through 9999 verified');
    }
    final tokens = <String,String>{
      'yyyy':pad(date.year,4), 'MM':pad(date.month,2), 'dd':pad(date.day,2),
      'HH':pad(date.hour,2), 'mm':pad(date.minute,2), 'ss':pad(date.second,2),
      'SSS':pad(date.millisecond,3),
    };
    if (format.isEmpty || format.length > 128) {
      throw const PineRuntimeException('unsupported_time_format', 'Invalid candidate time format length');
    }
    final out = StringBuffer();
    for (var i = 0; i < format.length;) {
      String? match;
      for (final token in tokens.keys) {
        if (format.startsWith(token, i)) {match = token;break;}
      }
      if (match != null) {
        out.write(tokens[match]);i += match.length;
      } else if (' -/:.,'.contains(format[i])) {
        out.write(format[i++]);
      } else {
        throw const PineRuntimeException('unsupported_time_format', 'Unverified date/time token');
      }
    }
    return out.toString();
  }

  // https://www.tradingview.com/pine-script-docs/visuals/colors/
  // RGBA is kept separate from numeric Pine values. This operates on an
  // already resolved color, not an inferred symbol palette.
  static PineRgba? withTransparency(PineRgba? color, num? transparency) {
    if (color == null || transparency == null || !transparency.isFinite) return null;
    if (transparency < 0 || transparency > 100) {
      throw const PineRuntimeException('transparency_range', 'Transparency must be 0 through 100');
    }
    final alpha = (255 * (100 - transparency) / 100).round();
    return PineRgba(color.red, color.green, color.blue, alpha);
  }
}

final class PineRgba {
  const PineRgba(this.red,this.green,this.blue,this.alpha)
      : assert(red >= 0 && red <= 255),
        assert(green >= 0 && green <= 255),
        assert(blue >= 0 && blue <= 255),
        assert(alpha >= 0 && alpha <= 255);
  final int red,green,blue,alpha;
  int get argb => (alpha << 24) | (red << 16) | (green << 8) | blue;
}

/// https://www.tradingview.com/pine-script-reference/v6/#fun_math.sum
/// The reference specifies length non-na samples. Retain the bounded
/// non-na window so changing a series length cannot accidentally discard
/// older available samples. Each instance belongs to one written call path.
final class PineRollingSum {
  PineRollingSum(this.budget, {this.capacity = 500}) {
    budget.reserveHistory(capacity);
  }
  final PineRuntimeBudget budget;
  final int capacity;
  final Queue<double> _samples = Queue<double>();

  double? step(num? source, int length) {
    if (length < 1 || length > capacity) {
      throw const PineRuntimeException('length', 'math.sum length exceeds bounded history');
    }
    // Charge worst-case traversal before mutating state.
    budget.consume(work: capacity);
    if (source != null && source.isFinite) {
      if (_samples.length == capacity) _samples.removeFirst();
      _samples.addLast(source.toDouble());
    }
    if (_samples.length < length) return null;
    var result = 0.0;
    for (final value in _samples.skip(_samples.length - length)) {
      result += value;
    }
    return result.isFinite ? result : null;
  }
}
