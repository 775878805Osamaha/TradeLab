import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../chart/chart_annotations.dart';
import '../chart/chart_short_position.dart';
import '../chart/chart_price_rectangle.dart';
import '../chart/chart_type_sheet.dart';
import '../chart/chart_viewport.dart';
import '../chart/candle_prefix.dart';
import '../data/range_bar_timeline.dart';
import '../data/range_tick_rollforward.dart';
import '../data/range_tick_store.dart';
import '../data/tradelab_data.dart';
import '../data/market_api.dart';
import '../data/ctrader_candle_stitcher.dart';
import '../data/market_controller.dart';
import '../paper/paper_journal_controller.dart';
import '../paper/paper_ledger.dart';
import '../paper/paper_order_sheet.dart';
import '../paper/paper_trade_service.dart';
import '../theme/tradelab_theme.dart';
import '../widgets/trade_components.dart';

enum ChartMode {
  candles,
  heikinAshi,
  range;

  // Time candles and Heikin Ashi use the same source and timestamps.
  // Range bars use BID ticks, different indices and a separate history.
  bool requiresHistoryReload(ChartMode next) =>
      (this == ChartMode.range) != (next == ChartMode.range);
}

typedef _DrawingSnapshot = (List<double>, List<ChartPattern>,
    List<ChartShortPosition>, List<ChartPriceRectangle>);

