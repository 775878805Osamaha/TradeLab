import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/tradelab_data.dart';
import 'pine_v6_frontend.dart';

enum ChartIndicatorKind { sma, ema, bollinger, rsi, macd, atr, stochastic, roc, pine }

/// An immutable description of a real, supported on-chart indicator.
/// All plots are calculated from the CURRENT verified source-candle list.
/// A saved Pine strategy is NEVER silently substituted with a different line.
class ChartIndicatorDefinition {
  const ChartIndicatorDefinition(this.id, this.title, this.period,
      {this.custom = false, this.kindOverride,
       this.pineSource, this.pineOverlay = true});

  final String id;
  final String title;
  final int period;
  final bool custom;
  final ChartIndicatorKind? kindOverride;
  /// Only populated after the restricted series compiler validated source.
  final String? pineSource;
  final bool pineOverlay;

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

  bool get separatePane => (kind == ChartIndicatorKind.pine && !pineOverlay) ||
      kind == ChartIndicatorKind.rsi ||
      kind == ChartIndicatorKind.macd || kind == ChartIndicatorKind.atr ||
      kind == ChartIndicatorKind.stochastic || kind == ChartIndicatorKind.roc;

  @override
  bool operator ==(Object other) => other is ChartIndicatorDefinition &&
      other.id == id && other.period == period &&
      other.title == title && other.custom == custom &&
      other.kindOverride == kindOverride &&
      other.pineSource == pineSource && other.pineOverlay == pineOverlay;

