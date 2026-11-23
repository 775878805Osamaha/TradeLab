import '../data/tradelab_data.dart';
import 'pine_runtime_core.dart';
import 'pine_subset_program.dart';

/// A saved definition and a visible *running* copy have different identities.
/// This is deliberately independent from ChartIndicatorLibraryState's legacy
/// activeIds so existing user preferences are not rewritten in Stage 1.
class PineIndicatorDefinition {
  const PineIndicatorDefinition({
    required this.id, required this.source, required this.program,
  });
  final String id;
  final String source;
  final PineSubsetProgram program;

  factory PineIndicatorDefinition.compile(String id, String source) =>
      PineIndicatorDefinition(
        id: id, source: source,
        program: PineSubsetProgram.compile(source),
      );
}

/// Stateful per-instance runtime. No global shared series, TA accumulators,
/// input overrides, or variable memory. Full v6 var/varip syntax is NOT part
/// of this subset yet; persistentState provides isolated storage for stage 2.
class PineIndicatorInstance {
  PineIndicatorInstance({
    required this.instanceId,
    required this.definition,
    Map<String, double> inputs = const {},
    this.limits = const PineRuntimeLimits(),
  }) : inputs = Map<String, double>.unmodifiable(inputs) {
    _runtime = definition.program.startExecutor(
        inputs: this.inputs, limits: limits);
  }

  final String instanceId;
  final PineIndicatorDefinition definition;
  final Map<String, double> inputs;
  final PineRuntimeLimits limits;
  final Map<String, PineValue> persistentState = {};
  PineBarExecutor? _runtime;

  int get completedBars => _runtime?.completedBars ?? 0;

  /// Each instance owns its own series; no external mutable buffer escapes.
  PineValue seriesAt(String name, int barsAgo) =>
      _runtime?.seriesAt(name, barsAgo) ?? PineValue.na;
  List<PineSubsetPlot> get outputs => _runtime?.outputs ?? const [];

  /// Intended for verified streaming closes only. If a budget is exceeded,
  /// poison no other instance: this executor is closed and must be rebuilt.
  void advance(TradeCandle bar) {
    final runtime = _runtime;
    if (runtime == null) {
      throw const PineRuntimeException(
          'instance_stopped', 'Rebuild the indicator after runtime failure');
    }
    try {
      runtime.advance(bar);
    } on PineRuntimeException {
      runtime.close();
      _runtime = null;
      rethrow;
    } catch (_) {
      runtime.close();
      _runtime = null;
      rethrow;
    }
  }

  /// Replay always rebuilds from the actual prefix, not a previously cached
  /// future or mutable state. The caller owns [source] (real OHLCV).
  /// On failure the old executor is left intact; the candidate is closed.
  void rebuild(List<TradeCandle> source, int visibleCount) {
    if (visibleCount < 0 || visibleCount > source.length) {
      throw const PineRuntimeException(
          'invalid_cutoff', 'Replay cutoff lies outside verified source');
    }
    final candidate = definition.program.startExecutor(
        inputs: inputs, limits: limits);
    try {
      for (var index = 0; index < visibleCount; index++) {
        candidate.advance(source[index]);
      }
    } catch (_) {
      candidate.close();
      rethrow;
    }
    _runtime?.close();
    _runtime = candidate;
    persistentState.clear();
  }

  void stop() {
    _runtime?.close();
    _runtime = null;
    persistentState.clear();
  }
}

/// Owns running instances; deleting one never deletes a saved definition.
class PineIndicatorInstances {
  final Map<String, PineIndicatorDefinition> _definitions = {};
  final Map<String, PineIndicatorInstance> _running = {};

  void saveDefinition(PineIndicatorDefinition definition) {
    _definitions[definition.id] = definition;
  }

  bool get hasDefinitions => _definitions.isNotEmpty;
  PineIndicatorDefinition? definition(String id) => _definitions[id];
  PineIndicatorInstance? instance(String instanceId) => _running[instanceId];

  PineIndicatorInstance add({
    required String instanceId,
    required String definitionId,
    Map<String, double> inputs = const {},
    PineRuntimeLimits limits = const PineRuntimeLimits(),
  }) {
    if (_running.containsKey(instanceId)) {
      throw const PineRuntimeException(
          'duplicate_instance', 'Indicator instance ID must be unique');
    }
    final definition = _definitions[definitionId];
    if (definition == null) {
      throw const PineRuntimeException(
          'unknown_definition', 'Indicator definition was not saved');
    }
    final copy = PineIndicatorInstance(
        instanceId: instanceId, definition: definition,
        inputs: inputs, limits: limits);
    _running[instanceId] = copy;
    return copy;
  }

  void remove(String instanceId) {
    _running.remove(instanceId)?.stop();
  }

  void closeAll() {
    for (final instance in _running.values) {
      instance.stop();
    }
    _running.clear();
  }

  /// Changing saved source does not hot-swap already running compiled ASTs.
  /// Future UI can explicitly stop/recreate affected instances at a safe bar.
  bool deleteDefinition(String id) {
    if (!_definitions.containsKey(id)) return false;
    for (final instance in _running.values) {
      if (instance.definition.id == id) {
        throw const PineRuntimeException(
            'definition_active', 'Remove active instances before deleting');
      }
    }
    _definitions.remove(id);
    return true;
  }
}