class ChartScreen extends StatefulWidget {
  const ChartScreen({required this.controller, this.journal, super.key});
  final MarketController controller;
  final PaperJournalController? journal;

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen>
    with SingleTickerProviderStateMixin {
  // Session-only BID tick cache: switching Range size rebuilds locally.
  // Scoped by account and symbol; not a substitute for persistent history.
  final _rangeBidCache = <String, List<double>>{};
  final _rangePointCache = <String, double>{};
  final _rangeBidCachedAt = <String, DateTime>{};
  List<MarketBar> _actualBars = [];
  List<TradeCandle> _actualCandles = [];
  List<int> _actualTimestamps = [];
  List<TradeCandle> _actualRange = [];
  // Ordered provider ticks backing Range mode. Keep their timestamps so older
  // pages can be requested without using a guessed time boundary.
  List<MarketTick> _rangeHistoryTicks = [];
  List<int> _rangeBarEndTickIndices = [];
  List<int> _rangeBarTimestamps = [];
  int? _rangeOlderCursorMs;
  int _loadRevision = 0;
  bool _loading = false;
  bool _olderLoading = false;
  bool _historyExhausted = false;
  int? _olderCursorMs;
  String? _olderLoadError;
  String? _loadError;
  List<TradeCandle>? _heikinSource;
  List<TradeCandle>? _heikinCache;
  bool _linkedBefore = false;
  String? _accountBefore;
  String _symbol = 'XAUUSD';
  String _timeframe = '15m';
  ChartMode _mode = ChartMode.candles;
  int _rangeTicks = 1000;
  bool _replay = false;
  bool _drawing = false;
  ChartDrawingTool _drawingTool = ChartDrawingTool.horizontal;
  bool _placingShort = false;
  bool _placingRectangle = false;
  ChartAnchor? _rectangleFirstCorner;
  final List<ChartPriceRectangle> _rectangles = [];
  List<ChartPriceRectangle> _analysisRectangles = [];
  int? _selectedRectangle;
  bool _draggingRectangle = false;
  PriceRectangleHandle? _rectangleDragHandle;
  ChartPriceRectangle? _rectangleAtDragStart;
  ChartAnchor? _shortEntryAnchor;
  double? _shortStopPrice;
  final List<ChartShortPosition> _shortPositions = [];
  List<ChartShortPosition> _analysisShortPositions = [];
  int? _selectedShort;
  ShortPositionHandle? _draggingShortHandle;
  ChartShortPosition? _shortAtDragStart;
  ChartMagnetMode _magnetMode = ChartMagnetMode.off;
  bool _showIndicators = false;
  bool _showShortLabels = true;
  int _visibleThrough = 60;
  ChartViewport _viewport = const ChartViewport();
  ChartViewport _gestureStart = const ChartViewport();
  late final AnimationController _momentum;
  double _previousMomentumX = 0;
  double _momentumPlotWidth = 1;
  bool _gestureHadMultiTouch = false;
  double _gestureFocalX = 0;
  Offset? _crosshair;
  Timer? _replayTimer;
  Timer? _closedCandleTimer;
  bool _refreshingClosedCandles = false;
  bool _playing = false;
  final List<double> _levels = [];
  final List<ChartPattern> _patterns = [];
  final List<_DrawingSnapshot> _lineUndo = [];
  final List<_DrawingSnapshot> _lineRedo = [];
  List<double> _analysisLevels = [];
  List<ChartPattern> _analysisPatterns = [];
  ChartAnchor? _pendingAnchor;
  int? _selectedLine;
  int? _selectedPattern;
  bool _draggingLine = false;
  bool _draggingPattern = false;
  ChartPattern? _patternAtDragStart;
  ChartAnchorEndpoint? _draggedEndpoint;
  double _gestureFocalY = 0;

  TradeSymbol get _selectedSymbol => tradeSymbols.firstWhere((s) => s.code == _symbol);
  bool get _liveRequested => _selectedSymbol.source == TradeSource.binance ||
      widget.controller.ctraderConnected;
  bool get _rangeSourceSupported => _selectedSymbol.source == TradeSource.ctrader;

  CTraderAccount? get _selectedBrokerAccount {
    final accountId = widget.controller.accountId;
    if (accountId == null) return null;
    for (final account in widget.controller.accounts) {
      if (account.id == accountId) return account;
    }
    return null;
  }

  String _utcMinuteLabel(int timestampMs) {
    final date = DateTime.fromMillisecondsSinceEpoch(
        timestampMs, isUtc: true);
    return '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')} UTC';
  }

  /// A read-only OAuth session is NOT proof the market feed is current.
  /// Never display a green "real data" badge for a historical M1 chart
  /// that stopped advancing hours ago.
  bool get _ctraderTimeCandlesStale {
    if (_selectedSymbol.source != TradeSource.ctrader ||
        _mode == ChartMode.range || _actualTimestamps.isEmpty) return false;
    final last = _actualTimestamps.last;
    final interval = switch (_timeframe) {
      '1m' => 1, '2m' => 2, '3m' => 3, '5m' => 5,
      '15m' => 15, '30m' => 30, '1h' => 60,
      '4h' => 240, '1D' => 1440, '1W' => 10080,
      '1M' => 43200, _ => 1,
    };
    final lag = DateTime.now().toUtc().millisecondsSinceEpoch - last;
    return lag > math.max(interval * 3, 10) * 60000;
  }

  String get _marketEvidenceLabel {
    if (!_liveRequested) return 'اربط حساب cTrader لعرض شموع الذهب والفوركس الحقيقية';
    if (_loading) return 'جار تحميل الأسعار من المصدر';
    if (_loadError != null) return 'تعذر التحقق من مصدر الأسعار';
    if (_selectedSymbol.source == TradeSource.ctrader) {
      final account = _selectedBrokerAccount;
      final broker = account?.broker.isNotEmpty == true
          ? account!.broker : 'الوسيط المرتبط';
      final mode = account?.isLive == true ? 'حقيقي' : 'تجريبي';
      if (_mode == ChartMode.range && _rangeHistoryTicks.isNotEmpty) {
        return 'BID cTrader · $broker ($mode) · آخر تيك '
            '${_utcMinuteLabel(_rangeHistoryTicks.last.timestamp)}';
      }
      if (_actualTimestamps.isNotEmpty) {
        return 'شموع cTrader · $broker ($mode) · آخر شمعة '
            '${_utcMinuteLabel(_actualTimestamps.last)}'
            '${_ctraderTimeCandlesStale ? ' · بيانات متأخرة' : ''}';
      }
      return 'لم تصل شموع موثقة من cTrader لهذا الرمز';
    }
    return 'شموع Binance · آخر بيانات مصدر موثق';
  }
  int get _totalBars {
    if (!_liveRequested) return 0;
    return _mode == ChartMode.range ? _actualRange.length : _actualBars.length;
  }

  @override
  void initState() {
    super.initState();
    _momentum = AnimationController.unbounded(vsync: this)
      ..addListener(_tickMomentum);
    _linkedBefore = widget.controller.ctraderConnected;
    _accountBefore = widget.controller.accountId;
    widget.controller.addListener(_onMarketUpdate);
    // Poll only broker-closed candles. Never update Replay or request
    // synthetic OHLC from non-cTrader sources.
    _closedCandleTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_refreshClosedCTraderCandles()),
    );
    // Binance does not require a cTrader session. Load its chart immediately
    // when selected, even on a device that has never linked a broker.
    if (_liveRequested) Future.microtask(_loadRealHistory);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _momentum.stop();
  }

  void _tickMomentum() {
    if (!mounted || _loading) {
      _momentum.stop();
      return;
    }
    final deltaX = _momentum.value - _previousMomentumX;
    _previousMomentumX = _momentum.value;
    if (deltaX.abs() < 0.000001) return;
    final count = _displayCandles.length;
    if (count < 2) {
      _momentum.stop();
      return;
    }
    final next = _viewport.pan(
        deltaX: deltaX,
        plotWidth: _momentumPlotWidth,
        candleCount: count);
    if (next == _viewport) {
      // The chart reached its historical or future-whitespace bound.
      _momentum.stop();
      return;
    }
    setState(() => _viewport = next);
    _prefetchOlderAtEdge(_momentumPlotWidth, count);
  }

  void _startMomentum(double horizontalVelocity, double plotWidth) {
    _momentum.stop();
    _previousMomentumX = 0;
    _momentumPlotWidth = plotWidth;
    // Pixels/second, signed like the finger. The friction simulation is
    // cancelable by the next gesture; price data never changes with motion.
    _momentum.animateWith(FrictionSimulation(
        0.08, 0, horizontalVelocity.clamp(-5000.0, 5000.0).toDouble()));
  }

  void _prefetchOlderAtEdge(double plotWidth, int count) {
    if (!_liveRequested || _loading || _olderLoading || _historyExhausted ||
        _olderLoadError != null || count <= 0 ||
        _viewport.scrollBars <= count - plotWidth / _viewport.barWidth - 25) {
      return;
    }
    if (_mode == ChartMode.range) {
      if (_rangeHistoryTicks.isNotEmpty) {
        unawaited(_loadOlderRangeHistory());
      }
    } else if (_actualBars.isNotEmpty) {
      unawaited(_loadOlderHistory());
    }
  }

  void _onMarketUpdate() {
    final linked = widget.controller.ctraderConnected;
    final changedAccount = _accountBefore != widget.controller.accountId;
    if (_linkedBefore != linked || changedAccount) {
      _momentum.stop();
      _rangeBidCache.clear();
      _rangeBidCachedAt.clear();
      _rangePointCache.clear();
      _linkedBefore = linked;
      _accountBefore = widget.controller.accountId;
      // Never carry another broker account's drawings into this account.
      _resetDrawingObjects();
      if (linked && _selectedSymbol.source == TradeSource.ctrader) {
        _loadRealHistory();
      }
      if (!linked && _selectedSymbol.source == TradeSource.ctrader) {
        _loadRevision++;
        _stopPlayback();
        _replay = false;
        _actualBars = [];
        _actualCandles = [];
        _actualTimestamps = [];
        _actualRange = [];
        _rangeHistoryTicks = [];
        _rangeBarEndTickIndices = [];
        _rangeBarTimestamps = [];
        _rangeOlderCursorMs = null;
        _olderCursorMs = null;
        _historyExhausted = false;
        _olderLoading = false;
        _olderLoadError = null;
        _loadError = null;
        _loading = false;
        if (mounted) setState(() {});
      }
    }
  }

  Future<void> _loadRealHistory() async {
    _momentum.stop();
    final revision = ++_loadRevision;
    if (!mounted) return;
    setState(() {
      _stopPlayback();
      if (_replay) {
        _levels..clear()..addAll(_analysisLevels);
        _patterns..clear()..addAll(_analysisPatterns);
        _shortPositions..clear()..addAll(_analysisShortPositions);
        _rectangles..clear()..addAll(_analysisRectangles);
      }
      _replay = false;
      _loading = true;
      // Invalidate the previous history request's UI state. Its finally block
      // intentionally ignores stale revisions, so reset the spinner here.
      _olderLoading = false;
      _loadError = null;
      _historyExhausted = false;
      _olderCursorMs = null;
      _olderLoadError = null;
      _actualBars = [];
      _actualCandles = [];
      _actualTimestamps = [];
      _actualRange = [];
      _rangeHistoryTicks = [];
      _rangeBarEndTickIndices = [];
      _rangeBarTimestamps = [];
      _rangeOlderCursorMs = null;
      _patterns.clear();
      _analysisPatterns = [];
      _analysisLevels = [];
      _pendingAnchor = null;
      _selectedPattern = null;
    });
    try {
      if (_mode == ChartMode.range) {
        if (!_rangeSourceSupported) {
          throw const MarketDataException('شموع المدى الحقيقية متاحة حاليًا لرموز cTrader فقط؛ لا تتوفر تيكات Binance لهذا الوضع.');
        }
        final account = widget.controller.accountId!;
        final symbol = _selectedSymbol;
        final cacheKey = '$account:${symbol.code}';
        // Reuse only a recent *complete* timestamped provider window. The
        // v3 price-only snapshot is not sufficient for historical paging.
        // A verified six-day window may be older than the short quote TTL.
        // Keep its complete historical coverage; request only uncovered
        // milliseconds since its end instead of re-fetching all six days.
        final windowEnd = DateTime.now().toUtc().millisecondsSinceEpoch;
        final windowStart = windowEnd -
            RangeTickStore.verifiedWindowDuration.inMilliseconds;
        VerifiedBidWindow? restored;
        try {
          restored = await RangeTickStore.readLatestVerifiedWindowWithCoverage(
            account, symbol.code, maxAge: const Duration(days: 6));
        } catch (_) {
          // A damaged cache never substitutes estimated ticks for cTrader.
          restored = null;
        }
        if (revision != _loadRevision || !mounted) return;

        List<MarketTick>? ticks;
        int? coveredFromMs;
        if (restored != null && restored.ticks.isNotEmpty &&
            restored.toMs >= windowStart) {
          if (windowEnd - restored.toMs <=
              const Duration(minutes: 2).inMilliseconds) {
            // No extra network traffic for the same fresh broker snapshot.
            ticks = restored.ticks;
            coveredFromMs = restored.fromMs;
          } else {
            // The old and new six-day windows overlap. Fetch precisely the
            // missing inclusive suffix; this avoids duplicate same-ms ticks.
            final suffix = await widget.controller.rangeTicksBetween(
              symbol,
              fromMs: restored.toMs + 1,
              toMs: windowEnd,
            );
            if (revision != _loadRevision || !mounted) return;
            ticks = RangeTickRollforward.merge(
              cached: restored,
              newTicks: suffix,
              newFromMs: windowStart,
              newToMs: windowEnd,
            );
            coveredFromMs = windowStart;
            // Persist the new complete window after the prices are available.
            unawaited(RangeTickStore.archiveVerifiedWindow(
              account, symbol.code, ticks,
              fromMs: windowStart, toMs: windowEnd,
            ).then<void>((_) {}, onError: (Object _, StackTrace __) {}));
          }
        }

        if (ticks == null || ticks.isEmpty) {
          // Missing, expired or empty saved coverage: fall back to a full,
          // verified broker request rather than treating holes as real ticks.
          ticks = await widget.controller.rangeTicks(symbol,
              before: DateTime.fromMillisecondsSinceEpoch(
                  windowEnd, isUtc: true));
          if (revision != _loadRevision || !mounted) return;
          if (ticks.isEmpty) {
            throw const MarketDataException(
                'لم يُرجع cTrader تيكات ضمن الفترة المطلوبة.');
          }
          coveredFromMs = windowStart;
          unawaited(RangeTickStore.archiveVerifiedWindow(
            account, symbol.code, ticks,
            fromMs: windowStart, toMs: windowEnd,
          ).then<void>((_) {}, onError: (Object _, StackTrace __) {}));
        }
        _rangeHistoryTicks = ticks;
        _rangeOlderCursorMs = coveredFromMs! - 1;
        var point = _rangePointCache[cacheKey];
        if (point == null) {
          point = await widget.controller.pointSize(_selectedSymbol);
          if (revision != _loadRevision || !mounted) return;
          if (!point.isFinite || point <= 0) {
            throw const MarketDataException('دقة تسعير الرمز غير صالحة لإنشاء شموع المدى.');
          }
          _rangePointCache[cacheKey] = point;
        }
        if (revision != _loadRevision || !mounted) return;
        final timeline = await RangeBarTimeline.buildAsync(ticks, _rangeTicks * point);
        if (revision != _loadRevision || !mounted) return;
        _actualRange = timeline.bars;
        _rangeBarEndTickIndices = timeline.endTickIndices;
        _rangeBarTimestamps = timeline.endTimestamps;
      } else {
        final bars = await widget.controller.history(_selectedSymbol, _timeframe);
        if (revision != _loadRevision || !mounted) return;
        // MarketApi already validated strictly ascending broker timestamps
        // and OHLC. Do not sort or deduplicate again in the UI: doing so
        // would conceal a source/protocol defect behind plausible candles.
        _actualBars = List<MarketBar>.unmodifiable(bars);
        _actualCandles = bars.map((bar) => bar.candle).toList(growable: false);
        _actualTimestamps =
            bars.map((bar) => bar.timestamp).toList(growable: false);
        if (bars.isNotEmpty) _olderCursorMs = bars.first.timestamp;
      }
      if (revision == _loadRevision && _totalBars == 0) {
        _loadError = 'لم يُرجع المصدر شموعًا لهذه الفترة. جرّب تحديث البيانات أو اختيار إطار آخر.';
      }
    } on MarketDataException catch (e) {
      if (revision == _loadRevision) _loadError = e.message;
    } catch (_) {
      if (revision == _loadRevision) _loadError = 'تعذر تحميل بيانات السوق. أعد المحاولة.';
    } finally {
      if (revision == _loadRevision && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshClosedCTraderCandles() async {
    if (!mounted || _refreshingClosedCandles || _loading || _olderLoading ||
        _replay || _draggingLine || _draggingPattern ||
        !_liveRequested || _loadError != null ||
        _selectedSymbol.source != TradeSource.ctrader ||
        _mode == ChartMode.range || _actualBars.isEmpty) return;
    final revision = _loadRevision;
    final symbol = _selectedSymbol;
    final timeframe = _timeframe;
    final lastTimestamp = _actualBars.last.timestamp;
    _refreshingClosedCandles = true;
    try {
      final recent = await widget.controller.closedCandlesSince(
          symbol, timeframe, lastTimestamp);
      if (!mounted || revision != _loadRevision || _replay ||
          _selectedSymbol.code != symbol.code || _timeframe != timeframe) {
        return;
      }
      final combined = CTraderCandleStitcher.append(_actualBars, recent);
      final appended = combined.length - _actualBars.length;
      if (appended == 0) {
        // Update the freshness label even when the broker has no new candle.
        setState(() {});
        return;
      }
      setState(() {
        _actualBars = combined;
        _actualCandles =
            combined.map((bar) => bar.candle).toList(growable: false);
        _actualTimestamps =
            combined.map((bar) => bar.timestamp).toList(growable: false);
        // Keep the visible candle anchored during historical inspection or
        // deliberate right-side whitespace; follow new bars at the live edge.
        _viewport = _viewport.afterAppending(appended);
      });
    } on MarketDataException catch (error) {
      if (mounted && revision == _loadRevision) {
        setState(() => _loadError = error.message);
      }
    } catch (_) {
      if (mounted && revision == _loadRevision) {
        setState(() => _loadError =
            'فشل تحديث شموع cTrader المغلقة. اضغط تحديث لإعادة المحاولة.');
      }
    } finally {
      _refreshingClosedCandles = false;
    }
  }

  Future<void> _loadOlderRangeHistory() async {
    if (_olderLoading || _loading || _historyExhausted ||
        !_liveRequested || _mode != ChartMode.range ||
        _rangeHistoryTicks.isEmpty ||
        widget.controller.accountId == null) return;
    final revision = _loadRevision;
    final account = widget.controller.accountId!;
    final symbol = _selectedSymbol;
    final earliest = _rangeHistoryTicks.first.timestamp;
    setState(() {
      _olderLoading = true;
      _olderLoadError = null;
    });
    try {
      // Cover the exact six-day interval using one or more independently
      // verified local windows, even if they were saved with different
      // boundaries on a previous app session. Partial archives are unsafe.
      final endMs = _rangeOlderCursorMs ?? earliest - 1;
      final fromMs = endMs -
          RangeTickStore.verifiedWindowDuration.inMilliseconds;
      if (fromMs < 0) {
        _historyExhausted = true;
        return;
      }
      List<MarketTick>? older;
      try {
        older = await RangeTickStore.readCoveredInterval(
          account, symbol.code, fromMs: fromMs, toMs: endMs);
      } catch (_) {
        // A damaged local cache can be recovered from cTrader.
        older = null;
      }
      if (!mounted || revision != _loadRevision) return;
      if (older == null) {
        older = await widget.controller.rangeTicks(
          symbol,
          before: DateTime.fromMillisecondsSinceEpoch(endMs, isUtc: true),
        );
        if (!mounted || revision != _loadRevision) return;
        // Save exact provider coverage, including verified empty windows,
        // without blocking chart rendering.
        unawaited(RangeTickStore.archiveVerifiedWindow(
          account, symbol.code, older, fromMs: fromMs, toMs: endMs,
        ).then<void>((_) {}, onError: (Object _, StackTrace __) {}));
      }
      // The cursor is exclusive, even when several ticks share a ms.
      if (older.any((tick) => tick.timestamp >= earliest)) {
        throw const MarketDataException(
          'تيكات الصفحة الأقدم تتداخل مع حد الشارت؛ تم إيقاف الدمج.');
      }
      if (older.isEmpty) {
        _rangeOlderCursorMs = fromMs - 1;
        _olderLoadError =
            'لا توجد تيكات في الأيام الستة السابقة. اضغط «أقدم» لمتابعة البحث.';
        return;
      }
      final prefix = older;
      final combined = [...prefix, ..._rangeHistoryTicks];
      final point = _rangePointCache['$account:${symbol.code}'];
      if (point == null || !point.isFinite || point <= 0) {
        throw StateError('Missing verified symbol point size');
      }
      // Remember the actual source tick that the Replay cutoff had reached.
      // This avoids revealing future ticks after the Range bars are rebuilt
      // with a different start price and thus different historical indices.
      final replayCutoffTick = _replay &&
              _visibleThrough > 0 &&
              _visibleThrough <= _rangeBarEndTickIndices.length
          ? _rangeBarEndTickIndices[_visibleThrough - 1]
          : null;
      final timeline = await RangeBarTimeline.buildAsync(combined, _rangeTicks * point);
      if (!mounted || revision != _loadRevision) return;
      // Range bars are not time candles: after prepending BID events, a bar's
      // index can move non-uniformly. Rebase each drawing endpoint to its
      // original market event while keeping its real price unchanged.
      int? rebaseAnchor(ChartAnchor anchor) => timeline.rebaseOldBarIndex(
        oldEndTickIndices: _rangeBarEndTickIndices,
        oldIndex: anchor.index,
        prependedTicks: prefix.length,
        anchorPrice: anchor.price,
      );
      ChartPattern? rebasePattern(ChartPattern pattern) {
        final first = rebaseAnchor(pattern.start);
        final last = rebaseAnchor(pattern.end);
        return first == null || last == null
            ? null : pattern.reanchored(first, last);
      }
      final rebasedPatterns = _patterns
          .map(rebasePattern).whereType<ChartPattern>().toList();
      final rebasedAnalysis = _analysisPatterns
          .map(rebasePattern).whereType<ChartPattern>().toList();
      ChartShortPosition? rebaseShort(ChartShortPosition drawing) {
        final first = rebaseAnchor(ChartAnchor(drawing.startIndex, drawing.entry));
        final last = rebaseAnchor(ChartAnchor(drawing.endIndex, drawing.entry));
        return first == null || last == null
            ? null : drawing.reanchored(first, last);
      }
      final rebasedShorts = _shortPositions
          .map(rebaseShort).whereType<ChartShortPosition>().toList();
      final rebasedAnalysisShorts = _analysisShortPositions
          .map(rebaseShort).whereType<ChartShortPosition>().toList();
      ChartPriceRectangle? rebaseRectangle(ChartPriceRectangle drawing) {
        final first = rebaseAnchor(ChartAnchor(drawing.startIndex, drawing.upper));
        final last = rebaseAnchor(ChartAnchor(drawing.endIndex, drawing.upper));
        if (first == null || last == null || first == last) return null;
        return drawing.reanchored(first, last);
      }
      final rebasedRectangles = _rectangles
          .map(rebaseRectangle).whereType<ChartPriceRectangle>().toList();
      final rebasedAnalysisRectangles = _analysisRectangles
          .map(rebaseRectangle).whereType<ChartPriceRectangle>().toList();
      final pendingIndex = _pendingAnchor == null
          ? null : rebaseAnchor(_pendingAnchor!);
      final shortEntryIndex = _shortEntryAnchor == null
          ? null : rebaseAnchor(_shortEntryAnchor!);
      final rectangleFirstIndex = _rectangleFirstCorner == null
          ? null : rebaseAnchor(_rectangleFirstCorner!);
      final previousDisplayCount = _replay ? _visibleThrough : _actualRange.length;
      final oldViewport = _viewport;
      // Preserve the market event visible near the right edge rather than
      // preserving a Range bar index (which changes after historical rebuild).
      var oldAnchorIndex = -1;
      if (oldViewport.scrollBars > 0 && previousDisplayCount > 0 &&
          _rangeBarEndTickIndices.length >= previousDisplayCount) {
        oldAnchorIndex = (previousDisplayCount - 1 - oldViewport.scrollBars)
            .round().clamp(0, previousDisplayCount - 1);
      }
      final anchorTickIndex = oldAnchorIndex < 0
          ? null : prefix.length + _rangeBarEndTickIndices[oldAnchorIndex];
      // A different Range origin can move the first new close beyond the
      // Replay cutoff. Never force at least one candle: that would reveal
      // a bar formed using BID ticks from the still-hidden future.
      if (_replay && replayCutoffTick == null) {
        _olderLoadError =
            'تعذر تثبيت موضع Replay على تيك معروف. أعد المحاولة خارج Replay.';
        return;
      }
      final safeReplayBars = replayCutoffTick == null
          ? null
          : timeline.visibleBarsThroughTick(prefix.length + replayCutoffTick);
      if (_replay && (safeReplayBars == null || safeReplayBars == 0)) {
        _olderLoadError =
            'يغيّر التاريخ الأقدم بداية شموع المدى قبل موضع Replay؛ '
            'لن نعرض شمعة تحتاج تيكات مستقبلية. أوقف Replay لتحميلها.';
        return;
      }
      setState(() {
        final nextDisplayCount = _replay
            ? safeReplayBars! : timeline.bars.length;
        if (anchorTickIndex != null && nextDisplayCount > 0) {
          final newAnchorIndex = (timeline.visibleBarsThroughTick(
                  anchorTickIndex) - 1).clamp(0, nextDisplayCount - 1);
          _viewport = oldViewport.remapHistoricalAnchor(
            oldCount: previousDisplayCount,
            oldIndex: oldAnchorIndex,
            newCount: nextDisplayCount,
            newIndex: newAnchorIndex,
          );
        }
        _rangeHistoryTicks = combined;
        _rangeOlderCursorMs = fromMs - 1;
        _actualRange = timeline.bars;
        _rangeBarEndTickIndices = timeline.endTickIndices;
        _rangeBarTimestamps = timeline.endTimestamps;
        _patterns..clear()..addAll(rebasedPatterns);
        _analysisPatterns = rebasedAnalysis;
        _shortPositions..clear()..addAll(rebasedShorts);
        _analysisShortPositions = rebasedAnalysisShorts;
        _rectangles..clear()..addAll(rebasedRectangles);
        _analysisRectangles = rebasedAnalysisRectangles;
        _selectedRectangle = null;
        _selectedShort = null;
        _pendingAnchor = pendingIndex == null ? null
            : ChartAnchor(pendingIndex, _pendingAnchor!.price);
        if (_shortEntryAnchor != null) {
          _shortEntryAnchor = shortEntryIndex == null ? null
              : ChartAnchor(shortEntryIndex, _shortEntryAnchor!.price);
          if (_shortEntryAnchor == null) _shortStopPrice = null;
        }
        if (_rectangleFirstCorner != null) {
          _rectangleFirstCorner = rectangleFirstIndex == null ? null
              : ChartAnchor(rectangleFirstIndex, _rectangleFirstCorner!.price);
        }
        _selectedPattern = null;
        _lineUndo.clear(); // Undo entries use the previous Range bar indices.
        _lineRedo.clear();
        if (_replay && replayCutoffTick != null) {
          _stopPlayback();
          _visibleThrough = safeReplayBars!;
        }
      });
    } on MarketDataException catch (error) {
      if (mounted && revision == _loadRevision) _olderLoadError = error.message;
    } catch (_) {
      if (mounted && revision == _loadRevision) {
        _olderLoadError = 'تعذر تحميل تيكات المدى الأقدم. أعد المحاولة.';
      }
    } finally {
      if (mounted && revision == _loadRevision) {
        setState(() => _olderLoading = false);
      }
    }
  }

  Future<void> _loadOlderHistory({bool manual = false}) async {
    if (_olderLoading || _loading || _historyExhausted || !_liveRequested ||
        (!manual && _olderLoadError != null) ||
        _mode == ChartMode.range || _actualBars.isEmpty) return;
    final revision = _loadRevision;
    setState(() {
      _olderLoading = true;
      _olderLoadError = null;
    });
    try {
      final cursor = _olderCursorMs ?? _actualBars.first.timestamp;
      if (cursor < 1) {
        if (mounted) setState(() => _historyExhausted = true);
        return;
      }
      // The cursor is exclusive; never re-request the same broker minute.
      final before = DateTime.fromMillisecondsSinceEpoch(
          cursor - 1, isUtc: true);
      final older = await widget.controller.history(
          _selectedSymbol, _timeframe, before: before);
      if (revision != _loadRevision || !mounted) return;
      final earliest = _actualBars.first.timestamp;
      // Providers can return pages out of order or with duplicate timestamps.
      // Normalize before prepending so chart indices and Replay stay stable.
      final byTimestamp = <int, MarketBar>{};
      for (final bar in older) {
        if (bar.timestamp < earliest) byTimestamp[bar.timestamp] = bar;
      }
      final unique = byTimestamp.values.toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      if (unique.isEmpty) {
        if (_selectedSymbol.source == TradeSource.binance) {
          _historyExhausted = true;
        } else {
          // A quiet short-window M1 response is not the end of history.
          // Continue immediately before the exact window queried, not
          // 89 days earlier (which would silently skip archived candles).
          _olderCursorMs = cursor -
              MarketApi.ctraderCandleLookback(_timeframe).inMilliseconds;
          _olderLoadError =
              'لا توجد شموع في الفترة السابقة. اضغط «أقدم» للبحث قبلها.';
        }
      } else {
        _olderCursorMs = unique.first.timestamp;
        setState(() {
        _actualBars = [...unique, ..._actualBars];
        _actualCandles = _actualBars.map((bar) => bar.candle).toList(growable: false);
        _actualTimestamps = _actualBars.map((bar) => bar.timestamp).toList(growable: false);
        for (var index = 0; index < _patterns.length; index++) {
          _patterns[index] = _patterns[index].shifted(unique.length);
        }
        for (var index = 0; index < _shortPositions.length; index++) {
          _shortPositions[index] = _shortPositions[index].shifted(unique.length);
        }
        for (var index = 0; index < _rectangles.length; index++) {
          _rectangles[index] = _rectangles[index].shifted(unique.length);
        }
        if (_replay) {
          _analysisPatterns = _analysisPatterns
              .map((drawing) => drawing.shifted(unique.length))
              .toList(growable: false);
          _analysisShortPositions = _analysisShortPositions
              .map((drawing) => drawing.shifted(unique.length))
              .toList(growable: false);
          _analysisRectangles = _analysisRectangles
              .map((drawing) => drawing.shifted(unique.length))
              .toList(growable: false);
        }
        if (_shortEntryAnchor != null) {
          _shortEntryAnchor = _shortEntryAnchor!.shifted(unique.length);
        }
        if (_rectangleFirstCorner != null) {
          _rectangleFirstCorner = _rectangleFirstCorner!.shifted(unique.length);
        }
        if (_pendingAnchor != null) {
          _pendingAnchor = _pendingAnchor!.shifted(unique.length);
        }
        // Undo snapshots contain bar indices from before historical prepend.
        // Keep current drawings but never replay an obsolete anchor snapshot.
        _lineUndo.clear();
        _lineRedo.clear();
        // The Replay cutoff must stay at the SAME historical candle when
        // older candles are prepended. Never reveal new future candles.
        if (_replay) _visibleThrough += unique.length;
        });
      }
    } catch (_) {
      if (revision == _loadRevision && mounted) {
        _olderLoadError = 'تعذّر تحميل الشموع الأقدم. يمكنك إعادة المحاولة.';
      }
    } finally {
      if (revision == _loadRevision && mounted) {
        setState(() => _olderLoading = false);
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onMarketUpdate);
    _loadRevision++;
    _replayTimer?.cancel();
    _closedCandleTimer?.cancel();
    _momentum.dispose();
    super.dispose();
  }

  void _stopPlayback() {
    _replayTimer?.cancel();
    _replayTimer = null;
    _playing = false;
  }

  void _toggleReplay() {
    _momentum.stop();
    if (_totalBars < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('حمّل شموع السوق أولًا لبدء Replay.')));
      return;
    }
    setState(() {
        _stopPlayback();
        if (!_replay) {
          // Drawings created after the Replay cutoff could expose future
          // information. Keep analysis objects separately until Replay ends.
          _analysisLevels = List<double>.of(_levels);
          _analysisPatterns = List<ChartPattern>.of(_patterns);
          _analysisShortPositions = List<ChartShortPosition>.of(_shortPositions);
          _analysisRectangles = List<ChartPriceRectangle>.of(_rectangles);
          _levels.clear();
          _patterns.clear();
          _shortPositions.clear();
          _rectangles.clear();
        } else {
          _levels..clear()..addAll(_analysisLevels);
          _patterns..clear()..addAll(_analysisPatterns);
          _shortPositions..clear()..addAll(_analysisShortPositions);
          _rectangles..clear()..addAll(_analysisRectangles);
        }
        _replay = !_replay;
        _visibleThrough = math.max(1, _totalBars ~/ 2);
        _viewport = const ChartViewport();
        _crosshair = null;
        _selectedLine = null;
        _selectedPattern = null;
        _selectedShort = null;
        _selectedRectangle = null;
        _placingShort = false;
        _placingRectangle = false;
        _rectangleFirstCorner = null;
        _shortEntryAnchor = null;
        _shortStopPrice = null;
        _pendingAnchor = null;
        _lineUndo.clear();
        _lineRedo.clear();
      });
  }

  void _togglePlay() {
    if (_playing) {
      setState(_stopPlayback);
      return;
    }
    setState(() => _playing = true);
    _replayTimer = Timer.periodic(const Duration(milliseconds: 650), (timer) {
      if (!mounted || !_replay || _visibleThrough >= _totalBars) {
        timer.cancel();
        if (mounted) setState(() => _playing = false);
        return;
      }
      setState(() => _visibleThrough++);
    });
  }

  void _notifyUnconnected() => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اربط حساب cTrader من شاشة الحساب أولًا لعرض شموع الذهب والفوركس الحقيقية.'),
        ),
      );

  void _openPaperOrder() {
    final journal = widget.journal;
    if (journal == null || journal.busy || journal.error != null || _replay) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('أغلق Replay وانتظر حتى يصبح الدفتر المحلي جاهزًا.')));
      return;
    }
    if (!LedgerEntry.usdQuotedSymbols.contains(_symbol)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('التداول التجريبي الحالي متاح للرموز المسعرة بالدولار فقط.')));
      return;
    }
    showModalBottomSheet<void>(context: context, showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => PaperOrderSheet(symbol: _selectedSymbol,
        service: PaperTradeService(
          quotes: LivePaperQuoteProvider(widget.controller), journal: journal)));
  }

  List<TradeCandle> get _displayCandles {
    // No synthetic or demo chart may be rendered before broker authorization.
    // Binance crypto candles are allowed independently of cTrader.
    if (!_liveRequested) return const [];
    if (_mode == ChartMode.range) {
      return _replay
          ? CandlePrefix(_actualRange, _visibleThrough) : _actualRange;
    }
    final source = _actualCandles;
    if (_mode != ChartMode.heikinAshi) {
      return _replay ? CandlePrefix(source, _visibleThrough) : source;
    }
    // A Heikin-Ashi candle depends only on past candles. Compute the full
    // causal sequence once per source, then reveal a prefix in Replay.
    if (!identical(source, _heikinSource)) {
      _heikinSource = source;
      _heikinCache = _buildHeikinAshi(source);
    }
    final smoothed = _heikinCache!;
    return _replay ? CandlePrefix(smoothed, _visibleThrough) : smoothed;
  }

  static List<TradeCandle> _buildHeikinAshi(List<TradeCandle> raw) {
    if (raw.isEmpty) return const [];
    final result = <TradeCandle>[];
    var previousOpen = (raw.first.open + raw.first.close) / 2;
    var previousClose = (raw.first.open + raw.first.high + raw.first.low + raw.first.close) / 4;
    for (final current in raw) {
      final close = (current.open + current.high + current.low + current.close) / 4;
      final open = result.isEmpty ? previousOpen : (previousOpen + previousClose) / 2;
      result.add(TradeCandle(open, math.max(current.high, math.max(open, close)),
          math.min(current.low, math.min(open, close)), close));
      previousOpen = open;
      previousClose = close;
    }
    return result;
  }

  Future<void> _showSymbolPicker() async {
    _momentum.stop();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const TradeSectionTitle('تغيير الرمز'),
            ...tradeSymbols.map((item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.code, textDirection: TextDirection.ltr,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(item.title),
                  trailing: item.code == _symbol
                      ? const Icon(Icons.check_circle, color: TradeColors.blue)
                      : const Icon(Icons.chevron_left),
                  onTap: () {
                    setState(() {
                      _stopPlayback();
                      _symbol = item.code;
                      _viewport = const ChartViewport();
                      _resetDrawingObjects();
                    });
                    Navigator.pop(sheetContext);
                    if (_liveRequested) _loadRealHistory();
                  },
                )),
          ]),
        ),
      ),
    );
  }

  Future<void> _showTimeframePicker() async {
    _momentum.stop();
    const frames = ['1m', '3m', '5m', '15m', '30m', '1h', '4h', '1D', '1W', '1M'];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const TradeSectionTitle('الإطار الزمني'),
            Wrap(spacing: 8, runSpacing: 8,
              children: frames.map((frame) => ChoiceChip(
                    label: Text(frame, textDirection: TextDirection.ltr),
                    selected: _timeframe == frame,
                    onSelected: (_) {
                      setState(() {
                        _timeframe = frame;
                        _viewport = const ChartViewport();
                        _resetDrawingObjects();
                      });
                      Navigator.pop(sheetContext);
                      if (_liveRequested && _mode != ChartMode.range) _loadRealHistory();
                    },
                  )).toList()),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }

  Future<void> _showChartTypePicker() async {
    _momentum.stop();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .13),
      builder: (sheetContext) => ChartTypeSheet(
        selected: switch (_mode) {
          ChartMode.candles => ChartKind.candles,
          ChartMode.heikinAshi => ChartKind.heikinAshi,
          ChartMode.range => ChartKind.range,
        },
        onUnavailable: (kind) => showDialog<void>(
          context: sheetContext,
          builder: (dialogContext) => AlertDialog(
            title: Text(kind.label, textDirection: TextDirection.rtl),
            content: const Text(
              'هذا النوع ظاهر في المرجع البصري، لكن محركه غير منفذ في TradeLab بعد. '
              'لن يتم عرضه على أنه شموع عادية أو بيانات سوق وهمية.',
              textDirection: TextDirection.rtl,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('حسنًا'),
              ),
            ],
          ),
        ),
        onSelect: (kind) async {
          final nextMode = switch (kind) {
            ChartKind.heikinAshi => ChartMode.heikinAshi,
            ChartKind.range => ChartMode.range,
            _ => ChartMode.candles,
          };
          final reload = _mode.requiresHistoryReload(nextMode);
          if (nextMode != _mode) {
            setState(() {
              _mode = nextMode;
              if (reload) {
                // Range has different bar identities; merely opening or
                // dismissing this sheet never resets zoom, Replay or cache.
                _viewport = const ChartViewport();
                _resetDrawingObjects();
              }
            });
          }
          Navigator.pop(sheetContext);
          if (nextMode == ChartMode.range) {
            // Preserve the established BID tick sizing and fetch sequence.
            await _showRangeSettings(reloadOnChange: !reload);
          }
          if (mounted && reload && _liveRequested) _loadRealHistory();
        },
      ),
    );
  }

  Future<void> _showRangeSettings({bool reloadOnChange = true}) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const TradeSectionTitle('إعدادات شموع المدى'),
            const Text('حجم المدى بالنقاط حسب دقة تسعير الرمز. الحساب الحقيقي يستخدم تيكات BID من cTrader فقط.'),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final size in const [100, 250, 500, 1000, 2000, 5000])
                ChoiceChip(
                  label: Text('$size'),
                  selected: _rangeTicks == size,
                  onSelected: (_) {
                    final changed = _rangeTicks != size;
                    if (changed) {
                      setState(() {
                        _rangeTicks = size;
                        _viewport = const ChartViewport();
                        _resetDrawingObjects();
                      });
                    }
                    Navigator.pop(sheetContext);
                    if (changed && reloadOnChange && _liveRequested) {
                      _loadRealHistory();
                    }
                  },
                ),
            ]),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }

  Future<void> _showDrawingTools() async {
    _momentum.stop();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, updateSheet) => SafeArea(
        child: SingleChildScrollView(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const TradeSectionTitle('أدوات الرسم'),
            const SizedBox(height: 6),
            const Align(alignment: AlignmentDirectional.centerStart,
                child: Text('مغناطيس الأسعار · تثبيت النقاط على O/H/L/C')),
            Wrap(spacing: 8, children: [
              for (final item in const <(ChartMagnetMode, String)>[
                (ChartMagnetMode.off, 'إيقاف'),
                (ChartMagnetMode.weak, 'ضعيف'),
                (ChartMagnetMode.strong, 'قوي'),
              ])
                ChoiceChip(
                  label: Text(item.$2),
                  selected: _magnetMode == item.$1,
                  onSelected: (_) {
                    setState(() => _magnetMode = item.$1);
                    updateSheet(() {});
                  },
                ),
            ]),
            for (final option in const <(ChartDrawingTool, String, IconData)>[
              (ChartDrawingTool.horizontal, 'خط أفقي', Icons.horizontal_rule),
              (ChartDrawingTool.trendLine, 'خط اتجاه · نقطتان', Icons.trending_up),
              (ChartDrawingTool.fibonacci, 'تصحيح فيبوناتشي · نقطتان', Icons.stacked_line_chart),
            ])
              ListTile(
                title: Text(option.$2),
                leading: Icon(option.$3),
                trailing: _drawing && _drawingTool == option.$1
                    ? const Icon(Icons.check_circle, color: TradeColors.blue)
                    : null,
                onTap: () {
                  setState(() {
                    _drawing = true;
                    _placingShort = false;
                    _placingRectangle = false;
                    _drawingTool = option.$1;
                    _pendingAnchor = null;
                    _selectedLine = null;
                    _selectedPattern = null;
                    _selectedShort = null;
                    _selectedRectangle = null;
                  });
                  Navigator.pop(sheetContext);
                },
              ),
            ListTile(
              key: const Key('short-position-tool'),
              title: const Text('مركز بيع · الدخول ثم الإيقاف ثم الهدف'),
              leading: const Icon(Icons.south_east),
              trailing: _placingShort
                  ? const Icon(Icons.check_circle, color: TradeColors.blue)
                  : null,
              onTap: () {
                setState(() {
                  _drawing = true;
                  _placingShort = true;
                  _placingRectangle = false;
                  _shortEntryAnchor = null;
                  _shortStopPrice = null;
                  _selectedShort = null;
                  _selectedRectangle = null;
                  _selectedLine = null;
                  _selectedPattern = null;
                  _pendingAnchor = null;
                });
                Navigator.pop(sheetContext);
              },
            ),
            ListTile(
              key: const Key('price-rectangle-tool'),
              title: const Text('مستطيل نطاق سعري · زاويتان'),
              leading: const Icon(Icons.crop_square_outlined),
              trailing: _placingRectangle
                  ? const Icon(Icons.check_circle, color: TradeColors.blue)
                  : null,
              onTap: () {
                _selectDrawingMode(rectangle: true);
                Navigator.pop(sheetContext);
              },
            ),
            ListTile(
              title: const Text('إنهاء الرسم والعودة إلى تحريك الشارت'),
              leading: const Icon(Icons.pan_tool_outlined),
              onTap: () {
                setState(() {
                  _drawing = false;
                  _placingShort = false;
                  _placingRectangle = false;
                  _pendingAnchor = null;
                  _rectangleFirstCorner = null;
                  _shortEntryAnchor = null;
                  _shortStopPrice = null;
                });
                Navigator.pop(sheetContext);
              },
            ),
          ]),
        ),
        ),
      ),
      ),
    );
  }

  Widget _iconAction({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool active = false,
  }) => IconButton(
        tooltip: label,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: onPressed,
        icon: Icon(icon, size: 22,
            color: active ? TradeColors.blue : Theme.of(context).colorScheme.onSurface),
      );

  void _zoomBy(double factor) {
    _momentum.stop();
    final width = math.max(80.0, MediaQuery.sizeOf(context).width - 61);
    final count = _displayCandles.length;
    setState(() => _viewport = _viewport.pinch(
          scale: factor,
          initialFocalX: width / 2,
          currentFocalX: width / 2,
          plotWidth: width,
          candleCount: count,
        ));
  }

  _DrawingSnapshot _snapshotDrawings() => (
    List<double>.of(_levels), List<ChartPattern>.of(_patterns),
    List<ChartShortPosition>.of(_shortPositions),
    List<ChartPriceRectangle>.of(_rectangles));

  void _restoreDrawings(_DrawingSnapshot snapshot) {
    _levels..clear()..addAll(snapshot.$1);
    _patterns..clear()..addAll(snapshot.$2);
    _shortPositions..clear()..addAll(snapshot.$3);
    _rectangles..clear()..addAll(snapshot.$4);
    _selectedLine = null;
    _selectedPattern = null;
    _selectedShort = null;
    _selectedRectangle = null;
    _pendingAnchor = null;
    _rectangleFirstCorner = null;
  }

  void _saveDrawingUndo() {
    _lineUndo.add(_snapshotDrawings());
    if (_lineUndo.length > 30) _lineUndo.removeAt(0);
    _lineRedo.clear();
  }

  void _undoDrawing() {
    if (_lineUndo.isEmpty) return;
    setState(() {
      _lineRedo.add(_snapshotDrawings());
      _restoreDrawings(_lineUndo.removeLast());
    });
  }

  void _redoDrawing() {
    if (_lineRedo.isEmpty) return;
    setState(() {
      _lineUndo.add(_snapshotDrawings());
      _restoreDrawings(_lineRedo.removeLast());
    });
  }

  void _resetDrawingObjects() {
    _levels.clear();
    _patterns.clear();
    _shortPositions.clear();
    _rectangles.clear();
    _analysisLevels = [];
    _analysisPatterns = [];
    _analysisShortPositions = [];
    _analysisRectangles = [];
    _lineUndo.clear();
    _lineRedo.clear();
    _pendingAnchor = null;
    _selectedLine = null;
    _selectedPattern = null;
    _selectedShort = null;
    _selectedRectangle = null;
    _placingShort = false;
    _shortEntryAnchor = null;
    _shortStopPrice = null;
    _placingRectangle = false;
    _rectangleFirstCorner = null;
  }

  ChartPriceScale _priceScale(List<TradeCandle> candles, double width, double height) =>
      ChartPriceScale.visible(candles, _viewport, width, math.max(1, height - 24));

  int? _hitLine(double y, ChartPriceScale scale) {
    for (var index = _levels.length - 1; index >= 0; index--) {
      if ((scale.y(_levels[index]) - y).abs() <= 18) return index;
    }
    return null;
  }

  int? _hitPattern(Offset position, ChartPriceScale scale,
      double width, int visibleCount) {
    for (var i = _patterns.length - 1; i >= 0; i--) {
      final pattern = _patterns[i];
      if (!pattern.visibleAt(visibleCount)) continue;
      final x1 = _viewport.chartX(index: pattern.start.index,
          candleCount: visibleCount, plotWidth: width);
      final x2 = _viewport.chartX(index: pattern.end.index,
          candleCount: visibleCount, plotWidth: width);
      final y1 = scale.y(pattern.start.price);
      final y2 = scale.y(pattern.end.price);
      if (pattern.tool == ChartDrawingTool.fibonacci) {
        final left = math.min(x1, x2) - 15;
        if (position.dx < left || position.dx > width) continue;
        if (ChartPattern.fibonacciRatios.any((ratio) =>
            (scale.y(pattern.fibonacciPrice(ratio)) - position.dy).abs() < 17)) {
          return i;
        }
      } else {
        final dx = x2 - x1;
        final dy = y2 - y1;
        final lengthSquared = dx * dx + dy * dy;
        final projection = lengthSquared == 0 ? 0.0 :
            ((position.dx - x1) * dx + (position.dy - y1) * dy) /
                lengthSquared;
        final t = projection.clamp(0.0, 1.0);
        final distance = math.sqrt(
          math.pow(position.dx - (x1 + dx * t), 2) +
          math.pow(position.dy - (y1 + dy * t), 2));
        if (distance <= 17) return i;
      }
    }
    return null;
  }

  ChartAnchorEndpoint? _hitSelectedHandle(Offset position,
      ChartPriceScale scale, double width, int visibleCount) {
    final index = _selectedPattern;
    if (index == null || index < 0 || index >= _patterns.length) return null;
    final pattern = _patterns[index];
    if (!pattern.visibleAt(visibleCount)) return null;
    final start = Offset(
      _viewport.chartX(index: pattern.start.index,
          candleCount: visibleCount, plotWidth: width),
      scale.y(pattern.start.price),
    );
    final end = Offset(
      _viewport.chartX(index: pattern.end.index,
          candleCount: visibleCount, plotWidth: width),
      scale.y(pattern.end.price),
    );
    // Make the displayed selection handles accessible to a finger.
    if ((position - start).distance <= 22) return ChartAnchorEndpoint.start;
    if ((position - end).distance <= 22) return ChartAnchorEndpoint.end;
    return null;
  }

  /// Price/viewport geometry is shared with the painter; only the small
  /// hit-target tolerance is expressed in logical screen units.
  (int, ShortPositionHandle)? _hitShortPosition(Offset point,
      ChartPriceScale scale, double plotWidth, int count) {
    for (var i = _shortPositions.length - 1; i >= 0; i--) {
      final item = _shortPositions[i];
      if (!item.visibleAt(count)) continue;
      final left = _viewport.chartX(index: item.startIndex,
          candleCount: count, plotWidth: plotWidth);
      final right = _viewport.chartX(index: item.endIndex,
          candleCount: count, plotWidth: plotWidth);
      final top = scale.y(item.stop);
      final entry = scale.y(item.entry);
      final bottom = scale.y(item.target);
      final targets = <(ShortPositionHandle, Offset)>[
        (ShortPositionHandle.stop, Offset(left, top)),
        (ShortPositionHandle.target, Offset(left, bottom)),
        (ShortPositionHandle.entry, Offset(left, entry)),
        (ShortPositionHandle.end, Offset(right, entry)),
      ];
      for (final target in targets) {
        if ((point - target.$2).distance <= 22) return (i, target.$1);
      }
      if (point.dx >= left - 12 && point.dx <= right + 12 &&
          point.dy >= top && point.dy <= bottom) {
        return (i, ShortPositionHandle.body);
      }
    }
    return null;
  }

  void _placeShortAt(ChartAnchor anchor) {
    if (_shortEntryAnchor == null) {
      _shortEntryAnchor = anchor;
      _shortStopPrice = null;
    } else if (_shortStopPrice == null) {
      if (anchor.price <= _shortEntryAnchor!.price) return;
      _shortStopPrice = anchor.price;
    } else {
      if (anchor.price >= _shortEntryAnchor!.price) return;
      _saveDrawingUndo();
      _shortPositions.add(ChartShortPosition(
        startIndex: math.min(_shortEntryAnchor!.index, anchor.index),
        endIndex: math.max(_shortEntryAnchor!.index, anchor.index),
        entry: _shortEntryAnchor!.price,
        stop: _shortStopPrice!,
        target: anchor.price,
      ));
      _selectedShort = _shortPositions.length - 1;
      _placingShort = false;
      _shortEntryAnchor = null;
      _shortStopPrice = null;
    }
  }

  void _placeRectangleAt(ChartAnchor anchor) {
    final first = _rectangleFirstCorner;
    if (first == null) {
      _rectangleFirstCorner = anchor;
      return;
    }
    if (first.index == anchor.index || first.price == anchor.price) return;
    _saveDrawingUndo();
    _rectangles.add(ChartPriceRectangle(
      startIndex: math.min(first.index, anchor.index),
      endIndex: math.max(first.index, anchor.index),
      upper: math.max(first.price, anchor.price),
      lower: math.min(first.price, anchor.price),
    ));
    _selectedRectangle = _rectangles.length - 1;
    _placingRectangle = false;
    _rectangleFirstCorner = null;
  }

  void _updateRectangleDrag(Offset current, ChartPriceScale scale,
      double plotWidth, int count) {
    final index = _selectedRectangle;
    final original = _rectangleAtDragStart;
    if (!_draggingRectangle || index == null || original == null ||
        index >= _rectangles.length) return;
    final price = scale.price(current.dy.clamp(0.0, scale.height).toDouble());
    final bar = _viewport.indexAt(
      x: current.dx.clamp(0.0, plotWidth).toDouble(),
      plotWidth: plotWidth, candleCount: count);
    if (bar == null) return;
    ChartPriceRectangle? next;
    if (_rectangleDragHandle != null) {
      next = original.withHandle(_rectangleDragHandle!, bar, price);
    } else {
      final proposedBars = ((current.dx - _gestureFocalX) /
          _viewport.barWidth).round();
      final deltaBars = proposedBars.clamp(-original.startIndex,
          math.max(0, count - 1 - original.endIndex)).toInt();
      final initialPrice = scale.price(
          _gestureFocalY.clamp(0.0, scale.height).toDouble());
      next = original.moved(deltaBars, price - initialPrice);
    }
    if (next != null) _rectangles[index] = next;
  }

  void _updateShortDrag(Offset current, ChartPriceScale scale,
      double width, int count) {
    final index = _selectedShort;
    final handle = _draggingShortHandle;
    final original = _shortAtDragStart;
    if (index == null || handle == null || original == null ||
        index >= _shortPositions.length) return;
    final price = scale.price(current.dy.clamp(0, scale.height).toDouble());
    final bar = _viewport.indexAt(x: current.dx.clamp(0, width).toDouble(),
        plotWidth: width, candleCount: count);
    ChartShortPosition? updated;
    switch (handle) {
      case ShortPositionHandle.stop:
        updated = original.edited(stop: price);
        break;
      case ShortPositionHandle.entry:
        updated = original.edited(entry: price);
        break;
      case ShortPositionHandle.target:
        updated = original.edited(target: price);
        break;
      case ShortPositionHandle.start:
        if (bar != null) updated = original.edited(startIndex: bar);
        break;
      case ShortPositionHandle.end:
        if (bar != null) updated = original.edited(endIndex: bar);
        break;
      case ShortPositionHandle.body:
        final priceDelta = price - scale.price(
            _gestureFocalY.clamp(0, scale.height).toDouble());
        final proposed = ((current.dx - _gestureFocalX) /
            _viewport.barWidth).round();
        final bars = proposed.clamp(-original.startIndex,
            math.max(0, count - 1 - original.endIndex)).toInt();
        final moved = original.moved(bars, priceDelta);
        if (moved.target > 0) updated = moved;
        break;
    }
    if (updated != null) _shortPositions[index] = updated;
  }

  void _selectDrawingMode({ChartDrawingTool? tool, bool short = false,
      bool rectangle = false}) {
    setState(() {
      _drawing = true;
      _placingShort = short;
      _placingRectangle = rectangle;
      if (tool != null) _drawingTool = tool;
      _shortEntryAnchor = null;
      _shortStopPrice = null;
      _rectangleFirstCorner = null;
      _pendingAnchor = null;
      _selectedShort = null;
      _selectedRectangle = null;
      _selectedLine = null;
      _selectedPattern = null;
    });
  }

  Widget _buildDrawingRail(double height) => Positioned(
    left: 0, top: math.min(100.0, height * .16), bottom: 15, width: 46,
    child: Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
      ),
      child: SingleChildScrollView(
        child: Column(children: [
          IconButton(
            key: const Key('drawing-rail-cursor'),
            tooltip: 'تحريك الشارت',
            onPressed: () => setState(() {
              _drawing = false;
              _placingShort = false;
              _placingRectangle = false;
              _pendingAnchor = null;
              _rectangleFirstCorner = null;
            }),
            icon: const Icon(Icons.near_me_outlined, size: 23),
          ),
          const Divider(height: 1),
          IconButton(
            tooltip: 'خط اتجاه',
            onPressed: () => _selectDrawingMode(tool: ChartDrawingTool.trendLine),
            icon: const Icon(Icons.show_chart, size: 23),
          ),
          IconButton(
            tooltip: 'تصحيح فيبوناتشي',
            onPressed: () => _selectDrawingMode(tool: ChartDrawingTool.fibonacci),
            icon: const Icon(Icons.tune, size: 23),
          ),
          IconButton(
            tooltip: 'خط أفقي',
            onPressed: () => _selectDrawingMode(tool: ChartDrawingTool.horizontal),
            icon: const Icon(Icons.horizontal_rule, size: 23),
          ),
          IconButton(
            key: const Key('drawing-rail-short'),
            tooltip: 'أداة مركز بيع',
            onPressed: () => _selectDrawingMode(short: true),
            icon: Icon(Icons.south_east, size: 23,
              color: _placingShort || _selectedShort != null
                  ? TradeColors.shortHandle : null),
          ),
          IconButton(
            key: const Key('drawing-rail-rectangle'),
            tooltip: 'مستطيل نطاق سعري',
            onPressed: () => _selectDrawingMode(rectangle: true),
            icon: Icon(Icons.crop_square_outlined, size: 23,
              color: _placingRectangle || _selectedRectangle != null
                  ? TradeColors.rectangleHandle : null),
          ),
          IconButton(
            tooltip: 'مغناطيس الأسعار',
            onPressed: _showDrawingTools,
            icon: const Icon(Icons.tune_outlined, size: 23),
          ),
        ]),
      ),
    ),
  );

  void _deleteSelectedShort() {
    final index = _selectedShort;
    if (index == null || index >= _shortPositions.length) return;
    setState(() {
      _saveDrawingUndo();
      _shortPositions.removeAt(index);
      _selectedShort = null;
    });
  }

  void _deleteSelectedRectangle() {
    final index = _selectedRectangle;
    if (index == null || index >= _rectangles.length) return;
    setState(() {
      _saveDrawingUndo();
      _rectangles.removeAt(index);
      _selectedRectangle = null;
    });
  }

  void _styleSelectedRectangle({double? strokeWidth, int? borderColor,
      int? fillColor}) {
    final index = _selectedRectangle;
    if (index == null || index >= _rectangles.length) return;
    final updated = _rectangles[index].edited(strokeWidth: strokeWidth,
      borderColorValue: borderColor, fillColorValue: fillColor);
    if (updated == null) return;
    setState(() {
      _saveDrawingUndo();
      _rectangles[index] = updated;
    });
  }

  Future<void> _rectangleProperties() async {
    if (_selectedRectangle == null) return;
    await showModalBottomSheet<void>(context: context, showDragHandle: true,
      builder: (sheetContext) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const TradeSectionTitle('خصائص المستطيل السعري'),
          const SizedBox(height: 12),
          const Align(alignment: AlignmentDirectional.centerStart,
            child: Text('سمك الحدود', textDirection: TextDirection.rtl)),
          Wrap(spacing: 10, children: [
            for (final px in const [1.0, 2.0, 3.0])
              OutlinedButton(onPressed: () {
                _styleSelectedRectangle(strokeWidth: px);
                Navigator.pop(sheetContext);
              }, child: Text('${px.toInt()}px', textDirection: TextDirection.ltr)),
          ]),
          const SizedBox(height: 8),
          const Align(alignment: AlignmentDirectional.centerStart,
            child: Text('لون الحدود', textDirection: TextDirection.rtl)),
          Wrap(spacing: 10, children: [
            for (final color in const [0xFFD5A63C, 0xFFFFA41D,
              0xFF2962FF, 0xFFE95454, 0xFF212121])
              IconButton(
                tooltip: 'تغيير لون الحدود',
                onPressed: () {
                  _styleSelectedRectangle(borderColor: color);
                  Navigator.pop(sheetContext);
                },
                icon: Icon(Icons.circle_outlined, color: Color(color), size: 27)),
          ]),
          const SizedBox(height: 8),
          const Align(alignment: AlignmentDirectional.centerStart,
            child: Text('لون التعبئة', textDirection: TextDirection.rtl)),
          Wrap(spacing: 10, children: [
            for (final color in const [0xFF5BAD6F, 0xFF4A9DE8,
              0xFFF2AB61, 0xFFE78BA1])
              IconButton(
                tooltip: 'تغيير لون التعبئة',
                onPressed: () {
                  _styleSelectedRectangle(fillColor: color);
                  Navigator.pop(sheetContext);
                },
                icon: Icon(Icons.circle, color: Color(color), size: 27)),
          ]),
        ]),
      )));
  }

  Widget _rectangleToolbarItem(Widget visual, String tooltip,
      VoidCallback callback, {double width = 38}) => SizedBox(
    width: width, height: 43,
    child: IconButton(
      key: ValueKey('rect-toolbar-$tooltip'), tooltip: tooltip,
      onPressed: callback, padding: EdgeInsets.zero,
      icon: visual,
    ),
  );

  Widget _rectangleUnderlinedIcon(IconData data, Color stripe) =>
      Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(data, size: 23, color: Theme.of(context).colorScheme.onSurface),
        Container(width: 20, height: 3, margin: const EdgeInsets.only(top: 1),
          decoration: BoxDecoration(color: stripe,
            borderRadius: BorderRadius.circular(2))),
      ]);

  Widget _buildRectangleFloatingToolbar(double width) {
    final selected = _selectedRectangle;
    final stroke = selected != null && selected < _rectangles.length
        ? _rectangles[selected].strokeWidth : 1.0;
    return Positioned(top: 12, left: 0,
      child: Container(
        constraints: BoxConstraints(maxWidth: width),
        height: 48,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).dividerColor),
          boxShadow: const [BoxShadow(color: Colors.black12,
            blurRadius: 5, offset: Offset(0, 2))],
        ),
        child: SingleChildScrollView(scrollDirection: Axis.horizontal,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _rectangleToolbarItem(const Icon(Icons.more_horiz, size: 24),
                'خصائص المستطيل', _rectangleProperties),
            _rectangleToolbarItem(const Icon(Icons.delete_outline, size: 25),
                'حذف المستطيل', _deleteSelectedRectangle),
            _rectangleToolbarItem(const _RectangleToolbarAngle(),
                'ضبط زوايا المستطيل', _rectangleProperties),
            _rectangleToolbarItem(const Icon(Icons.remove, size: 26),
                'تغيير لون الحدود', _rectangleProperties),
            _rectangleToolbarItem(Text('${stroke.toStringAsFixed(0)}px',
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontSize: 14)),
                'سمك الخط', _rectangleProperties, width: 40),
            _rectangleToolbarItem(_rectangleUnderlinedIcon(
                Icons.text_fields, TradeColors.shortLabelRed),
                'خصائص النص', _rectangleProperties),
            _rectangleToolbarItem(_rectangleUnderlinedIcon(
                Icons.format_color_fill_outlined,
                TradeColors.rectangleAccentGreen),
                'لون التعبئة', _rectangleProperties),
            _rectangleToolbarItem(_rectangleUnderlinedIcon(
                Icons.edit_outlined, TradeColors.rectangleAccentOrange),
                'لون القلم', _rectangleProperties),
            _rectangleToolbarItem(const Icon(Icons.grid_view_outlined, size: 24),
                'إضافة مستطيل', () => _selectDrawingMode(rectangle: true)),
          ])),
      ));
  }

  Future<void> _shortProperties() async {
    final index = _selectedShort;
    if (index == null || index >= _shortPositions.length) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const TradeSectionTitle('خصائص مركز البيع'),
          const SizedBox(height: 8),
          Text('الدخول: ${_shortPositions[index].entry.toStringAsFixed(5)}',
            textDirection: TextDirection.ltr),
          Text('وقف الخسارة: ${_shortPositions[index].stop.toStringAsFixed(5)}',
            textDirection: TextDirection.ltr),
          Text('الهدف: ${_shortPositions[index].target.toStringAsFixed(5)}',
            textDirection: TextDirection.ltr),
          Text('العائد / المخاطرة: ${_shortPositions[index].rewardRisk.toStringAsFixed(2)}',
            textDirection: TextDirection.ltr),
          const SizedBox(height: 8),
          const Text('هذه أداة رسم تحليلية، وليست أمر بيع أو نتيجة صفقة منفّذة.',
            textAlign: TextAlign.center),
          TextButton.icon(onPressed: () {
            setState(() => _showShortLabels = !_showShortLabels);
            Navigator.pop(sheetContext);
          }, icon: const Icon(Icons.text_fields),
            label: Text(_showShortLabels ? 'إخفاء التسميات' : 'إظهار التسميات')),
        ]),
      )),
    );
  }

  Widget _buildShortFloatingToolbar(double width) => Positioned(
    top: 12,
    left: math.max(4, (width - 296) / 2),
    child: Container(
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 9,
          offset: Offset(0, 3))],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _shortToolbarButton(Icons.more_horiz, 'خصائص المركز', _shortProperties),
        _shortToolbarButton(Icons.delete_outline, 'حذف مركز البيع', _deleteSelectedShort),
        _shortToolbarButton(Icons.format_color_fill_outlined,
            'تفاصيل وقف الخسارة', _shortProperties,
            color: TradeColors.shortLabelRed),
        _shortToolbarButton(Icons.format_color_fill_outlined,
            'تفاصيل الهدف', _shortProperties,
            color: TradeColors.shortLabelBlue),
        _shortToolbarButton(Icons.text_fields,
            _showShortLabels ? 'إخفاء التسميات' : 'إظهار التسميات',
            () => setState(() => _showShortLabels = !_showShortLabels)),
        _shortToolbarButton(Icons.add_box_outlined, 'إضافة مركز بيع',
            () => _selectDrawingMode(short: true)),
        _shortToolbarButton(Icons.more_vert, 'المزيد', _shortProperties),
      ]),
    ),
  );

  Widget _shortToolbarButton(IconData icon, String tooltip,
      VoidCallback onPressed, {Color? color}) => SizedBox(
    width: 40, height: 44,
    child: IconButton(
      key: ValueKey('short-toolbar-$tooltip'),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      icon: Icon(icon, size: 22, color: color),
    ),
  );

  ChartAnchor? _anchorAt(Offset point, ChartPriceScale scale,
      double plotWidth, int count) {
    final index = _viewport.indexAt(
        x: point.dx, plotWidth: plotWidth, candleCount: count);
    if (index == null) return null;
    final rawPrice = scale.price(point.dy.clamp(0, scale.height).toDouble());
    final bar = _displayCandles[index];
    return ChartAnchor(index, snapDrawingPrice(
      requestedPrice: rawPrice,
      ohlc: [bar.open, bar.high, bar.low, bar.close],
      mode: _magnetMode,
      weakPriceTolerance: (scale.maximum - scale.minimum) /
          scale.height * 12,
    ));
  }

  Future<void> _editSelectedDrawing() async {
    final selected = _selectedPattern;
    if (selected != null && selected < _patterns.length) {
      final pattern = _patterns[selected];
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, updateSheet) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const TradeSectionTitle('خصائص الرسم'),
                const SizedBox(height: 12),
                Wrap(spacing: 10, children: [
                  for (final color in const <int>[
                    0xFF3467E9, 0xFF26A69A, 0xFFE34A4A, 0xFFE8A426,
                  ])
                    IconButton(
                      tooltip: 'تغيير لون الرسم',
                      onPressed: () {
                        setState(() {
                          _saveDrawingUndo();
                          _patterns[selected] = _patterns[selected].styled(
                              colorValue: color);
                        });
                        updateSheet(() {});
                      },
                      icon: Icon(Icons.circle, color: Color(color), size: 30),
                    ),
                ]),
                ListTile(
                  title: const Text('سماكة الخط'),
                  subtitle: Slider(
                    min: 1, max: 4, divisions: 6,
                    value: _patterns[selected].strokeWidth.clamp(1.0, 4.0).toDouble(),
                    onChangeStart: (_) => _saveDrawingUndo(),
                    onChanged: (value) {
                      setState(() => _patterns[selected] =
                          _patterns[selected].styled(strokeWidth: value));
                      updateSheet(() {});
                    },
                  ),
                ),
                if (pattern.tool == ChartDrawingTool.fibonacci)
                  SwitchListTile(
                    title: const Text('إظهار تسميات مستويات فيبوناتشي'),
                    value: _patterns[selected].showLabels,
                    onChanged: (value) {
                      setState(() {
                        _saveDrawingUndo();
                        _patterns[selected] =
                            _patterns[selected].styled(showLabels: value);
                      });
                      updateSheet(() {});
                    },
                  ),
              ]),
            ),
          ),
        ),
      );
      return;
    }
    final index = _selectedLine;
    if (index == null || index >= _levels.length) return;
    final field = TextEditingController(text: _levels[index].toStringAsFixed(3));
    try {
      await showModalBottomSheet<void>(
        context: context, showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const TradeSectionTitle('سعر الخط الأفقي'),
              TextField(controller: field,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'السعر')),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () {
                  final value = double.tryParse(field.text);
                  if (value == null || !value.isFinite || value <= 0) return;
                  setState(() {
                    _saveDrawingUndo();
                    _levels[index] = value;
                  });
                  Navigator.pop(sheetContext);
                },
                child: const Text('حفظ'),
              ),
            ]),
          ),
        ),
      );
    } finally {
      field.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final candles = _displayCandles;
    final surface = colors.surface;
    return Column(children: [
      Container(
        color: surface,
        padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
        child: Row(children: [
          Expanded(
            child: InkWell(
              key: const Key('symbol-picker'),
              borderRadius: BorderRadius.circular(8),
              onTap: _showSymbolPicker,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(child: Text(_symbol, textDirection: TextDirection.ltr,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900))),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down, size: 19),
                  ]),
                  Text(_liveRequested
                      ? 'تحليل السوق · ${_selectedSymbol.source == TradeSource.binance ? 'Binance' : 'cTrader'}'
                      : 'تحليل السوق · غير متصل',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
                ]),
              ),
            ),
          ),
          Flexible(child: TradeStatusChip(label: _liveRequested
              ? (_loading ? 'جار التحميل' : _loadError != null
                  ? 'خطأ في المصدر' : _ctraderTimeCandlesStale
                  ? 'بيانات متأخرة' : _selectedSymbol.source == TradeSource.ctrader
                  ? 'شموع cTrader' : 'شموع Binance')
              : 'غير مرتبط', connected: _liveRequested && !_loading &&
                  _loadError == null && !_ctraderTimeCandlesStale &&
                  candles.isNotEmpty)),
          _iconAction(icon: Icons.fullscreen, label: 'ملء الشاشة', onPressed: _notifyUnconnected),
          _iconAction(icon: Icons.refresh, label: 'تحديث أسعار السوق',
            onPressed: _liveRequested ? _loadRealHistory : _notifyUnconnected),
        ]),
      ),
      const Divider(height: 1),
      if (_mode == ChartMode.range)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          color: TradeColors.blue.withValues(alpha: .07),
          child: Text(_liveRequested
              ? 'مدى $_rangeTicks نقطة · ${!_rangeSourceSupported ? 'غير مدعوم لهذا المصدر' : _actualRange.isEmpty ? 'انتظار تيكات cTrader' : 'شموع محسوبة من تيكات BID لـ cTrader'}'
              : 'مدى $_rangeTicks · اربط حساب cTrader للحصول على تيكات BID الحقيقية',
              style: const TextStyle(fontSize: 11, color: TradeColors.blue)),
        ),
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      if (_loadError != null && _liveRequested)
        MaterialBanner(content: Text(_loadError!), actions: [
          TextButton(onPressed: _loadRealHistory, child: const Text('إعادة المحاولة')),
        ]),
      if (_olderLoading) const LinearProgressIndicator(minHeight: 2),
      if (_olderLoadError != null)
        Container(
          color: TradeColors.blue.withValues(alpha: .06),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Expanded(child: Text(_olderLoadError!, style: const TextStyle(fontSize: 12))),
            TextButton(onPressed: () {
              setState(() => _olderLoadError = null);
              unawaited(_mode == ChartMode.range
                  ? _loadOlderRangeHistory()
                  : _loadOlderHistory(manual: true));
            }, child: const Text('إعادة المحاولة')),
          ]),
        ),
      Expanded(
        child: LayoutBuilder(builder: (context, constraints) {
          final plotWidth = math.max(1.0, constraints.maxWidth - 61);
          _momentumPlotWidth = plotWidth;
          return Stack(children: [
          Positioned.fill(child: GestureDetector(
            key: const Key('chart-gesture-area'),
            behavior: HitTestBehavior.opaque,
            onScaleStart: (details) {
              _momentum.stop(); // A new gesture owns the chart immediately.
              _gestureHadMultiTouch = details.pointerCount > 1;
              _gestureStart = _viewport;
              _gestureFocalX = details.localFocalPoint.dx;
              _gestureFocalY = details.localFocalPoint.dy;
              _draggingShortHandle = null;
              _shortAtDragStart = null;
              _draggingRectangle = false;
              _rectangleDragHandle = null;
              _rectangleAtDragStart = null;
              if (_drawing && details.pointerCount == 1) {
                final scale = _priceScale(candles, plotWidth, constraints.maxHeight);
                final rectangleHit = PriceRectangleGeometry.hitTest(
                    details.localFocalPoint, _rectangles, _viewport,
                    scale, candles.length, plotWidth);
                final shortHit = rectangleHit == null
                    ? _hitShortPosition(details.localFocalPoint,
                        scale, plotWidth, candles.length) : null;
                if (rectangleHit != null) {
                  _selectedRectangle = rectangleHit.$1;
                  _rectangleDragHandle = rectangleHit.$2;
                  _rectangleAtDragStart = _rectangles[rectangleHit.$1];
                  _draggingRectangle = true;
                  _selectedShort = null;
                  _selectedLine = null;
                  _selectedPattern = null;
                  _saveDrawingUndo();
                }
                _draggedEndpoint = rectangleHit == null && shortHit == null
                    ? _hitSelectedHandle(details.localFocalPoint,
                        scale, plotWidth, candles.length) : null;
                if (shortHit != null) {
                  _selectedShort = shortHit.$1;
                  _draggingShortHandle = shortHit.$2;
                  _shortAtDragStart = _shortPositions[shortHit.$1];
                  _selectedLine = null;
                  _selectedPattern = null;
                  _saveDrawingUndo();
                }
                _selectedLine = rectangleHit == null && shortHit == null &&
                    _draggedEndpoint == null
                    ? _hitLine(details.localFocalPoint.dy, scale) : null;
                _draggingLine = _selectedLine != null;
                if (_draggedEndpoint != null) {
                  _draggingPattern = true;
                } else {
                  _selectedPattern = rectangleHit != null || shortHit != null ||
                      _draggingLine ? null :
                      _hitPattern(details.localFocalPoint, scale,
                          plotWidth, candles.length);
                  _draggingPattern = _selectedPattern != null;
                }
                _patternAtDragStart = _draggingPattern
                    ? _patterns[_selectedPattern!] : null;
                if (_draggingLine || _draggingPattern) _saveDrawingUndo();
              } else {
                _draggingLine = false;
                _draggingPattern = false;
                _draggedEndpoint = null;
              }
            },
            onScaleUpdate: (details) {
              if (details.pointerCount > 1) _gestureHadMultiTouch = true;
              setState(() {
              if (_draggingRectangle && details.pointerCount == 1) {
                final scale = _priceScale(candles, plotWidth, constraints.maxHeight);
                _updateRectangleDrag(details.localFocalPoint, scale,
                    plotWidth, candles.length);
              } else if (_draggingShortHandle != null && details.pointerCount == 1) {
                final scale = _priceScale(candles, plotWidth, constraints.maxHeight);
                _updateShortDrag(details.localFocalPoint, scale,
                    plotWidth, candles.length);
              } else if (_draggingLine && _selectedLine != null && details.pointerCount == 1) {
                final scale = _priceScale(candles, plotWidth, constraints.maxHeight);
                _levels[_selectedLine!] = scale.price(
                    details.localFocalPoint.dy.clamp(0, scale.height).toDouble());
              } else if (_draggingPattern && _selectedPattern != null &&
                  _patternAtDragStart != null && details.pointerCount == 1) {
                final scale = _priceScale(candles, plotWidth, constraints.maxHeight);
                final original = _patternAtDragStart!;
                if (_draggedEndpoint != null) {
                  final anchor = _anchorAt(details.localFocalPoint,
                      scale, plotWidth, candles.length);
                  if (anchor != null) {
                    _patterns[_selectedPattern!] = original.withEndpoint(
                        _draggedEndpoint!, anchor);
                  }
                } else {
                  final proposedBars = ((details.localFocalPoint.dx -
                      _gestureFocalX) / _viewport.barWidth).round();
                  final minIndex = math.min(original.start.index, original.end.index);
                  final maxIndex = math.max(original.start.index, original.end.index);
                  final barDelta = proposedBars.clamp(-minIndex,
                      math.max(0, candles.length - 1 - maxIndex));
                  final change = scale.price(
                      details.localFocalPoint.dy.clamp(0, scale.height).toDouble()) -
                      scale.price(_gestureFocalY.clamp(0, scale.height).toDouble());
                  _patterns[_selectedPattern!] = original.moved(barDelta.toInt(), change);
                }
              } else if (details.pointerCount > 1) {
                _viewport = _gestureStart.pinch(
                  scale: details.scale,
                  initialFocalX: _gestureFocalX,
                  currentFocalX: details.localFocalPoint.dx,
                  plotWidth: plotWidth,
                  candleCount: candles.length,
                );
              } else {
                _viewport = _viewport.pan(
                  deltaX: details.focalPointDelta.dx,
                  plotWidth: plotWidth,
                  candleCount: candles.length,
                );
              }
              });
              // The same paging threshold also applies during momentum.
              if (_draggingShortHandle == null &&
                  !_draggingLine && !_draggingPattern && !_draggingRectangle) {
                _prefetchOlderAtEdge(plotWidth, candles.length);
              }
            },
            onScaleEnd: (details) {
              final editing = _draggingLine || _draggingPattern ||
                  _draggingShortHandle != null || _draggingRectangle;
              _draggingLine = false;
              _draggingPattern = false;
              _patternAtDragStart = null;
              _draggedEndpoint = null;
              _draggingShortHandle = null;
              _shortAtDragStart = null;
              _draggingRectangle = false;
              _rectangleDragHandle = null;
              _rectangleAtDragStart = null;
              final velocity = details.velocity.pixelsPerSecond.dx;
              if (chartShouldFling(
                  horizontalVelocity: velocity,
                  candleCount: candles.length,
                  multiTouch: _gestureHadMultiTouch,
                  editingDrawing: editing || _crosshair != null,
                  reducedMotion: MediaQuery.disableAnimationsOf(context))) {
                _startMomentum(velocity, plotWidth);
              }
            },
            onDoubleTap: () {
              _momentum.stop();
              setState(() { _viewport = const ChartViewport(); _crosshair = null; });
            },
            onLongPressStart: (details) {
              _momentum.stop();
              setState(() => _crosshair = details.localPosition);
            },
            onLongPressMoveUpdate: (details) => setState(() => _crosshair = details.localPosition),
            onLongPressEnd: (_) => setState(() => _crosshair = null),
            onTapUp: (details) {
              if (!_drawing || details.localPosition.dx > plotWidth) return;
              final scale = _priceScale(candles, plotWidth, constraints.maxHeight);
              final hit = _hitLine(details.localPosition.dy, scale);
              setState(() {
                final rectangleHit = PriceRectangleGeometry.hitTest(
                    details.localPosition, _rectangles, _viewport,
                    scale, candles.length, plotWidth);
                if (rectangleHit != null) {
                  _selectedRectangle = rectangleHit.$1;
                  _selectedShort = null;
                  _selectedLine = null;
                  _selectedPattern = null;
                  _pendingAnchor = null;
                  return;
                }
                if (_placingRectangle) {
                  final anchor = _anchorAt(details.localPosition,
                      scale, plotWidth, candles.length);
                  if (anchor != null) _placeRectangleAt(anchor);
                  return;
                }
                if (_selectedRectangle != null) {
                  _selectedRectangle = null;
                  return;
                }
                final shortHit = _hitShortPosition(details.localPosition,
                    scale, plotWidth, candles.length);
                if (shortHit != null) {
                  _selectedShort = shortHit.$1;
                  _selectedLine = null;
                  _selectedPattern = null;
                  _pendingAnchor = null;
                  return;
                }
                if (_placingShort) {
                  final anchor = _anchorAt(details.localPosition,
                      scale, plotWidth, candles.length);
                  if (anchor != null) _placeShortAt(anchor);
                  return;
                }
                if (hit != null) {
                  _selectedLine = hit;
                  _selectedPattern = null;
                  _selectedShort = null;
                  _pendingAnchor = null;
                  return;
                }
                final hitPattern = _hitPattern(details.localPosition,
                    scale, plotWidth, candles.length);
                if (hitPattern != null) {
                  _selectedPattern = hitPattern;
                  _selectedLine = null;
                  _selectedShort = null;
                  _pendingAnchor = null;
                  return;
                }
                if (_drawingTool != ChartDrawingTool.horizontal) {
                  final anchor = _anchorAt(details.localPosition, scale,
                      plotWidth, candles.length);
                  if (anchor == null) return;
                  if (_pendingAnchor == null) {
                    _pendingAnchor = anchor;
                  } else {
                    _saveDrawingUndo();
                    _patterns.add(ChartPattern(
                      tool: _drawingTool,
                      start: _pendingAnchor!,
                      end: anchor,
                    ));
                    _selectedPattern = _patterns.length - 1;
                    _selectedLine = null;
                    _selectedShort = null;
                    _pendingAnchor = null;
                  }
                  return;
                }
                _saveDrawingUndo();
                final anchor = _anchorAt(details.localPosition,
                    scale, plotWidth, candles.length);
                if (anchor == null) return;
                _levels.add(anchor.price);
                _selectedLine = _levels.length - 1;
                _selectedPattern = null;
                _selectedShort = null;
              });
            },
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size.infinite,
                painter: _CandleChartPainter(
                  candles: candles,
                  timestamps: _mode == ChartMode.range
                      ? _rangeBarTimestamps : _actualTimestamps,
                  dark: Theme.of(context).brightness == Brightness.dark,
                  viewport: _viewport,
                  crosshair: _crosshair,
                  levels: List<double>.unmodifiable(_levels),
                  patterns: List<ChartPattern>.unmodifiable(_patterns),
                  shortPositions: List<ChartShortPosition>.unmodifiable(_shortPositions),
                  selectedLine: _drawing ? _selectedLine : null,
                  selectedPattern: _drawing ? _selectedPattern : null,
                  selectedShort: _drawing ? _selectedShort : null,
                  showShortLabels: _showShortLabels,
                  indicator: _showIndicators,
                ),
              ),
            ),
          )),
          if (candles.isNotEmpty && _rectangles.isNotEmpty)
            Positioned.fill(child: IgnorePointer(child: RepaintBoundary(
              child: CustomPaint(
                painter: ChartPriceRectanglePainter(
                  drawings: List<ChartPriceRectangle>.unmodifiable(_rectangles),
                  selectedIndex: _drawing ? _selectedRectangle : null,
                  viewport: _viewport,
                  scale: _priceScale(candles, plotWidth, constraints.maxHeight),
                  candleCount: candles.length,
                  plotWidth: plotWidth,
                  dark: Theme.of(context).brightness == Brightness.dark,
                  timestamps: _mode == ChartMode.range
                      ? _rangeBarTimestamps : _actualTimestamps,
                ),
                size: Size.infinite,
              ),
            ))),
          if (candles.isEmpty)
            Positioned.fill(child: IgnorePointer(child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_loading)
                    const CircularProgressIndicator(strokeWidth: 2),
                  if (_loading) const SizedBox(height: 14),
                  Text(_loading ? 'جارِ تحميل شموع السوق الفعلية…'
                    : !_liveRequested
                        ? 'اربط حساب cTrader من شاشة الحساب لعرض شموع الذهب والفوركس الحقيقية.'
                        : _loadError ?? 'لا توجد شموع متاحة من المصدر.',
                    key: const Key('chart-source-empty'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
                ]),
              ),
            ))),
          if (candles.isNotEmpty && _drawing)
            _buildDrawingRail(constraints.maxHeight),
          if (_drawing && _selectedShort != null &&
              _selectedShort! < _shortPositions.length && candles.isNotEmpty)
            _buildShortFloatingToolbar(constraints.maxWidth),
          if (_drawing && _selectedRectangle != null &&
              _selectedRectangle! < _rectangles.length && candles.isNotEmpty)
            _buildRectangleFloatingToolbar(constraints.maxWidth),
          ]);
        }),
      ),
      // The chart stays the dominant surface; its tool strip sits below the
      // time axis, as in the supplied mobile reference.
      Container(
        color: surface,
        height: 50,
        child: SingleChildScrollView(
         scrollDirection: Axis.horizontal,
         child: Row(children: [
          TextButton.icon(
            key: const Key('timeframe-picker'),
            onPressed: _showTimeframePicker,
            label: Text(_timeframe, textDirection: TextDirection.ltr),
            icon: const Icon(Icons.keyboard_arrow_down, size: 18),
          ),
          _iconAction(icon: Icons.candlestick_chart, label: 'نوع الشموع', onPressed: _showChartTypePicker),
          _iconAction(icon: Icons.replay_circle_filled_outlined,
              label: _replay ? 'إغلاق Replay' : 'تشغيل Replay داخل الشارت',
              active: _replay, onPressed: _toggleReplay),
          _iconAction(icon: Icons.functions, label: 'المؤشرات', active: _showIndicators,
            onPressed: () => setState(() => _showIndicators = !_showIndicators)),
          _iconAction(icon: Icons.edit_outlined, label: 'أدوات الرسم', active: _drawing,
            onPressed: _showDrawingTools),
          _iconAction(icon: Icons.zoom_in_outlined, label: 'تكبير الشارت',
            onPressed: () => _zoomBy(1.25)),
          _iconAction(icon: Icons.zoom_out_outlined, label: 'تصغير الشارت',
            onPressed: () => _zoomBy(.8)),
          _iconAction(icon: Icons.last_page, label: 'العودة إلى أحدث شمعة',
            onPressed: () {
              _momentum.stop();
              setState(() => _viewport = _viewport.jumpToLatest());
            }),
          const SizedBox(width: 8),
          if (_mode == ChartMode.range)
            TextButton(onPressed: _showRangeSettings, child: Text('مدى $_rangeTicks')),
         ])),
      ),
      Container(
        padding: const EdgeInsetsDirectional.only(start: 12, end: 8, top: 6, bottom: 6),
        color: surface,
        child: Row(children: [
          const Icon(Icons.info_outline, size: 15, color: TradeColors.blue),
          const SizedBox(width: 6),
          Expanded(child: Text(_marketEvidenceLabel,
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11))),
          if (_drawing && (_selectedLine != null || _selectedPattern != null ||
              _selectedShort != null || _selectedRectangle != null))
            IconButton(tooltip: 'خصائص الرسم المحدد',
              onPressed: _selectedRectangle != null ? _rectangleProperties :
                  _selectedShort != null ? _shortProperties : _editSelectedDrawing,
              icon: const Icon(Icons.tune)),
          if (_drawing && (_selectedLine != null || _selectedPattern != null ||
              _selectedShort != null || _selectedRectangle != null))
            IconButton(tooltip: 'حذف الرسم المحدد', onPressed: () => setState(() {
              _saveDrawingUndo();
              if (_selectedRectangle != null && _selectedRectangle! < _rectangles.length) {
                _rectangles.removeAt(_selectedRectangle!);
              } else if (_selectedShort != null && _selectedShort! < _shortPositions.length) {
                _shortPositions.removeAt(_selectedShort!);
              } else if (_selectedLine != null && _selectedLine! < _levels.length) {
                _levels.removeAt(_selectedLine!);
              } else if (_selectedPattern != null && _selectedPattern! < _patterns.length) {
                _patterns.removeAt(_selectedPattern!);
              }
              _selectedLine = null;
              _selectedPattern = null;
              _selectedShort = null;
              _selectedRectangle = null;
            }), icon: const Icon(Icons.delete_outline)),
          if (_lineUndo.isNotEmpty)
            TextButton.icon(
              onPressed: _undoDrawing,
              icon: const Icon(Icons.undo, size: 18),
              label: const Text('تراجع'),
            ),
          if (_lineRedo.isNotEmpty)
            IconButton(
              key: const Key('drawing-redo'), tooltip: 'إعادة الرسم',
              onPressed: _redoDrawing, icon: const Icon(Icons.redo, size: 19)),
        ]),
      ),
      if (widget.journal != null && !_replay)
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            key: const Key('open-paper-order'),
            onPressed: _openPaperOrder,
            icon: const Icon(Icons.add_chart, size: 17),
            label: const Text('صفقة تجريبية'),
          ),
        ),
      if (_pendingAnchor != null && _drawing)
        Container(
          alignment: Alignment.center,
          color: TradeColors.blue.withValues(alpha: .06),
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: const Text('المس الشارت لتحديد النقطة الثانية للرسم',
              style: TextStyle(fontSize: 12, color: TradeColors.blue)),
        ),
      if (_drawing && _selectedPattern != null)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 3),
          child: Text('اسحب دائرة البداية أو النهاية لتعديل طرف الرسم فقط',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: TradeColors.blue)),
        ),
      if (_placingShort && candles.isNotEmpty)
        Container(
          alignment: Alignment.center,
          color: TradeColors.shortHandle.withValues(alpha: .06),
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(_shortEntryAnchor == null
              ? 'مركز بيع: المس الشارت لتحديد سعر الدخول'
              : _shortStopPrice == null
                  ? 'حدد وقف الخسارة فوق سعر الدخول'
                  : 'حدد الهدف أسفل سعر الدخول',
              key: const Key('short-position-placement-hint'),
              style: const TextStyle(fontSize: 12, color: TradeColors.shortHandle)),
        ),
      if (_placingRectangle && candles.isNotEmpty)
        Container(alignment: Alignment.center,
          color: TradeColors.rectangleHandle.withValues(alpha: .06),
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(_rectangleFirstCorner == null
            ? 'المستطيل: اختر الزاوية الأولى على الشارت'
            : 'المستطيل: اختر الزاوية المقابلة لتحديد السعر والزمن',
            key: const Key('price-rectangle-placement-hint'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: TradeColors.rectangleHandle)),
        ),
      if (_replay) _replayControls(context),
    ]);
  }

  Widget _replayControls(BuildContext context) => Container(
        color: Theme.of(context).colorScheme.surface,
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Text('Replay', style: TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('$_visibleThrough / $_totalBars شمعة',
                style: Theme.of(context).textTheme.labelSmall),
          ]),
          if (_liveRequested && (_mode == ChartMode.range
              ? _rangeHistoryTicks.isNotEmpty : _actualBars.isNotEmpty))
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _olderLoading || _historyExhausted
                    ? null : () => _mode == ChartMode.range
                        ? _loadOlderRangeHistory()
                        : _loadOlderHistory(manual: true),
                icon: _olderLoading
                    ? const SizedBox(width: 15, height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.history, size: 18),
                label: Text(_historyExhausted ? 'لا تتوفر شموع أقدم'
                    : _mode == ChartMode.range
                        ? 'تحميل تيكات مدى أقدم' : 'تحميل شموع أقدم'),
              ),
            ),
          Row(children: [
            IconButton(tooltip: 'رجوع شمعة',
              onPressed: _visibleThrough <= 1 ? null : () => setState(() {
                _stopPlayback();
                _visibleThrough--;
              }),
              icon: const Icon(Icons.skip_previous)),
            IconButton(key: const Key('replay-play-pause'),
              tooltip: _playing ? 'إيقاف' : 'تشغيل',
              onPressed: _togglePlay,
              icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle_fill,
                  color: TradeColors.blue)),
            IconButton(tooltip: 'تقدم شمعة',
              onPressed: _visibleThrough >= _totalBars ? null : () => setState(() {
                _stopPlayback();
                _visibleThrough++;
              }),
              icon: const Icon(Icons.skip_next)),
            Expanded(child: Slider(
              value: _visibleThrough.clamp(1, math.max(2, _totalBars)).toDouble(),
              min: 1, max: math.max(2, _totalBars).toDouble(),
              divisions: math.max(1, _totalBars - 1),
              label: '$_visibleThrough',
              onChanged: (value) => setState(() {
                _stopPlayback();
                _visibleThrough = value.round();
              }),
            )),
          ]),
        ]),
      );
}

