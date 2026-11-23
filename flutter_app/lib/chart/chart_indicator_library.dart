import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/tradelab_data.dart';

enum ChartIndicatorKind { sma, ema, bollinger, rsi, macd, atr, stochastic, roc }

/// An immutable description of a real, supported on-chart indicator.
/// All plots are calculated from the CURRENT verified source-candle list.
/// A saved Pine strategy is NEVER silently substituted with a different line.
class ChartIndicatorDefinition {
  const ChartIndicatorDefinition(this.id, this.title, this.period,
      {this.custom = false, this.kindOverride});

  final String id;
  final String title;
  final int period;
  final bool custom;
  final ChartIndicatorKind? kindOverride;

  ChartIndicatorKind get kind {
    if (kindOverride != null) return kindOverride!;
    if (id.startsWith('ema-')) return ChartIndicatorKind.ema;
    if (id.startsWith('bb-')) return ChartIndicatorKind.bollinger;
    if (id.startsWith('rsi-')) return ChartIndicatorKind.rsi;
    if (id == 'macd') return ChartIndicatorKind.macd;
    if (id.startsWith('atr-')) return ChartIndicatorKind.atr;
    if (id.startsWith('stoch-')) return ChartIndicatorKind.stochastic;
    if (id.startsWith('roc-')) return ChartIndicatorKind.roc;
    return ChartIndicatorKind.sma;
  }

  bool get separatePane => kind == ChartIndicatorKind.rsi ||
      kind == ChartIndicatorKind.macd || kind == ChartIndicatorKind.atr ||
      kind == ChartIndicatorKind.stochastic || kind == ChartIndicatorKind.roc;

  @override
  bool operator ==(Object other) => other is ChartIndicatorDefinition &&
      other.id == id && other.period == period &&
      other.title == title && other.custom == custom &&
      other.kindOverride == kindOverride;

  @override
  int get hashCode => Object.hash(id, title, period, custom, kindOverride);

  static const builtIns = <ChartIndicatorDefinition>[
    ChartIndicatorDefinition('sma-12', 'SMA 12', 12),
    ChartIndicatorDefinition('sma-20', 'SMA 20', 20),
    ChartIndicatorDefinition('sma-50', 'SMA 50', 50),
    ChartIndicatorDefinition('sma-200', 'SMA 200', 200),
    ChartIndicatorDefinition('ema-9', 'EMA 9', 9),
    ChartIndicatorDefinition('ema-21', 'EMA 21', 21),
    ChartIndicatorDefinition('ema-50', 'EMA 50', 50),
    ChartIndicatorDefinition('ema-200', 'EMA 200', 200),
    ChartIndicatorDefinition('bb-20', 'Bollinger Bands 20', 20),
    ChartIndicatorDefinition('rsi-14', 'RSI 14', 14),
    ChartIndicatorDefinition('macd', 'MACD (12, 26, 9)', 12),
    ChartIndicatorDefinition('atr-14', 'ATR 14', 14),
    // Built-in STOCH is (periodK=14, smoothK=3, periodD=3).
    // Length editing changes only the raw high/low lookback.
    ChartIndicatorDefinition('stoch-14', 'Stochastic 14', 14),
    ChartIndicatorDefinition('roc-9', 'ROC 9', 9),
  ];
}

/// Saved user-authored source. This is a strict source validation whitelist,
/// not a generic Pine compiler. One ta.sma, ta.ema or ta.rsi single plot can
/// run through native calculations. Other syntax is saved but not evaluated.
class ChartSavedIndicatorScript {
  const ChartSavedIndicatorScript({
    required this.id,
    required this.name,
    required this.source,
  });

  final String id;
  final String name;
  final String source;

  static const maxSourceLength = 15000;
  static const maxNameLength = 80;
  static final RegExp _singlePlot = RegExp(
    r'^plot\s*\(\s*ta\.(sma|ema|rsi)\s*\(\s*close\s*,\s*(\d{1,3})\s*\)\s*\)$');

