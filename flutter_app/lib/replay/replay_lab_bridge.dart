import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../data/market_api.dart';

/// O(1) read-only view of the completed bars through the frozen Replay
/// cursor. The chart passes an immutable provider-history list, so a later
/// history prepend or reload cannot mutate this captured source.
class FrozenMarketBarPrefix extends ListBase<MarketBar> {
  FrozenMarketBarPrefix(List<MarketBar> immutableSource, int through)
      : _source = immutableSource,
        _through = through {
    if (through < 0 || through > immutableSource.length) {
      throw RangeError.range(through, 0, immutableSource.length, 'through');
    }
  }

  final List<MarketBar> _source;
  final int _through;

  @override
  int get length => _through;

  @override
  set length(int value) =>
      throw UnsupportedError('Replay snapshot is read-only.');

  @override
  MarketBar operator [](int index) {
    if (index < 0 || index >= _through) throw RangeError.index(index, this);
    return _source[index];
  }

  @override
  void operator []=(int index, MarketBar value) =>
      throw UnsupportedError('Replay snapshot is read-only.');
}

/// A frozen, prefix-only view of a chart Replay session for the Lab.
/// Never contains candles after the chart's revealed cursor.
class ReplayLabSnapshot {
  const ReplayLabSnapshot({
    required this.symbol,
    required this.timeframe,
    required this.accountKey,
    required this.bars,
  });

  final String symbol;
  final String timeframe;
  final String accountKey;
  final List<MarketBar> bars;
}

/// Shares only an on-demand historical snapshot, not the chart's mutable state.
/// The chart stays mounted in the IndexedStack and owns all Replay controls.
class ReplayLabBridge extends ChangeNotifier {
  ReplayLabSnapshot? Function()? _capture;
  VoidCallback? _pause;

  void attach({
    required ReplayLabSnapshot? Function() capture,
    required VoidCallback pause,
  }) {
    _capture = capture;
    _pause = pause;
  }

  ReplayLabSnapshot? capture() => _capture?.call();

  void pausePlayback() => _pause?.call();

  /// Lets the Lab refresh its historical cursor when its bottom tab reopens.
  void labSelected() => notifyListeners();

  void detach() {
    _capture = null;
    _pause = null;
  }
}