/// Line-only angle glyph; keeps the reference toolbar's outlined style.
class _RectangleToolbarAngle extends StatelessWidget {
  const _RectangleToolbarAngle();

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _RectangleAnglePainter(
      Theme.of(context).colorScheme.onSurface),
    size: const Size(25, 25));
}

class _RectangleAnglePainter extends CustomPainter {
  _RectangleAnglePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()..color = color..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final base = size.height * .78;
    canvas.drawLine(Offset(2, base), Offset(size.width - 1, base), ink);
    canvas.drawLine(Offset(2, base),
      Offset(size.width * .78, size.height * .13), ink);
    canvas.drawArc(Rect.fromLTWH(4, size.height * .49, 10, 10),
      math.pi * 1.5, math.pi * .48, false, ink);
  }

  @override
  bool shouldRepaint(covariant _RectangleAnglePainter old) =>
    old.color != color;
}

class _CandleChartPainter extends CustomPainter {
  _CandleChartPainter({
    required this.candles,
    required this.timestamps,
    required this.dark,
    required this.viewport,
    required this.crosshair,
    required this.levels,
    required this.patterns,
    required this.shortPositions,
    required this.selectedLine,
    required this.selectedPattern,
    required this.selectedShort,
    required this.showShortLabels,
    required this.indicator,
  });