  /// Safely supported subset; arbitrary source is stored but not executed.
  /// Exactly one direct plot and one indicator declaration, no eval or I/O.
  ChartIndicatorDefinition? supportedIndicator() {
    if (source.length > maxSourceLength) return null;
    final instructions = source.split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('//'))
        .toList(growable: false);
    if (instructions.length != 2) return null;
    final declaration = RegExp(
      r'''^indicator\(\s*["'][^"']{1,80}["']\s*,\s*overlay\s*=\s*(true|false)\s*\)$''')
        .firstMatch(instructions.first);
    final plot = _singlePlot.firstMatch(instructions.last);
    if (declaration == null || plot == null) return null;
    final period = int.tryParse(plot.group(2)!);
    if (period == null || period < 1 || period > 500) return null;
    final kind = switch (plot.group(1)!) {
      'sma' => ChartIndicatorKind.sma,
      'ema' => ChartIndicatorKind.ema,
      _ => ChartIndicatorKind.rsi,
    };
    if (kind == ChartIndicatorKind.rsi && period < 2) return null;
    if ((declaration.group(1) == 'false') !=
        (kind == ChartIndicatorKind.rsi)) return null;
    return ChartIndicatorDefinition(id, name, period,
        custom: true, kindOverride: kind);
  }

  int? get supportedSmaPeriod {
    final parsed = supportedIndicator();
    return parsed?.kind == ChartIndicatorKind.sma ? parsed?.period : null;
  }

  Map<String, Object> toJson() =>
      <String, Object>{'id': id, 'name': name, 'source': source};

  static ChartSavedIndicatorScript? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    final source = value['source'];
    if (id is! String || id.isEmpty || id.length > 72 ||
        !id.startsWith('script-') ||
        name is! String || name.trim().isEmpty ||
        name.length > maxNameLength ||
        source is! String || source.trim().isEmpty ||
        source.length > maxSourceLength) return null;
    return ChartSavedIndicatorScript(id: id, name: name, source: source);
  }
}

/// Device-local indicator selections and saved source. This never touches
/// brokerage OAuth, candle history, orders, results or the trading account.
class ChartIndicatorLibraryState {
  const ChartIndicatorLibraryState({
    this.activeIds = const <String>{},
    this.favoriteIds = const <String>{},
    this.scripts = const <ChartSavedIndicatorScript>[],
    this.periodOverrides = const <String, int>{},
  });

  final Set<String> activeIds;
  final Set<String> favoriteIds;
  final List<ChartSavedIndicatorScript> scripts;
  final Map<String, int> periodOverrides;

  static const maxScripts = 25;
  static const maxActive = 8;

  List<ChartIndicatorDefinition> get supported {
    final result = <ChartIndicatorDefinition>[
      for (final item in ChartIndicatorDefinition.builtIns)
        ChartIndicatorDefinition(
          item.id,
          item.period == (periodOverrides[item.id] ?? item.period)
              ? item.title
              : item.title.replaceFirst(
                  RegExp(r'\d+$'),
                  (periodOverrides[item.id] ?? item.period).toString()),
          periodOverrides[item.id] ?? item.period,
        ),
    ];
    for (final script in scripts) {
      final parsed = script.supportedIndicator();
      if (parsed != null) result.add(parsed);
    }
    return result;
  }

  List<ChartIndicatorDefinition> get active =>
      supported.where((item) => activeIds.contains(item.id))
          .take(maxActive).toList(growable: false);

  bool get hasActive => active.isNotEmpty;

  ChartIndicatorLibraryState copyWith({
    Set<String>? activeIds,
    Set<String>? favoriteIds,
    List<ChartSavedIndicatorScript>? scripts,
    Map<String, int>? periodOverrides,
  }) => ChartIndicatorLibraryState(
    activeIds: Set<String>.unmodifiable(activeIds ?? this.activeIds),
    favoriteIds: Set<String>.unmodifiable(favoriteIds ?? this.favoriteIds),
    scripts: List<ChartSavedIndicatorScript>.unmodifiable(
        scripts ?? this.scripts),
    periodOverrides: Map<String, int>.unmodifiable(
        periodOverrides ?? this.periodOverrides),
  );

  ChartIndicatorLibraryState toggleActive(String id) {
    if (!supported.any((item) => item.id == id)) return this;
    final next = <String>{...activeIds};
    if (!next.remove(id)) {
      if (active.length >= maxActive) return this;
      final proposed = supported.firstWhere((item) => item.id == id);
      if (proposed.separatePane &&
          active.where((item) => item.separatePane).length >= 2) return this;
      next.add(id);
    }
    return copyWith(activeIds: next);
  }

  ChartIndicatorLibraryState setPeriod(String id, int length) {
    if (length < 1 || length > 500) return this;
    final definitions = ChartIndicatorDefinition.builtIns
        .where((item) => item.id == id);
    if (definitions.isEmpty) return this;
    final original = definitions.first;
    if (original.kind == ChartIndicatorKind.macd ||
        (original.kind == ChartIndicatorKind.rsi && length < 2)) return this;
    final updated = <String, int>{...periodOverrides};
    if (length == original.period) {
      updated.remove(id);
    } else {
      updated[id] = length;
    }
    return copyWith(periodOverrides: updated);
  }

  ChartIndicatorLibraryState toggleFavorite(String id) {
    if (!ChartIndicatorDefinition.builtIns.any((item) => item.id == id) &&
        !scripts.any((item) => item.id == id)) return this;
    final next = <String>{...favoriteIds};
    if (!next.remove(id)) next.add(id);
    return copyWith(favoriteIds: next);
  }