  @override
  int get hashCode => Object.hash(id, title, period, custom, kindOverride,
      pineSource, pineOverlay);

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
    if (instructions.length != 2) return _compileSeries();
    final declaration = RegExp(
      r'''^indicator\(\s*["'][^"']{1,80}["']\s*,\s*overlay\s*=\s*(true|false)\s*\)$''')
        .firstMatch(instructions.first);
    final plot = _singlePlot.firstMatch(instructions.last);
    if (declaration == null || plot == null) return _compileSeries();
    final period = int.tryParse(plot.group(2)!);
    if (period == null || period < 1 || period > 500) return _compileSeries();
    final kind = switch (plot.group(1)!) {
      'sma' => ChartIndicatorKind.sma,
      'ema' => ChartIndicatorKind.ema,
      _ => ChartIndicatorKind.rsi,
    };
    if (kind == ChartIndicatorKind.rsi && period < 2) return _compileSeries();
    if ((declaration.group(1) == 'false') !=
        (kind == ChartIndicatorKind.rsi)) return _compileSeries();
    return ChartIndicatorDefinition(id, name, period,
        custom: true, kindOverride: kind);
  }

  ChartIndicatorDefinition? _compileSeries() {
    final checked = const PineV6Frontend().prepare(source);
    final program = checked.legacyProgram;
    if (!checked.canExecute || program == null) return null;
    return ChartIndicatorDefinition(id, name, 1,
        custom: true,
        kindOverride: ChartIndicatorKind.pine,
        pineSource: source,
        pineOverlay: program.overlay);
  }

  /// Human-readable compile result for unsupported saved source.
  String? get compileError {
    final checked = const PineV6Frontend().prepare(source);
    if (checked.canExecute) return null;
    final diagnostic = checked.diagnostics.isEmpty
        ? null : checked.diagnostics.first;
    if (diagnostic == null) return 'Pine: غير مدعوم بعد';
    return 'السطر ' + diagnostic.line.toString() +
        '، العمود ' + diagnostic.column.toString() +
        ' (' + diagnostic.code + '): ' + diagnostic.message;
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
    this.activeOrder = const <String>[],
    this.paneHeights = const <String, int>{},
  });

  final Set<String> activeIds;
  final Set<String> favoriteIds;
  final List<ChartSavedIndicatorScript> scripts;
  final Map<String, int> periodOverrides;
  /// The order of rendered overlays and sub-panes; old saves without this
  /// list fall back to the original built-in catalog order.
  final List<String> activeOrder;
  /// Resizable independent study panes use per-id device-local heights.
  final Map<String, int> paneHeights;

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

  List<ChartIndicatorDefinition> get active {
    final catalog = supported;
    final byId = <String, ChartIndicatorDefinition>{
      for (final item in catalog) item.id: item,
    };
    final valid = catalog.where((item) => activeIds.contains(item.id))
        .map((item) => item.id).toList(growable: false);
    final order = <String>{
      ...activeOrder.where((id) => activeIds.contains(id) &&
          byId.containsKey(id)),
      ...valid,
    };
    return order.take(maxActive).map((id) => byId[id]!)
        .toList(growable: false);
  }

  int heightForPane(String id) =>
      paneHeights[id]?.clamp(84, 192).toInt() ?? 106;

  ChartIndicatorLibraryState resizePane(String id, int height) {
    final activePane = active.any((item) => item.id == id &&
        item.separatePane);
    if (!activePane || height < 84 || height > 192) return this;
    final next = <String, int>{...paneHeights};
    if (height == 106) {
      next.remove(id);
    } else {
      next[id] = height;
    }
    return copyWith(paneHeights: next);
  }

  /// Move a pane relative to other panes, without losing overlay positions.
  ChartIndicatorLibraryState movePane(String id, int direction) {
    if (direction != -1 && direction != 1) return this;
    final current = active.map((item) => item.id).toList();
    final panes = active.where((item) => item.separatePane)
        .map((item) => item.id).toList();
    final index = panes.indexOf(id);
    final target = index + direction;
    if (index < 0 || target < 0 || target >= panes.length) return this;
    final first = current.indexOf(panes[index]);
    final second = current.indexOf(panes[target]);
    final tmp = current[first];
    current[first] = current[second];
    current[second] = tmp;
    return copyWith(activeOrder: current);
  }

  /// Change the stacking order of active overlays or independent panes
  /// without accidentally moving an overlay into the pane list.
  ChartIndicatorLibraryState moveActive(String id, int direction) {
    if (direction != -1 && direction != 1) return this;
    final studies = active;
    final kind = studies.where((item) =>
        item.separatePane == studies.any((value) =>
            value.id == id && value.separatePane))
        .map((item) => item.id).toList();
    final at = kind.indexOf(id);
    final nextIndex = at + direction;
    if (at < 0 || nextIndex < 0 || nextIndex >= kind.length) return this;
    final ordering = studies.map((item) => item.id).toList();
    final first = ordering.indexOf(kind[at]);
    final second = ordering.indexOf(kind[nextIndex]);
    final swap = ordering[first];
    ordering[first] = ordering[second];
    ordering[second] = swap;
    return copyWith(activeOrder: ordering);
  }

  /// Remove all *visible* indicators while preserving the user's source
  /// drafts, favorites, and custom lengths. No broker or chart data changes.
  ChartIndicatorLibraryState clearActive() {
    if (activeIds.isEmpty) return this;
    return copyWith(activeIds: <String>{},
        activeOrder: <String>[], paneHeights: <String, int>{});
  }

  bool get hasActive => active.isNotEmpty;

  ChartIndicatorLibraryState copyWith({
    Set<String>? activeIds,
    Set<String>? favoriteIds,
    List<ChartSavedIndicatorScript>? scripts,
    Map<String, int>? periodOverrides,
    List<String>? activeOrder,
    Map<String, int>? paneHeights,
  }) => ChartIndicatorLibraryState(
    activeIds: Set<String>.unmodifiable(activeIds ?? this.activeIds),
    favoriteIds: Set<String>.unmodifiable(favoriteIds ?? this.favoriteIds),
    scripts: List<ChartSavedIndicatorScript>.unmodifiable(
        scripts ?? this.scripts),
    periodOverrides: Map<String, int>.unmodifiable(
        periodOverrides ?? this.periodOverrides),
    activeOrder: List<String>.unmodifiable(activeOrder ?? this.activeOrder),
    paneHeights: Map<String, int>.unmodifiable(
        paneHeights ?? this.paneHeights),
  );

  ChartIndicatorLibraryState toggleActive(String id) {
    if (!supported.any((item) => item.id == id)) return this;
    final next = <String>{...activeIds};
    final ordered = active.map((item) => item.id).toList();
    final heights = <String, int>{...paneHeights};
    if (next.remove(id)) {
      ordered.remove(id);
      heights.remove(id);
    } else {
      if (active.length >= maxActive) return this;
      final proposed = supported.firstWhere((item) => item.id == id);
      if (proposed.separatePane &&
          active.where((item) => item.separatePane).length >= 2) return this;
      next.add(id);
      ordered.add(id);
    }
    return copyWith(activeIds: next, activeOrder: ordered,
        paneHeights: heights);
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

  /// Replacing saved Pine source is atomic. Unsupported or pane-changing
  /// edits never leave an old running program attached to the real chart.
  /// A user can still retain an unsupported draft locally without execution.
  ChartIndicatorLibraryState updateScript({
    required String id,
    required String name,
    required String source,
  }) {
    final index = scripts.indexWhere((item) => item.id == id);
    if (index < 0) return this;
    final replacement = ChartSavedIndicatorScript(
      id: id, name: name, source: source);
    if (ChartSavedIndicatorScript.fromJson(replacement.toJson()) == null) {
      return this;
    }
    final updatedScripts = [...scripts]..[index] = replacement;
    final nextActive = <String>{...activeIds};
    final nextOrder = [...activeOrder];
    final heights = <String, int>{...paneHeights};
    final before = scripts[index].supportedIndicator();
    final after = replacement.supportedIndicator();
    if (after == null ||
        (before != null && before.separatePane != after.separatePane)) {
      nextActive.remove(id);
      nextOrder.remove(id);
      heights.remove(id);
    }
    return copyWith(
      scripts: updatedScripts,
      activeIds: nextActive,
      activeOrder: nextOrder,
      paneHeights: heights,
    );
  }

  ChartIndicatorLibraryState deleteScript(String id) {
    return copyWith(
      scripts: scripts.where((script) => script.id != id).toList(),
      activeIds: <String>{...activeIds}..remove(id),
      favoriteIds: <String>{...favoriteIds}..remove(id),
      activeOrder: activeOrder.where((item) => item != id).toList(),
      paneHeights: <String, int>{...paneHeights}..remove(id),
    );
  }

  String encode() => jsonEncode({
    'version': 1,
    'activeIds': activeIds.toList(),
    'favoriteIds': favoriteIds.toList(),
    'scripts': scripts.map((item) => item.toJson()).toList(),
    'periodOverrides': periodOverrides,
    'activeOrder': activeOrder,
    'paneHeights': paneHeights,
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
      final active = readIds(parsed['activeIds'], allowed, maxActive);
      final rawOrder = parsed['activeOrder'];
      final ordered = <String>[];
      if (rawOrder is List) {
        for (final id in rawOrder.whereType<String>()) {
          if (active.contains(id) && !ordered.contains(id) &&
              ordered.length < maxActive) ordered.add(id);
        }
      }
      for (final item in catalog.supported) {
        if (active.contains(item.id) && !ordered.contains(item.id)) {
          ordered.add(item.id);
        }
      }
      final heights = <String, int>{};
      final rawHeights = parsed['paneHeights'];
      final byId = <String, ChartIndicatorDefinition>{
        for (final item in catalog.supported) item.id: item,
      };
      if (rawHeights is Map) {
        for (final entry in rawHeights.entries) {
          final id = entry.key;
          final pixels = entry.value;
          if (id is String && pixels is int && pixels >= 84 &&
              pixels <= 192 && active.contains(id) &&
              byId[id]?.separatePane == true) {
            heights[id] = pixels;
          }
        }
      }
      return catalog.copyWith(
        activeIds: active,
        favoriteIds: readIds(parsed['favoriteIds'], existing, 50),
        activeOrder: ordered,
        paneHeights: heights,
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