  final List<TradeCandle> candles;
  final List<int> timestamps;
  final bool dark;
  final ChartViewport viewport;
  final Offset? crosshair;
  final List<double> levels;
  final List<ChartPattern> patterns;
  final List<ChartShortPosition> shortPositions;
  final int? selectedLine;
  final int? selectedPattern;
  final int? selectedShort;
  final bool showShortLabels;
  final bool indicator;

  @override
  void paint(Canvas canvas, Size size) {
    final background = dark ? const Color(0xFF000D16) : Colors.white;
    final line = dark ? const Color(0xFF293544) : const Color(0xFFE4EAF1);
    final text = dark ? const Color(0xFF9598A1) : const Color(0xFF637086);
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final axis = size.width - 61;
    if (axis < 30 || size.height < 60 || candles.isEmpty) return;
    final chartHeight = size.height - 24;
    final (start, ending) = viewport.visibleIndices(
      plotWidth: axis,
      candleCount: candles.length,
    );
    if (start >= ending) return;
    final scale = ChartPriceScale.visible(candles, viewport, axis, chartHeight);
    final maximum = scale.maximum;
    final minimum = scale.minimum;
    final span = math.max(.00001, maximum - minimum);
    double y(double price) => scale.y(price);
    final decimals = span < .05 ? 5 : span < 1 ? 4 : span < 20 ? 2 : 1;
    final gridPaint = Paint()..color = line..strokeWidth = .8;
    for (var i = 0; i <= 5; i++) {
      final lineY = chartHeight * i / 5;
      canvas.drawLine(Offset(0, lineY), Offset(axis, lineY), gridPaint);
      _text(canvas, (maximum - span * i / 5).toStringAsFixed(decimals),
          Offset(axis + 3, lineY - 6), text, 10);
    }
    for (var i = 1; i <= 4; i++) {
      final x = axis * i / 5;
      canvas.drawLine(Offset(x, 0), Offset(x, chartHeight), gridPaint);
    }
    canvas.drawLine(Offset(axis, 0), Offset(axis, size.height), gridPaint);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, axis, chartHeight));
    final positiveWick = Paint()
      ..color = TradeColors.positive
      ..strokeWidth = 1.3;
    final negativeWick = Paint()
      ..color = TradeColors.negative
      ..strokeWidth = 1.3;
    final positiveBody = Paint()..color = TradeColors.positive;
    final negativeBody = Paint()..color = TradeColors.negative;
    for (var i = start; i < ending; i++) {
      final candle = candles[i];
      final centerX = viewport.chartX(
        index: i, candleCount: candles.length, plotWidth: axis);
      if (centerX < -viewport.barWidth || centerX > axis + viewport.barWidth) continue;
      canvas.drawLine(Offset(centerX, y(candle.high)), Offset(centerX, y(candle.low)),
          candle.positive ? positiveWick : negativeWick);
      final openY = y(candle.open);
      final closeY = y(candle.close);
      canvas.drawRect(Rect.fromLTRB(
        centerX - viewport.barWidth * .31, math.min(openY, closeY),
        centerX + viewport.barWidth * .31, math.max(openY + 1, closeY + 1),
      ), candle.positive ? positiveBody : negativeBody);
    }
    if (indicator) {
      final linePath = Path();
      var rollingSum = 0.0;
      for (var i = math.max(0, start - 11); i < start; i++) {
        rollingSum += candles[i].close;
      }
      for (var i = start; i < ending; i++) {
        rollingSum += candles[i].close;
        if (i > start && i >= 12) rollingSum -= candles[i - 12].close;
        final average = rollingSum / math.min(12, i + 1);
        final x = viewport.chartX(
          index: i, candleCount: candles.length, plotWidth: axis);
        if (i == start) { linePath.moveTo(x, y(average)); } else { linePath.lineTo(x, y(average)); }
      }
      canvas.drawPath(linePath, Paint()..color = TradeColors.blue..strokeWidth = 1.6
        ..style = PaintingStyle.stroke);
    }
    for (var index = 0; index < levels.length; index++) {
      final levelY = y(levels[index]);
      final marker = Paint()..color = TradeColors.blue.withValues(alpha: .8)
        ..strokeWidth = selectedLine == index ? 2.4 : 1;
      canvas.drawLine(Offset(0, levelY), Offset(axis, levelY), marker);
    }
    for (var index = 0; index < patterns.length; index++) {
      final drawing = patterns[index];
      // Replay is strictly prefix-only: drawings ending in the future stay
      // invisible, even if their coordinates were created in analysis mode.
      if (!drawing.visibleAt(candles.length)) continue;
      final x1 = viewport.chartX(index: drawing.start.index,
          candleCount: candles.length, plotWidth: axis);
      final x2 = viewport.chartX(index: drawing.end.index,
          candleCount: candles.length, plotWidth: axis);
      final y1 = y(drawing.start.price);
      final y2 = y(drawing.end.price);
      final color = Color(drawing.colorValue);
      final selected = selectedPattern == index;
      final drawingPaint = Paint()
        ..color = color
        ..strokeWidth = drawing.strokeWidth + (selected ? 1 : 0)
        ..style = PaintingStyle.stroke;
      if (drawing.tool == ChartDrawingTool.fibonacci) {
        final fromX = math.min(x1, x2);
        for (final ratio in ChartPattern.fibonacciRatios) {
          final price = drawing.fibonacciPrice(ratio);
          final levelY = y(price);
          canvas.drawLine(Offset(fromX, levelY),
              Offset(axis, levelY), drawingPaint);
          if (drawing.showLabels) {
            _text(canvas, '${(ratio * 100).toStringAsFixed(1)}% ${price.toStringAsFixed(decimals)}',
                Offset(fromX + 5, levelY - 13), color, 10);
          }
        }
      } else {
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), drawingPaint);
      }
      if (selected) {
        final handle = Paint()..color = color;
        canvas.drawCircle(Offset(x1, y1), 4.2, handle);
        canvas.drawCircle(Offset(x2, y2), 4.2, handle);
      }
    }
    _paintShortPositions(canvas, scale, axis, candles.length, decimals);
    canvas.restore();
    // A source-derived last-close marker, not a simulated tick or countdown.
    final lastClose = candles.last.close;
    final lastY = y(lastClose);
    if (lastY >= 0 && lastY <= chartHeight) {
      final lastColor = candles.last.positive
          ? TradeColors.positive : TradeColors.negative;
      final marker = Paint()
        ..color = lastColor
        ..strokeWidth = .9;
      for (var x = 0.0; x < axis; x += 6) {
        canvas.drawLine(Offset(x, lastY),
            Offset(math.min(axis, x + 2.2), lastY), marker);
      }
      final tagY = (lastY - 10).clamp(0, chartHeight - 20).toDouble();
      canvas.drawRect(Rect.fromLTWH(axis, tagY, 61, 20),
          Paint()..color = lastColor);
      _text(canvas, _price(lastClose, decimals),
          Offset(axis + 2, tagY + 3), Colors.white, 10);
    }
    for (var i = 0; i < shortPositions.length; i++) {
      final item = shortPositions[i];
      if (!item.visibleAt(candles.length)) continue;
      _shortAxisTag(canvas, axis, chartHeight, scale.y(item.stop),
          _price(item.stop, decimals), TradeColors.shortLabelRed);
      _shortAxisTag(canvas, axis, chartHeight, scale.y(item.target),
          _price(item.target, decimals), TradeColors.shortLabelBlue);
    }
    if (timestamps.length >= candles.length) {
      // Real UTC dates only. Range uses the time of the originating BID
      // tick, NOT a guessed fixed-duration interval per Range bar.
      for (var tick = 1; tick <= 4; tick++) {
        final x = axis * tick / 5;
        final index = viewport.indexAt(x: x, plotWidth: axis,
            candleCount: candles.length);
        if (index == null) continue;
        final date = DateTime.fromMillisecondsSinceEpoch(timestamps[index], isUtc: true);
        final label = _formatUtc(date);
        _text(canvas, label, Offset(x - 26, chartHeight + 4), text, 9);
      }
    }
    if (crosshair != null) {
      final location = Offset(
        crosshair!.dx.clamp(0, axis).toDouble(),
        crosshair!.dy.clamp(0, chartHeight).toDouble(),
      );
      final crossPaint = Paint()
        ..color = dark ? const Color(0xFF9CA9B9) : const Color(0xFF8692A3)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(location.dx, 0),
          Offset(location.dx, chartHeight), crossPaint);
      canvas.drawLine(Offset(0, location.dy),
          Offset(axis, location.dy), crossPaint);
      final crossPrice = maximum - location.dy / chartHeight * span;
      final markerY = (location.dy - 9).clamp(0, chartHeight - 18).toDouble();
      canvas.drawRect(Rect.fromLTWH(axis, markerY, 61, 18),
          Paint()..color = TradeColors.blue);
      _text(canvas, crossPrice.toStringAsFixed(decimals),
          Offset(axis + 3, markerY + 2), Colors.white, 10);
      if (timestamps.length >= candles.length) {
        final index = viewport.indexAt(
            x: location.dx, plotWidth: axis, candleCount: candles.length);
        if (index != null) {
          final date = DateTime.fromMillisecondsSinceEpoch(timestamps[index], isUtc: true);
          final startX = (location.dx - 37).clamp(0.0, axis - 75).toDouble();
          canvas.drawRect(Rect.fromLTWH(startX, chartHeight, 75, 20),
              Paint()..color = TradeColors.blue);
          _text(canvas, _formatUtc(date),
              Offset(startX + 5, chartHeight + 4), Colors.white, 9);
        }
      }
    }
    // A separate LTR price axis keeps digits and decimal points predictable in RTL.
    if (timestamps.length < candles.length) {
      _text(canvas, 'شموع مدى',
          Offset(axis / 2 - 18, chartHeight + 3), text, 10);
    } else {
      _text(canvas, 'UTC', Offset(3, chartHeight + 4), text, 9);
    }
  }

  static void _text(Canvas canvas, String value, Offset offset, Color color, double size) {
    final painter = TextPainter(
      text: TextSpan(text: value,
          style: TextStyle(fontSize: size, color: color, fontWeight: FontWeight.w500)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, offset);
  }

  void _paintShortPositions(Canvas canvas, ChartPriceScale scale,
      double axis, int count, int decimals) {
    for (var i = 0; i < shortPositions.length; i++) {
      final item = shortPositions[i];
      if (!item.visibleAt(count)) continue;
      final x1 = viewport.chartX(index: item.startIndex,
          candleCount: count, plotWidth: axis);
      final x2 = viewport.chartX(index: item.endIndex,
          candleCount: count, plotWidth: axis);
      final left = math.min(x1, x2);
      final right = math.max(x1, x2);
      final yStop = scale.y(item.stop);
      final yEntry = scale.y(item.entry);
      final yTarget = scale.y(item.target);
      if (right < 0 || left > axis) continue;
      canvas.drawRect(Rect.fromLTRB(left, yStop, right, yEntry),
        Paint()..color = TradeColors.shortStopFill.withValues(alpha: .75));
      canvas.drawRect(Rect.fromLTRB(left, yEntry, right, yTarget),
        Paint()..color = TradeColors.shortTargetFill.withValues(alpha: .75));
      canvas.drawLine(Offset(left, yEntry), Offset(right, yEntry),
          Paint()..color = TradeColors.shortHandle..strokeWidth = 1.4);
      if (selectedShort == i) {
        final outline = Paint()
          ..color = TradeColors.shortHandle
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;
        canvas.drawRect(Rect.fromLTRB(left, yStop, right, yTarget), outline);
        for (final handle in <(Offset, bool)>[
          (Offset(left, yStop), false),
          (Offset(left, yEntry), true),
          (Offset(right, yEntry), false),
          (Offset(left, yTarget), false),
        ]) {
          canvas.drawRRect(RRect.fromRectAndRadius(
              Rect.fromCenter(center: handle.$1, width: 20, height: 20),
              Radius.circular(handle.$2 ? 10 : 5)),
              Paint()..color = Colors.white);
          canvas.drawRRect(RRect.fromRectAndRadius(
              Rect.fromCenter(center: handle.$1, width: 20, height: 20),
              Radius.circular(handle.$2 ? 10 : 5)),
              Paint()..color = TradeColors.shortHandle
                ..style = PaintingStyle.stroke..strokeWidth = 3);
        }
      }
      if (selectedShort != i || !showShortLabels) continue;
      final risk = _price(item.risk, decimals);
      final reward = _price(item.reward, decimals);
      _shortPill(canvas,
          'الإيقاف: \u2066$risk\u2069 (\u2066${item.riskPercent.toStringAsFixed(3)}%\u2069)',
          Offset(axis - 8, yStop - 39), TradeColors.shortLabelRed,
          axis, scale.height);
      _shortPill(canvas,
          'العائد المحتمل: \u2066$reward\u2069   نسبة العائد/المخاطرة: '
          '\u2066${item.rewardRisk.toStringAsFixed(2)}\u2069',
          Offset(axis - 8, yEntry + 20), TradeColors.shortLabelBlue,
          axis, scale.height,
          twoLines: true);
      _shortPill(canvas,
          'الهدف: \u2066$reward\u2069 (\u2066${item.rewardPercent.toStringAsFixed(3)}%\u2069)',
          Offset(axis - 8, yTarget + 19), TradeColors.shortLabelBlue,
          axis, scale.height);
    }
  }

  static void _shortAxisTag(Canvas canvas, double axis, double height,
      double y, String value, Color color) {
    if (y < 0 || y > height) return;
    final top = (y - 9).clamp(0, height - 18).toDouble();
    canvas.drawRect(Rect.fromLTWH(axis, top, 61, 18), Paint()..color = color);
    _text(canvas, value, Offset(axis + 2, top + 2), Colors.white, 10);
  }

  static void _shortPill(Canvas canvas, String value, Offset location,
      Color fill, double axis, double chartHeight, {bool twoLines = false}) {
    final span = TextSpan(text: value, style: const TextStyle(
      fontSize: 11, color: Colors.white, height: 1.18));
    final painter = TextPainter(
      text: span, textDirection: TextDirection.rtl,
      textAlign: TextAlign.center,
      maxLines: twoLines ? 2 : 1,
    )..layout(maxWidth: math.max(40, axis - 16));
    final rectWidth = painter.width + 12;
    final left = (location.dx - rectWidth + 10)
        .clamp(3.0, math.max(3.0, axis - rectWidth - 3)).toDouble();
    final top = location.dy.clamp(1.0,
        math.max(1.0, chartHeight - painter.height - 9)).toDouble();
    canvas.drawRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, rectWidth, painter.height + 8),
      const Radius.circular(4)), Paint()..color = fill);
    painter.paint(canvas, Offset(left + 6, top + 4));
  }

  static String _price(double value, int digits) {
    final parts = value.toStringAsFixed(digits).split('.');
    final integer = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return digits == 0 ? integer : '$integer.${parts.last}';
  }

  static String _formatUtc(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';

  @override
  bool shouldRepaint(covariant _CandleChartPainter old) =>
      old.candles != candles || old.timestamps != timestamps ||
      old.dark != dark || old.viewport != viewport ||
      old.crosshair != crosshair || old.indicator != indicator ||
      !listEquals(old.levels, levels) ||
      !listEquals(old.patterns, patterns) ||
      !listEquals(old.shortPositions, shortPositions) ||
      old.selectedLine != selectedLine || old.selectedPattern != selectedPattern ||
      old.selectedShort != selectedShort || old.showShortLabels != showShortLabels;
}
