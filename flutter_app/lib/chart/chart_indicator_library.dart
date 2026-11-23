import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/tradelab_data.dart';

/// An immutable description of a real, supported on-chart indicator.
/// All plots are calculated from the CURRENT verified source-candle list.
/// A saved Pine strategy is NEVER silently substituted with a different line.
class ChartIndicatorDefinition {
  const ChartIndicatorDefinition(this.id, this.title, this.period,
      {this.custom = false});

  final String id;
  final String title;
  final int period;
  final bool custom;

  static const builtIns = <ChartIndicatorDefinition>[
    ChartIndicatorDefinition('sma-12', 'SMA 12', 12),
    ChartIndicatorDefinition('sma-20', 'SMA 20', 20),
    ChartIndicatorDefinition('sma-50', 'SMA 50', 50),
    ChartIndicatorDefinition('sma-200', 'SMA 200', 200),
  ];
}

/// Saved user-authored source. Full TradingView Pine is NOT interpreted.
/// Only a standalone overlay indicator containing exactly one
/// plot(ta.sma(close, N)) statement is supported in this first safe bridge.
/// Strategies, strategies with orders, lookahead, request.security, drawings,
/// multiple plots, and other Pine operations remain stored but unexecutable.
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
  static final RegExp _sma =
      RegExp(r'^plot\s*\(\s*ta\.sma\s*\(\s*close\s*,\s*(\d{1,3})\s*\)\s*\)$');

  int? get supportedSmaPeriod {
    if (source.length > maxSourceLength) return null;
    final instructions = source.split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('//'))
        .toList(growable: false);
    if (instructions.length != 2 ||
        !RegExp(r'''^indicator\(\s*["'][^"']{1,80}["']\s*,\s*overlay\s*=\s*true\s*\)$''')
            .hasMatch(instructions.first)) return null;
    final match = _sma.firstMatch(instructions.last);
    if (match == null) return null;
    final period = int.tryParse(match.group(1)!);
    if (period == null || period < 1 || period > 500) return null;
    return period;
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
  });

  final Set<String> activeIds;
  final Set<String> favoriteIds;
  final List<ChartSavedIndicatorScript> scripts;

  static const maxScripts = 25;
  static const maxActive = 8;

  List<ChartIndicatorDefinition> get supported {
    final result = <ChartIndicatorDefinition>[
      ...ChartIndicatorDefinition.builtIns,
    ];
    for (final script in scripts) {
      final period = script.supportedSmaPeriod;
      if (period == null) continue;
      result.add(ChartIndicatorDefinition(
          script.id, script.name, period, custom: true));
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
  }) => ChartIndicatorLibraryState(
    activeIds: Set<String>.unmodifiable(activeIds ?? this.activeIds),
    favoriteIds: Set<String>.unmodifiable(favoriteIds ?? this.favoriteIds),
    scripts: List<ChartSavedIndicatorScript>.unmodifiable(
        scripts ?? this.scripts),
  );

  ChartIndicatorLibraryState toggleActive(String id) {
    if (!supported.any((item) => item.id == id)) return this;
    final next = <String>{...activeIds};
    if (!next.remove(id)) {
      if (active.length >= maxActive) return this;
      next.add(id);
    }
    return copyWith(activeIds: next);
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
      final catalog = ChartIndicatorLibraryState(scripts: scripts);
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
