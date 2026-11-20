import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show VoidCallback, compute, kIsWeb;

import '../data/tradelab_data.dart';

/// Display-only causal Heikin-Ashi transform. Source OHLC remains untouched:
/// paper trades, Replay orders and broker archives always use real candles.
/// The output is index-aligned with the source and never inserts gaps/bars.
class ChartHeikinAshi {
  const ChartHeikinAshi._();

  static const minOffloadCandles = 5000;

  static bool shouldOffload(int count) =>
      !kIsWeb && count >= minOffloadCandles;

  static List<TradeCandle> build(List<TradeCandle> raw) {
    if (raw.isEmpty) return const <TradeCandle>[];
    final result = <TradeCandle>[];
    var previousOpen = (raw.first.open + raw.first.close) / 2;
    var previousClose =
        (raw.first.open + raw.first.high + raw.first.low + raw.first.close) / 4;
    for (final current in raw) {
      final close =
          (current.open + current.high + current.low + current.close) / 4;
      final open =
          result.isEmpty ? previousOpen : (previousOpen + previousClose) / 2;
      result.add(TradeCandle(
        open,
        math.max(current.high, math.max(open, close)),
        math.min(current.low, math.min(open, close)),
        close,
      ));
      previousOpen = open;
      previousClose = close;
    }
    return result;
  }

  static Future<List<TradeCandle>> buildAsync(List<TradeCandle> raw) async {
    if (!shouldOffload(raw.length)) return build(raw);
    return compute<List<TradeCandle>, List<TradeCandle>>(
      _buildHeikinAshiWorker,
      raw,
      debugLabel: 'tradelab-causal-heikin-ashi-history',
    );
  }
}

List<TradeCandle> _buildHeikinAshiWorker(List<TradeCandle> raw) =>
    ChartHeikinAshi.build(raw);

/// Keeps one prepared display view per exact raw-source list identity.
/// No stale derived candles may be displayed when the source account/symbol,
/// historical prefix, timeframe, or Replay source list changes.
///
/// A large source is resolved asynchronously and returns null until ready.
/// The caller shows a loading state, never the old account's HA candles nor
/// ordinary raw OHLC mislabeled as Heikin-Ashi.
class ChartHeikinAshiCache {
  ChartHeikinAshiCache({
    Future<List<TradeCandle>> Function(List<TradeCandle>)? buildLarge,
  }) : _buildLarge = buildLarge ?? ChartHeikinAshi.buildAsync;

  final Future<List<TradeCandle>> Function(List<TradeCandle>) _buildLarge;
  List<TradeCandle>? _readySource;
  List<TradeCandle>? _readyCandles;
  List<TradeCandle>? _pendingSource;
  List<TradeCandle>? _failedSource;
  int _revision = 0;
  bool _disposed = false;

  bool isPendingFor(List<TradeCandle> source) =>
      !_disposed && identical(_pendingSource, source);

  List<TradeCandle>? resolve(
    List<TradeCandle> source, {
    required VoidCallback onReady,
    VoidCallback? onError,
  }) {
    if (_disposed) return null;
    if (identical(_readySource, source)) return _readyCandles;
    if (!ChartHeikinAshi.shouldOffload(source.length)) {
      // Small histories are cheap and do not need a loading frame.
      final built = ChartHeikinAshi.build(source);
      _revision++;
      _pendingSource = null;
      _readySource = source;
      _readyCandles = built;
      _failedSource = null;
      return built;
    }
    if (!identical(_pendingSource, source) &&
        !identical(_failedSource, source)) {
      final revision = ++_revision;
      _pendingSource = source;
      unawaited(_resolveLarge(source, revision, onReady, onError));
    }
    return null;
  }

  Future<void> _resolveLarge(
    List<TradeCandle> source,
    int revision,
    VoidCallback onReady,
    VoidCallback? onError,
  ) async {
    try {
      final built = await _buildLarge(source);
      if (_disposed || revision != _revision ||
          !identical(_pendingSource, source)) return;
      _readySource = source;
      _readyCandles = built;
      _pendingSource = null;
      _failedSource = null;
      onReady();
    } catch (_) {
      if (_disposed || revision != _revision ||
          !identical(_pendingSource, source)) return;
      _pendingSource = null;
      _failedSource = source;
      onError?.call();
    }
  }

  void dispose() {
    _disposed = true;
    _revision++;
    _pendingSource = null;
    _readySource = null;
    _readyCandles = null;
    _failedSource = null;
  }
}
