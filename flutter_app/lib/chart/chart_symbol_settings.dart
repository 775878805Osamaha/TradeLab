import 'dart:convert';

/// Time labels are presentation-only. The source UTC candle timestamps remain
/// untouched, including while Replay and the local candle cache are active.
enum ChartTimeZone {
  newYork,
  utc,
  device;

  String get nameArabic => switch (this) {
    ChartTimeZone.newYork => 'نيويورك',
    ChartTimeZone.utc => 'UTC',
    ChartTimeZone.device => 'توقيت الجهاز',
  };

  /// Eastern US DST: since 2007 it runs from the second Sunday in March at
  /// 02:00 EST to the first Sunday in November at 02:00 EDT. Older historical
  /// bars use the pre-2007 federal rule from 1987 onward.
  static Duration newYorkOffset(DateTime timestampUtc) {
    final instant = timestampUtc.toUtc();
    final year = instant.year;
    if (year < 1987) return const Duration(hours: -5);
    final start = year >= 2007
        ? DateTime.utc(year, 3, _nthSunday(year, 3, 2), 7)
        : DateTime.utc(year, 4, _nthSunday(year, 4, 1), 7);
    final end = year >= 2007
        ? DateTime.utc(year, 11, _nthSunday(year, 11, 1), 6)
        : DateTime.utc(year, 10, _lastSunday(year, 10), 6);
    return !instant.isBefore(start) && instant.isBefore(end)
        ? const Duration(hours: -4)
        : const Duration(hours: -5);
  }

  static int _nthSunday(int year, int month, int ordinal) {
    final first = DateTime.utc(year, month).weekday;
    return 1 + (7 - first) % 7 + 7 * (ordinal - 1);
  }

  static int _lastSunday(int year, int month) {
    final lastDay = DateTime.utc(year, month + 1, 0);
    return lastDay.day - lastDay.weekday % 7;
  }

  DateTime displayDate(int utcMilliseconds) {
    final instant = DateTime.fromMillisecondsSinceEpoch(
      utcMilliseconds, isUtc: true);
    return switch (this) {
      ChartTimeZone.newYork => instant.add(newYorkOffset(instant)),
      ChartTimeZone.utc => instant,
      ChartTimeZone.device => instant.toLocal(),
    };
  }

  String labelAt(DateTime timestampUtc) => switch (this) {
    ChartTimeZone.newYork =>
      'نيويورك (UTC${newYorkOffset(timestampUtc).inHours})',
    ChartTimeZone.utc => 'UTC',
    ChartTimeZone.device => 'توقيت الجهاز',
  };
}

/// Immutable symbol appearance/axis preferences. None of these fields modify
/// OHLC, broker sources, downloaded bars or the Replay cursor.
class ChartSymbolSettings {
  const ChartSymbolSettings({
    this.colorByPreviousClose = true,
    this.bodyVisible = true,
    this.borderVisible = true,
    this.wickVisible = true,
    this.bodyBull = 0xFF089981,
    this.bodyBear = 0xFFF23645,
    this.borderBull = 0xFF089981,
    this.borderBear = 0xFFF23645,
    this.wickBull = 0xFF089981,
    this.wickBear = 0xFFF23645,
    this.precisionDigits,
    this.timeZone = ChartTimeZone.newYork,
  });

  final bool colorByPreviousClose;
  final bool bodyVisible;
  final bool borderVisible;
  final bool wickVisible;
  final int bodyBull;
  final int bodyBear;
  final int borderBull;
  final int borderBear;
  final int wickBull;
  final int wickBear;
  /// Null means the automatic value selected from the real chart tick step.
  final int? precisionDigits;
  final ChartTimeZone timeZone;

  int digitsForTickStep(int automaticallySelected) =>
      precisionDigits ?? automaticallySelected;

  ChartSymbolSettings copyWith({
    bool? colorByPreviousClose,
    bool? bodyVisible,
    bool? borderVisible,
    bool? wickVisible,
    int? bodyBull,
    int? bodyBear,
    int? borderBull,
    int? borderBear,
    int? wickBull,
    int? wickBear,
    ChartTimeZone? timeZone,
  }) => ChartSymbolSettings(
    colorByPreviousClose: colorByPreviousClose ?? this.colorByPreviousClose,
    bodyVisible: bodyVisible ?? this.bodyVisible,
    borderVisible: borderVisible ?? this.borderVisible,
    wickVisible: wickVisible ?? this.wickVisible,
    bodyBull: bodyBull ?? this.bodyBull,
    bodyBear: bodyBear ?? this.bodyBear,
    borderBull: borderBull ?? this.borderBull,
    borderBear: borderBear ?? this.borderBear,
    wickBull: wickBull ?? this.wickBull,
    wickBear: wickBear ?? this.wickBear,
    precisionDigits: precisionDigits,
    timeZone: timeZone ?? this.timeZone,
  );

  ChartSymbolSettings withPrecision(int? digits) => ChartSymbolSettings(
    colorByPreviousClose: colorByPreviousClose,
    bodyVisible: bodyVisible,
    borderVisible: borderVisible,
    wickVisible: wickVisible,
    bodyBull: bodyBull,
    bodyBear: bodyBear,
    borderBull: borderBull,
    borderBear: borderBear,
    wickBull: wickBull,
    wickBear: wickBear,
    precisionDigits: digits,
    timeZone: timeZone,
  );

  String encode() => jsonEncode({
    'colorByPreviousClose': colorByPreviousClose,
    'bodyVisible': bodyVisible,
    'borderVisible': borderVisible,
    'wickVisible': wickVisible,
    'bodyBull': bodyBull,
    'bodyBear': bodyBear,
    'borderBull': borderBull,
    'borderBear': borderBear,
    'wickBull': wickBull,
    'wickBear': wickBear,
    'precisionDigits': precisionDigits,
    'timeZone': timeZone.name,
  });

  static ChartSymbolSettings decode(String stored) {
    try {
      final data = jsonDecode(stored);
      if (data is! Map<String, dynamic>) return const ChartSymbolSettings();
      final digits = data['precisionDigits'];
      return ChartSymbolSettings(
        colorByPreviousClose: data['colorByPreviousClose'] is bool
          ? data['colorByPreviousClose'] as bool : true,
        bodyVisible: data['bodyVisible'] is bool
          ? data['bodyVisible'] as bool : true,
        borderVisible: data['borderVisible'] is bool
          ? data['borderVisible'] as bool : true,
        wickVisible: data['wickVisible'] is bool
          ? data['wickVisible'] as bool : true,
        bodyBull: _safeColor(data['bodyBull'], 0xFF089981),
        bodyBear: _safeColor(data['bodyBear'], 0xFFF23645),
        borderBull: _safeColor(data['borderBull'], 0xFF089981),
        borderBear: _safeColor(data['borderBear'], 0xFFF23645),
        wickBull: _safeColor(data['wickBull'], 0xFF089981),
        wickBear: _safeColor(data['wickBear'], 0xFFF23645),
        precisionDigits: digits is int && digits >= 0 && digits <= 8
            ? digits : null,
        timeZone: ChartTimeZone.values.firstWhere(
          (e) => e.name == data['timeZone'],
          orElse: () => ChartTimeZone.newYork),
      );
    } catch (_) {
      return const ChartSymbolSettings();
    }
  }

  static int _safeColor(Object? raw, int fallback) =>
    raw is int && raw >= 0 && raw <= 0xFFFFFFFF ? raw : fallback;
}