  ChartIndicatorLibraryState saveScript(ChartSavedIndicatorScript script) {
    if (ChartSavedIndicatorScript.fromJson(script.toJson()) == null ||
        scripts.length >= maxScripts ||
        scripts.any((item) => item.id == script.id)) return this;
    return copyWith(scripts: [...scripts, script]);
  }

  ChartIndicatorLibraryState deleteScript(String id) {
    return copyWith(
      scripts: scripts.where((script) => script.id != id).toList(),
      activeIds: <String>{...activeIds}..remove(id),
      favoriteIds: <String>{...favoriteIds}..remove(id),
    );
  }

  String encode() => jsonEncode({
    'version': 1,
    'activeIds': activeIds.toList(),
    'favoriteIds': favoriteIds.toList(),
    'scripts': scripts.map((item) => item.toJson()).toList(),
    'periodOverrides': periodOverrides,
  });

  static ChartIndicatorLibraryState decode(String encoded) {
    try {
      if (encoded.length > 500000) return const ChartIndicatorLibraryState();
      final parsed = jsonDecode(encoded);
      if (parsed is! Map || parsed['version'] != 1) {
        return const ChartIndicatorLibraryState();
      }
      final raw = parsed['scripts'];
      final scripts = <ChartSavedIndicatorScript>[];
      if (raw is List) {
        for (final item in raw.take(maxScripts)) {
          final script = ChartSavedIndicatorScript.fromJson(item);
          if (script != null &&
              !scripts.any((existing) => existing.id == script.id)) {
            scripts.add(script);
          }
        }
      }
      final builtIns = <String, ChartIndicatorDefinition>{
        for (final item in ChartIndicatorDefinition.builtIns) item.id: item,
      };
      final overrides = <String, int>{};
      final rawOverrides = parsed['periodOverrides'];
      if (rawOverrides is Map) {
        for (final entry in rawOverrides.entries) {
          final item = builtIns[entry.key];
          final length = entry.value;
          if (item != null && length is int &&
              length >= 1 && length <= 500 &&
              item.kind != ChartIndicatorKind.macd &&
              (item.kind != ChartIndicatorKind.rsi || length >= 2)) {
            overrides[item.id] = length;
          }
        }
      }
      final catalog = ChartIndicatorLibraryState(
          scripts: scripts, periodOverrides: overrides);
      final allowed = catalog.supported.map((item) => item.id).toSet();
      final existing = <String>{
        ...ChartIndicatorDefinition.builtIns.map((item) => item.id),
        ...scripts.map((item) => item.id),
      };
      Set<String> readIds(Object? data, Set<String> valid, int cap) {
        if (data is! List) return <String>{};
        return data.whereType<String>()
            .where(valid.contains).take(cap).toSet();
      }
      return catalog.copyWith(
        activeIds: readIds(parsed['activeIds'], allowed, maxActive),
        favoriteIds: readIds(parsed['favoriteIds'], existing, 50),
      );
    } catch (_) {
      return const ChartIndicatorLibraryState();
    }
  }
}

abstract class ChartIndicatorLibraryStore {
  Future<ChartIndicatorLibraryState> load();
  Future<void> save(ChartIndicatorLibraryState state);
}

class SecureChartIndicatorLibraryStore implements ChartIndicatorLibraryStore {
  SecureChartIndicatorLibraryStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const key = 'tradelab_indicator_library_v1';

  @override
  Future<ChartIndicatorLibraryState> load() async {
    final stored = await _storage.read(key: key);
    return stored == null ? const ChartIndicatorLibraryState() :
        ChartIndicatorLibraryState.decode(stored);
  }

  @override
  Future<void> save(ChartIndicatorLibraryState state) =>
      _storage.write(key: key, value: state.encode());
}

/// Rolling SMA computation only scans the actually displayed indices plus
/// at most [period] authentic historical bars. Pan/pinch remains O(viewport),
/// not O(120k history), and Replay never queries unrevealed future candles.
class ChartIndicatorVisiblePoints {
  const ChartIndicatorVisiblePoints._();

  static List<({int index, double value})> sma({
    required List<TradeCandle> candles,
    required int start,
    required int end,
    required int period,
  }) {
    if (period < 1 || period > 500 || start < 0 ||
        end > candles.length || end <= start) return const [];
    final previousStart = math.max(0, start - period);
    var sum = 0.0;
    for (var i = previousStart; i < start; i++) {
      sum += candles[i].close;
    }
    final values = <({int index, double value})>[];
    for (var i = start; i < end; i++) {
      sum += candles[i].close;
      if (i >= period) sum -= candles[i - period].close;
      final value = sum / math.min(period, i + 1);
      if (value.isFinite) values.add((index: i, value: value));
    }
    return values;
  }
}
