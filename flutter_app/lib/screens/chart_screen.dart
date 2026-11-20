import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../chart/chart_annotations.dart';
import '../chart/chart_line_geometry.dart';
import '../chart/chart_candle_wicks.dart';
import '../chart/chart_short_position.dart';
import '../chart/chart_price_rectangle.dart';
import '../chart/chart_type_sheet.dart';
import '../chart/analysis_hub_sheet.dart';
import '../chart/drawing_tools_sheet.dart';
import '../chart/chart_viewport.dart';
import '../chart/chart_price_scale_cache.dart';
import '../chart/chart_ohlc_inspector.dart';
import '../chart/chart_crosshair_time_label.dart';
import '../chart/chart_quick_actions.dart';
import '../chart/chart_frame_profiler.dart';
import '../chart/chart_text_layout_cache.dart';
import '../chart/chart_feed_health.dart';
import '../chart/chart_panel_settings.dart';
import '../chart/chart_panel_settings_page.dart';
import '../chart/chart_scale_settings.dart';
import '../chart/chart_scale_settings_page.dart';
import '../chart/chart_symbol_settings.dart';
import '../chart/chart_symbol_settings_page.dart';
import '../chart/chart_axis_source_labels.dart';
import '../chart/chart_visible_sma.dart';
import '../chart/chart_axis_ticks.dart';
import '../chart/chart_price_text_formatter.dart';
import '../chart/chart_time_axis_label_layout.dart';
import '../chart/chart_historical_time_zone.dart';
import '../chart/candle_prefix.dart';
import '../chart/chart_heikin_ashi.dart';
import '../replay/replay_playback_speed.dart';
import '../replay/replay_mobile_controls.dart';
import '../replay/replay_start_overlay.dart';
import '../replay/replay_start_resolver.dart';
import '../replay/replay_date_time_resolver.dart';
import '../replay/replay_training_session.dart';
import '../replay/replay_training_order_dialog.dart';
import '../replay/replay_training_archive.dart';
import '../replay/replay_trade_overlay.dart';
import '../data/range_bar_timeline.dart';
import '../data/range_startup_loader.dart';
import '../data/ctrader_older_candle_pager.dart';
import '../data/older_candle_prepend.dart';
import '../data/verified_market_history_snapshot.dart';
import '../data/range_history_fill_policy.dart';
import '../data/range_older_page.dart';
import '../data/range_older_page_scanner.dart';
import '../data/range_tick_store.dart';
import '../data/tradelab_data.dart';
import '../data/market_api.dart';
import '../data/chart_timeframe_catalog.dart';
import '../data/market_candle_store.dart';
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
  const ChartScreen({required this.controller, this.journal,
    this.onOpenAccount, this.requestedSymbolCode = 'XAUUSD',
    this.active = true, this.focusMode = false,
    this.onToggleFocusMode, super.key});
  final MarketController controller;
  final PaperJournalController? journal;
  final VoidCallback? onOpenAccount;
  /// Navigation from Markets requests this verified symbol; chart stays
  /// mounted in IndexedStack and must invalidate the prior symbol's history.
  final String requestedSymbolCode;
  /// False while kept alive but hidden inside the bottom-tab IndexedStack.
  final bool active;
  /// Expand the same chart viewport, never remount or reload source history.
  final bool focusMode;
  final VoidCallback? onToggleFocusMode;

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen>
    with SingleTickerProviderStateMixin {
  // Normal pan/fling and crosshair frames invalidate only the candle canvas.
  final ValueNotifier<int> _chartRepaint = ValueNotifier<int>(0);
  // Rectangle drags repaint an independent layer, not all candles and UI.
  final ValueNotifier<int> _rectangleRepaint = ValueNotifier<int>(0);
  late final Listenable _rectanglePaintSignals = Listenable.merge([
    _chartRepaint, _rectangleRepaint,
  ]);
  final ChartTextLayoutCache _chartTextCache = ChartTextLayoutCache();
  // Shared by candle paint, rectangles, Replay price levels and touch hits.
  // Exactly one immutable auto-scale per source/viewport/plot configuration.
  final ChartPriceScaleCache _autoPriceScaleCache = ChartPriceScaleCache();

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
  final RangeAutoFillRevisionGate _rangeAutoFillRevisionGate =
      RangeAutoFillRevisionGate();
  bool get _rangeAutoFilling =>
      _rangeAutoFillRevisionGate.isActiveFor(_loadRevision);
  bool _historyExhausted = false;
  int? _olderCursorMs;
  String? _olderLoadError;
  String? _loadError;
  final ChartHeikinAshiCache _heikinCache = ChartHeikinAshiCache();
  bool _linkedBefore = false;
  String? _accountBefore;
  String _symbol = 'XAUUSD';
  String _timeframe = '1m';
  ChartMode _mode = ChartMode.candles;
  // A 1000-point default often leaves only a single verified BID Range bar
  // in the available tick window. Start at a visible, selectable 25 points;
  // every larger/smaller cTrader preset remains available to the user.
  int _rangeTicks = 25;
  bool _replay = false;
  bool _replaySelectingStart = false;
  bool _replayDraggingStart = false;
  int _replayCandidateIndex = 0;
  int _replayInitialCount = 1;
  // Keep the candle area clear until the user explicitly requests tools.
  bool _replayShowTradingButtons = false;
  bool _replayShowDrawingTools = false;
  bool _replayAutoStep = true;
  bool _drawing = false;
  bool _drawingsVisible = true;
  bool _drawingsLocked = false;
  bool _eraserMode = false;
  bool _rulerMode = false;
  bool _continueDrawing = true;
  ChartAnchor? _measureStart;
  ChartDrawingTool _drawingTool = ChartDrawingTool.horizontal;
  // The catalog owns visual selection; chart coordinates and history do not
  // change until the user deliberately chooses an implemented tool.
  final Set<DrawingCatalogKind> _favoriteDrawingTools = {
    DrawingCatalogKind.fibonacciRetracement,
    DrawingCatalogKind.trendLine,
    DrawingCatalogKind.horizontal,
    DrawingCatalogKind.horizontalRay,
    DrawingCatalogKind.verticalLine,
    DrawingCatalogKind.shortPosition,
    DrawingCatalogKind.longPosition,
    DrawingCatalogKind.fixedVolumeProfile,
    DrawingCatalogKind.ellipse,
    DrawingCatalogKind.priceRectangle,
  };
  static const _drawingFavoritesKey = 'tradelab-drawing-favorites-v1';
  static const _drawingFavoritesVisibleKey =
      'tradelab-drawing-favorites-visible-v1';
  final _drawingFavoritesStorage = const FlutterSecureStorage();
  bool _showFavoriteShortcuts = true;
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
  // Keep the newest verified bar close to the price scale on mobile.
  // Default zoom is legible; pinch and pan remain fully user-controlled.
  ChartViewport _viewport = const ChartViewport(
    barWidth: 10, scrollBars: 0, rightMarginBars: 4);
  // A manually scaled price ruler affects drawings and candles equally.
  // Keep its scope per source, account, timeframe and Range configuration.
  ChartPriceScale? _manualPriceScale;
  String? _manualPriceScaleKey;
  bool _draggingPriceAxis = false;
  bool _draggingTimeAxis = false;
  double _doubleTapChartX = 0;
  String get _currentPriceScaleKey =>
      '${widget.controller.accountId}|${_selectedSymbol.source.name}|'
      '$_symbol|$_timeframe|${_mode.name}|$_rangeTicks|'
      '${_replay ? 'replay' : _replaySelectingStart ? 'select' : 'live'}';
  bool get _priceScaleManual =>
      _manualPriceScale != null &&
      _manualPriceScaleKey == _currentPriceScaleKey;
  ChartPanelSettings _panelSettings = const ChartPanelSettings();
  bool _panelSettingsOpen = false;
  bool _scaleSettingsOpen = false;
  ChartScaleSettings _scaleSettings = const ChartScaleSettings();
  bool _symbolSettingsOpen = false;
  bool _symbolSettingsReturnToPanel = false;
  ChartSymbolSettings _symbolSettings = const ChartSymbolSettings();
  bool _panelChartTouched = false;
  static const _panelSettingsKey = 'tradelab-chart-panel-settings-v1';
  static const _scaleSettingsKey = 'tradelab-chart-scale-settings-v1';
  static const _symbolSettingsKey = 'tradelab-chart-symbol-settings-v1';
  final _panelSettingsStorage = const FlutterSecureStorage();
  ChartTouchGesture _touchGesture = ChartTouchGesture();
  // Flutter's scale recognizer starts only after the finger passes touch
  // slop. Preserve where the user's FIRST finger actually landed so a guide
  // with a 17/18dp hit target remains draggable after that delay.
  int? _firstChartPointer;
  Offset? _firstChartDown;

  @visibleForTesting
  ({bool draggingLine, bool draggingPattern, bool draggingRectangle,
    int levels, int patterns, int? selectedLine, int? selectedPattern,
    double? levelValue, ChartPattern? patternValue})
      get debugGuideDragSelection => (
        draggingLine: _draggingLine,
        draggingPattern: _draggingPattern,
        draggingRectangle: _draggingRectangle,
        levels: _levels.length,
        patterns: _patterns.length,
        selectedLine: _selectedLine,
        selectedPattern: _selectedPattern,
        levelValue: _selectedLine != null &&
            _selectedLine! >= 0 && _selectedLine! < _levels.length
            ? _levels[_selectedLine!] : null,
        patternValue: _selectedPattern != null &&
            _selectedPattern! >= 0 && _selectedPattern! < _patterns.length
            ? _patterns[_selectedPattern!] : null,
      );
  late final AnimationController _momentum;
  double _previousMomentumX = 0;
  double _momentumPlotWidth = 1;
  double _gestureFocalX = 0;
  Offset? _crosshair;
  Timer? _replayTimer;
  ReplayPlaybackSpeed _replaySpeed = ReplayPlaybackSpeed.normal;
  final ReplayTrainingSession _training = ReplayTrainingSession();
  final ChartFrameProfiler _frameProfiler = ChartFrameProfiler();
  String _trainingSessionId = '';
  String _trainingSourceKey = '';
  bool _trainingEverTraded = false;
  Timer? _trainingSaveDebounce;
  Future<void> _trainingSaveQueue = Future<void>.value();
  Timer? _closedCandleTimer;
  bool _refreshingClosedCandles = false;
  MarketQuote? _lastObservedQuote;
  bool _pollingSelectedQuote = false;
  int _lastQuoteRequestAtMs = 0;
  bool _retryingEmptyHistory = false;
  int _lastEmptyHistoryAttemptMs = 0;
  bool _playing = false;
  final List<double> _levels = [];
  final List<ChartPattern> _patterns = [];
  final List<_DrawingSnapshot> _lineUndo = [];
  final List<_DrawingSnapshot> _lineRedo = [];
  List<double> _analysisLevels = [];
  List<ChartPattern> _analysisPatterns = [];
  ChartAnchor? _pendingAnchor;
  ChartAnchor? _secondChannelAnchor;
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
    final quote = widget.controller.recentQuoteFor(_selectedSymbol);
    return ChartFeedHealth.closedCandlesLagging(
      latestClosedOpenMs: _actualTimestamps.last,
      timeframe: _timeframe,
      nowMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      freshQuoteTimestampMs: quote?.timestampMs,
    );
  }

  String get _marketEvidenceLabel {
    if (_replay) {
      // This status must describe the last REVEALED source candle, not a
      // contemporary live quote or an unrevealed future market timestamp.
      final times = _replaySourceTimestamps;
      if (_visibleThrough < 1 || _visibleThrough > times.length) {
        return 'Replay تاريخي · لم تتوفر شمعة مكشوفة موثقة';
      }
      final source = _selectedSymbol.source == TradeSource.ctrader
          ? 'cTrader' : 'Binance';
      return 'Replay تاريخي · $source · $_symbol · آخر شمعة مكشوفة '
          '${_utcMinuteLabel(times[_visibleThrough - 1])} · '
          'أسعار السوق المباشر مخفية';
    }
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
        final quote = widget.controller.recentQuoteFor(_selectedSymbol);
        return 'شموع cTrader · $broker ($mode) · آخر شمعة مغلقة '
            '${_utcMinuteLabel(_actualTimestamps.last)}'
            '${quote == null ? '' : ' · سعر BID/ASK عند ${_utcMinuteLabel(quote.timestampMs)}'}'
            '${_ctraderTimeCandlesStale ? ' · الشموع متأخرة' : ''}';
      }
      return 'لم تصل شموع موثقة من cTrader لهذا الرمز';
    }
    return 'شموع Binance · آخر بيانات مصدر موثق';
  }
  int get _totalBars {
    if (!_liveRequested) return 0;
    // The last Range bar is still forming; never count it as a Replay
    // entry/exit candle. The live chart can keep drawing it separately.
    return _mode == ChartMode.range
        ? math.max(0, _actualRange.length - 1)
        : _actualBars.length;
  }

  @override
  void initState() {
    super.initState();
    if (tradeSymbols.any((item) => item.code == widget.requestedSymbolCode)) {
      _symbol = widget.requestedSymbolCode;
    }
    _frameProfiler.attach();
    unawaited(_loadDrawingFavorites());
    unawaited(_loadPanelSettings());
    unawaited(_loadScaleSettings());
    unawaited(_loadSymbolSettings());
    _momentum = AnimationController.unbounded(vsync: this)
      ..addListener(_tickMomentum)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed) {
          // Natural friction finish is a real user-visible end. Never keep
          // sampling idle toolbar frames after kinetic scrolling stops.
          _frameProfiler.endInteraction();
        }
      });
    _linkedBefore = widget.controller.ctraderConnected;
    _accountBefore = widget.controller.accountId;
    widget.controller.addListener(_onMarketUpdate);
    _lastObservedQuote = widget.controller.recentQuoteFor(_selectedSymbol);
    // Poll only broker-closed candles. Never update Replay or request
    // synthetic OHLC from non-cTrader sources.
    _closedCandleTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (!widget.active) return;
        unawaited(_refreshClosedCTraderCandles());
        unawaited(_retryEmptyCTraderHistory());
        unawaited(_refreshSelectedCTraderQuote());
        // Quote labels must disappear after their 90-second validity
        // expires, including when the chart is in Range mode.
        _refreshDisplayedQuote();
      },
    );
    // Binance does not require a cTrader session. Load its chart immediately
    // when selected, even on a device that has never linked a broker.
    if (widget.active && _liveRequested) Future.microtask(_loadRealHistory);
    if (widget.active && _selectedSymbol.source == TradeSource.ctrader) {
      Future.microtask(_refreshSelectedCTraderQuote);
    }
  }

  @override
  void didUpdateWidget(covariant ChartScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestedSymbolCode != widget.requestedSymbolCode &&
        widget.requestedSymbolCode != _symbol) {
      final targets = tradeSymbols.where(
          (item) => item.code == widget.requestedSymbolCode);
      if (targets.isNotEmpty) {
        _changeSymbol(targets.first);
        return;
      }
    }
    if (!oldWidget.active && widget.active) {
      // The chart was hidden behind another tab. Refresh only the selected
      // verified symbol, never fetch quote data while offscreen.
      _lastObservedQuote = widget.controller.recentQuoteFor(_selectedSymbol);
      if (_liveRequested && !_loading &&
          _actualBars.isEmpty && _actualRange.isEmpty) {
        Future.microtask(_loadRealHistory);
      }
      Future.microtask(_refreshSelectedCTraderQuote);
    }
  }

  Future<void> _loadDrawingFavorites() async {
    try {
      final stored = await _drawingFavoritesStorage.read(
          key: _drawingFavoritesKey);
      final savedVisibility = await _drawingFavoritesStorage.read(
          key: _drawingFavoritesVisibleKey);
      if (!mounted) return;
      setState(() {
        if (stored != null) {
          _favoriteDrawingTools
            ..clear()
            ..addAll(DrawingFavoritesCodec.decode(stored));
        }
        if (savedVisibility != null) {
          _showFavoriteShortcuts = savedVisibility == 'true';
        }
      });
    } catch (_) {
      // Drawing access must remain usable on devices without a secure store.
    }
  }

  Future<void> _persistDrawingFavorites() async {
    try {
      await _drawingFavoritesStorage.write(
        key: _drawingFavoritesKey,
        value: DrawingFavoritesCodec.encode(_favoriteDrawingTools),
      );
    } catch (_) {
      // A storage error must not interrupt chart gestures or drawing selection.
    }
  }

  Future<void> _persistDrawingFavoriteVisibility() async {
    try {
      await _drawingFavoritesStorage.write(
        key: _drawingFavoritesVisibleKey,
        value: _showFavoriteShortcuts.toString(),
      );
    } catch (_) {
      // The visible state remains effective for the active chart session.
    }
  }

  Future<void> _loadPanelSettings() async {
    try {
      final saved = await _panelSettingsStorage.read(key: _panelSettingsKey);
      if (saved == null || !mounted) return;
      final loaded = ChartPanelSettings.decode(saved);
      setState(() {
        _panelSettings = loaded;
        _viewport = _viewport.withRightMarginBars(loaded.rightMarginBars.toDouble());
      });
    } catch (_) {
      // Keep readable defaults when secure storage is unavailable.
    }
  }

  Future<void> _savePanelSettings(ChartPanelSettings settings) async {
    try {
      await _panelSettingsStorage.write(
        key: _panelSettingsKey, value: settings.encode());
    } catch (_) {
      // The chart still uses the committed settings for this session.
    }
  }

  Future<void> _loadScaleSettings() async {
    try {
      final stored = await _panelSettingsStorage.read(key: _scaleSettingsKey);
      if (stored != null && mounted) {
        setState(() => _scaleSettings = ChartScaleSettings.decode(stored));
      }
    } catch (_) {
      // Invalid/older local preferences must never block a real chart.
    }
  }

  Future<void> _saveScaleSettings(ChartScaleSettings settings) async {
    try {
      await _panelSettingsStorage.write(
        key: _scaleSettingsKey, value: settings.encode());
    } catch (_) {
      // Keep committed in-memory preferences if the device store is locked.
    }
  }

  Future<void> _loadSymbolSettings() async {
    try {
      final stored = await _panelSettingsStorage.read(key: _symbolSettingsKey);
      if (stored != null && mounted) {
        setState(() => _symbolSettings = ChartSymbolSettings.decode(stored));
      }
    } catch (_) {
      // Preserve a functioning chart if local device storage is unavailable.
    }
  }

  Future<void> _saveSymbolSettings(ChartSymbolSettings settings) async {
    try {
      await _panelSettingsStorage.write(
        key: _symbolSettingsKey, value: settings.encode());
    } catch (_) {
      // A committed in-memory setting remains valid for this chart session.
    }
  }

  ChartViewport _freshViewport() => ChartViewport(
    rightMarginBars: _panelSettings.rightMarginBars.toDouble());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _stopMomentum();
  }

  void _stopMomentum() {
    // A new touch, account change, Replay transition or modal action can
    // cancel friction before its natural AnimationStatus.completed event.
    // End that exact cohort first, so future idle frames cannot be
    // mislabelled as kinetic chart motion.
    _frameProfiler.endInteraction();
    _momentum.stop();
  }

  void _tickMomentum() {
    if (!mounted || _loading) {
      _stopMomentum();
      return;
    }
    final deltaX = _momentum.value - _previousMomentumX;
    _previousMomentumX = _momentum.value;
    if (deltaX.abs() < 0.000001) return;
    final count = _displayCandles.length;
    if (count < 2) {
      _stopMomentum();
      return;
    }
    final next = _viewport.pan(
        deltaX: deltaX,
        plotWidth: _momentumPlotWidth,
        candleCount: count);
    if (next == _viewport) {
      // The chart reached its historical or future-whitespace bound.
      _stopMomentum();
      return;
    }
    if (chartCanUsePaintOnlyViewportUpdate(
      selectingReplayStart: _replaySelectingStart,
      crosshairVisible: _crosshair != null,
      movingDrawing: false,
      visiblePriceRectangles: _drawingsVisible && _rectangles.isNotEmpty,
      priceRectanglesFollowViewport: true,
      replayTradeLevelsVisible: _replay && _training.trades.isNotEmpty,
      replayTradeLevelsFollowViewport: true,
    )) {
      _viewport = next;
      _chartRepaint.value++;
    } else {
      // Rebuild overlays with snapshot-based viewport positions as well.
      setState(() => _viewport = next);
    }
    _prefetchOlderAtEdge(_momentumPlotWidth, count);
  }

  void _startMomentum(double horizontalVelocity, double plotWidth) {
    _stopMomentum();
    _frameProfiler.beginInteraction(
      interaction: ChartFrameInteraction.momentum,
      chartMode: _mode.name,
      replay: _replay || _replaySelectingStart,
      displayedCandles: _displayCandles.length,
      rangeBidTicks:
          _mode == ChartMode.range ? _rangeHistoryTicks.length : 0,
    );
    _previousMomentumX = 0;
    _momentumPlotWidth = plotWidth;
    // Pixels/second, signed like the finger. The friction simulation is
    // cancelable by the next gesture; price data never changes with motion.
    _momentum.animateWith(FrictionSimulation(
        0.08, 0, horizontalVelocity.clamp(-5000.0, 5000.0).toDouble()));
  }

  void _prefetchOlderAtEdge(double plotWidth, int count) {
    if (!_liveRequested || _loading || _olderLoading ||
        _rangeAutoFilling || _historyExhausted ||
        (_mode == ChartMode.range &&
            _rangeHistoryTicks.length >= RangeOlderPage.maxLoadedTicks) ||
        _olderLoadError != null || count <= 0 ||
        _viewport.scrollBars <= count - plotWidth / _viewport.barWidth - 25) {
      return;
    }
    if (_mode == ChartMode.range) {
      // Rebuilding Range from an earlier BID origin changes all bar indices.
      // Do not silently relocate a practice entry while a trade is recorded.
      if (_replay && _training.trades.isNotEmpty) return;
      if (_rangeHistoryTicks.isNotEmpty) {
        unawaited(_loadOlderRangeHistory());
      }
    } else if (_actualBars.isNotEmpty) {
      unawaited(_loadOlderHistory());
    }
  }

  /// cTrader price refresh is read-only. No broker trades, artificial bars
  /// or price interpolation are created. Inactive tabs issue no requests.
  Future<void> _refreshSelectedCTraderQuote() async {
    if (!mounted || !widget.active || _pollingSelectedQuote || _replay ||
        _selectedSymbol.source != TradeSource.ctrader ||
        !widget.controller.ctraderConnected) {
      return;
    }
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final cached = widget.controller.recentQuoteFor(_selectedSymbol);
    if (!ChartFeedHealth.shouldRequestQuote(
      nowMs: nowMs,
      lastAttemptMs: _lastQuoteRequestAtMs,
      freshQuoteTimestampMs: cached?.timestampMs,
    )) {
      return;
    }
    _pollingSelectedQuote = true;
    _lastQuoteRequestAtMs = nowMs;
    final symbol = _selectedSymbol;
    try {
      // paperQuote is a source-only BID/ASK GET; it neither places orders
      // nor writes to the local trading journal.
      await widget.controller.paperQuote(symbol);
    } on MarketDataException {
      // Keep the previous evidence/error state; never fabricate a price.
    } catch (_) {
      // Recheck on the next throttled interval after a transient failure.
    } finally {
      _pollingSelectedQuote = false;
    }
  }

  void _refreshDisplayedQuote() {
    final latest = widget.controller.recentQuoteFor(_selectedSymbol);
    final previous = _lastObservedQuote;
    if (!ChartFeedHealth.quoteChanged(previous, latest)) return;
    _lastObservedQuote = latest;
    if (!mounted || !widget.active || _replay) return;
    // Verified BID/ASK movement normally requires a repaint only. Avoid
    // rebuilding the chart controls, drawing tools and history on each tick.
    _chartRepaint.value++;
    if (_selectedSymbol.source == TradeSource.ctrader &&
        _mode != ChartMode.range && _actualTimestamps.isNotEmpty &&
        ChartFeedHealth.quoteHeaderEvidenceChanged(
          previous: previous,
          next: latest,
          lastClosedOpenMs: _actualTimestamps.last,
          timeframe: _timeframe,
          nowMs: DateTime.now().toUtc().millisecondsSinceEpoch,
        )) {
      // Update source minute and stale-candle warnings in the header.
      setState(() {});
    }
  }

  void _onMarketUpdate() {
    final linked = widget.controller.ctraderConnected;
    final changedAccount = _accountBefore != widget.controller.accountId;
    if (_linkedBefore != linked || changedAccount) {
      _stopMomentum();
      _rangeBidCache.clear();
      _rangeBidCachedAt.clear();
      _rangePointCache.clear();
      _linkedBefore = linked;
      _accountBefore = widget.controller.accountId;
      _lastQuoteRequestAtMs = 0;
      // Never carry another broker account's drawings into this account.
      _resetDrawingObjects();
      if (linked && widget.active &&
          _selectedSymbol.source == TradeSource.ctrader) {
        _loadRealHistory();
        unawaited(_refreshSelectedCTraderQuote());
      }
      if ((!linked || !widget.active) &&
          _selectedSymbol.source == TradeSource.ctrader) {
        // The chart is retained in IndexedStack while hidden. An account
        // change must invalidate old account candles and pending futures even
        // if the new account remains connected. When the tab is reopened,
        // didUpdateWidget() will fetch the new account's verified history.
        _loadRevision++;
        _recordTraining();
        _stopPlayback();
        _replay = false;
        _replaySelectingStart = false;
        _replayDraggingStart = false;
        _training.clear();
        _trainingEverTraded = false;
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
    // MarketController can publish a new BID/ASK while the broker link and
    // selected account stay unchanged. Redraw verified price labels then.
    _refreshDisplayedQuote();
  }

  Future<void> _loadRealHistory() async {
    if (_replay) _recordTraining();
    _stopMomentum();
    final revision = ++_loadRevision;
    if (!mounted) return;
    final sourceSymbol = _selectedSymbol;
    final sourceTimeframe = _timeframe;
    final sourceAccount = sourceSymbol.source == TradeSource.ctrader
        ? widget.controller.accountId : null;
    if (sourceSymbol.source == TradeSource.ctrader &&
        _mode != ChartMode.range) {
      // A failed *initial* fetch will be retried after two minutes, not on
      // every 30-second timer or every chart rebuild.
      _lastEmptyHistoryAttemptMs =
          DateTime.now().toUtc().millisecondsSinceEpoch;
    }
    setState(() {
      _stopPlayback();
      if (_replay) {
        _levels..clear()..addAll(_analysisLevels);
        _patterns..clear()..addAll(_analysisPatterns);
        _shortPositions..clear()..addAll(_analysisShortPositions);
        _rectangles..clear()..addAll(_analysisRectangles);
      }
      _replay = false;
      _replaySelectingStart = false;
      _replayDraggingStart = false;
      _training.clear();
      _trainingEverTraded = false;
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
      _secondChannelAnchor = null;
      _selectedPattern = null;
    });
    try {
      if (_mode == ChartMode.range) {
        if (!_rangeSourceSupported) {
          throw const MarketDataException('شموع المدى الحقيقية متاحة حاليًا لرموز cTrader فقط؛ لا تتوفر تيكات Binance لهذا الوضع.');
        }
        final account = widget.controller.accountId;
        if (account == null) {
          throw const MarketDataException(
              'لا يوجد حساب cTrader محدد. افتح الحساب وأعد الاتصال.');
        }
        final symbol = _selectedSymbol;
        final cacheKey = '$account:${symbol.code}';
        var point = _rangePointCache[cacheKey];
        if (point == null) {
          point = await widget.controller.pointSize(symbol);
          if (revision != _loadRevision || !mounted) return;
          if (!point.isFinite || point <= 0) {
            throw const MarketDataException(
                'دقة تسعير رمز cTrader غير صالحة لإنشاء شموع المدى.');
          }
          _rangePointCache[cacheKey] = point;
        }
        final windowEnd = DateTime.now().toUtc().millisecondsSinceEpoch;
        final pendingArchivePages = <int>{};
        bool isCurrentRange() => mounted && revision == _loadRevision &&
            widget.controller.accountId == account &&
            _selectedSymbol.code == symbol.code &&
            _selectedSymbol.source == symbol.source &&
            _mode == ChartMode.range;
        final snapshot = await RangeStartupLoader.load(
          endMs: windowEnd,
          isCurrent: isCurrentRange,
          priceDistance: _rangeTicks * point,
          getTicks: (fromMs, toMs) async {
            if (!isCurrentRange()) {
              throw const MarketDataException('تغير الشارت أثناء تحميل تيكات المدى.');
            }
            List<MarketTick>? verified;
            try {
              verified = await RangeTickStore.readCoveredInterval(
                account, symbol.code, fromMs: fromMs, toMs: toMs);
            } catch (_) {
              // Missing or damaged archive is not a market data source.
            }
            if (verified != null) return verified;
            final fetched = await widget.controller.rangeTicksBetween(
              symbol, fromMs: fromMs, toMs: toMs);
            if (!isCurrentRange()) {
              throw const MarketDataException('تغير الحساب أثناء تحميل المدى.');
            }
            // The loader must validate this exact inclusive window
            // (including empty broker responses) before persistence.
            pendingArchivePages.add(fromMs);
            return fetched;
          },
          onVerifiedPage: (fromMs, toMs, page) {
            if (!isCurrentRange() ||
                !pendingArchivePages.remove(fromMs)) return;
            unawaited(RangeTickStore.archiveVerifiedWindow(
              account, symbol.code, page,
              fromMs: fromMs, toMs: toMs,
            ).then<void>((_) {}, onError: (Object _, StackTrace __) {}));
          },
          onSnapshot: (page) async {
            if (!isCurrentRange()) return;
            // Display authentic BID Range bars as soon as a short interval
            // completes. Continue widening history only if too few bars
            // formed to make the chart useful.
            setState(() {
              _rangeHistoryTicks = page.ticks;
              _rangeOlderCursorMs = page.fromMs - 1;
              _actualRange = page.timeline.bars;
              _rangeBarEndTickIndices = page.timeline.endTickIndices;
              _rangeBarTimestamps = page.timeline.endTimestamps;
            });
          },
        );
        if (revision != _loadRevision || !mounted) return;
        if (snapshot == null) {
          throw const MarketDataException(
              'لم تصل تيكات BID موثقة من cTrader خلال آخر 6 أيام. '
              'تحقق من اتصال الحساب وتوفر تاريخ التيكات لدى الوسيط.');
        }
      } else {
        // Render verified, account-scoped history immediately on a return to
        // this symbol. A recently synchronized cache needs no new OHLC call.
        List<MarketBar> cached = const [];
        var fresh = false;
        try {
          cached = await MarketCandleStore.read(
              sourceSymbol, sourceTimeframe, sourceAccount);
          fresh = cached.isNotEmpty && await MarketCandleStore.isFresh(
              sourceSymbol, sourceTimeframe, sourceAccount);
        } catch (_) {
          // SQLite can be unavailable in some test hosts. The verified source
          // remains authoritative, never an invented fallback.
        }
        if (revision != _loadRevision || !mounted) return;
        if (cached.isNotEmpty) {
          // The source cache has already been SHA/SQLite validated by its
          // reader. A large mapped candle/timestamp snapshot is built on an
          // isolate, never synchronously in the chart's gesture event loop.
          final cachedSnapshot =
              await VerifiedMarketHistorySnapshot.fromVerifiedAsync(cached);
          if (revision != _loadRevision || !mounted ||
              _selectedSymbol.code != sourceSymbol.code ||
              _timeframe != sourceTimeframe ||
              (sourceSymbol.source == TradeSource.ctrader &&
                  widget.controller.accountId != sourceAccount)) return;
          setState(() {
            _actualBars = cachedSnapshot.bars;
            _actualCandles = cachedSnapshot.candles;
            _actualTimestamps = cachedSnapshot.timestamps;
            _olderCursorMs = cachedSnapshot.bars.first.timestamp;
          });
        }
        if (fresh) return;
        final bars = await widget.controller.history(sourceSymbol, sourceTimeframe);
        if (revision != _loadRevision || !mounted) return;
        // Preserve the verified conflict-detecting merge, but move its
        // large source/axis allocations off the UI isolate. Small pages
        // remain synchronous to avoid unnecessary isolate setup overhead.
        final mergedSnapshot =
            await VerifiedMarketHistorySnapshot.mergeVerifiedAsync(
              cached: cached, fetched: bars);
        if (revision != _loadRevision || !mounted ||
            _selectedSymbol.code != sourceSymbol.code ||
            _timeframe != sourceTimeframe ||
            (sourceSymbol.source == TradeSource.ctrader &&
                widget.controller.accountId != sourceAccount)) return;
        _actualBars = mergedSnapshot.bars;
        _actualCandles = mergedSnapshot.candles;
        _actualTimestamps = mergedSnapshot.timestamps;
        if (mergedSnapshot.bars.isNotEmpty) {
          _olderCursorMs = mergedSnapshot.bars.first.timestamp;
        }
        if (bars.isNotEmpty) {
          unawaited(MarketCandleStore.archive(sourceSymbol, sourceTimeframe,
              sourceAccount, bars, markFresh: true).catchError((Object _) {}));
        }
      }
      if (revision == _loadRevision && _totalBars == 0) {
        // A forming Range bar with genuine BID ticks is not a terminal
        // failure: older real ticks may close additional bars. Let the
        // bounded background backfill search verified earlier intervals.
        if (_mode != ChartMode.range || _rangeHistoryTicks.isEmpty) {
          _loadError =
              'لم يُرجع المصدر شموعًا مكتملة لهذه الفترة. جرّب تحديث البيانات أو اختيار إطار آخر.';
        }
      }
    } on MarketDataException catch (e) {
      if (revision == _loadRevision) _loadError = e.message;
    } catch (_) {
      if (revision == _loadRevision) _loadError = 'تعذر تحميل بيانات السوق. أعد المحاولة.';
    } finally {
      if (revision == _loadRevision && mounted) {
        setState(() => _loading = false);
        // First authentic ticks appear without waiting for deep history.
        // Then fill the screen progressively instead of freezing after 12
        // closed Range bars. This never changes prices or tick timestamps.
        if (_mode == ChartMode.range && _rangeHistoryTicks.isNotEmpty &&
            widget.active && !_replay && !_replaySelectingStart) {
          unawaited(_autoFillRangeHistory(revision));
        }
      }
    }
  }

  /// Recover a first-load cTrader OHLC failure WITHOUT clearing drawings,
  /// Replay history, user panning/zoom, or replacing bars with fabricated
  /// prices. Successful results are the same source-validated MarketBars used
  /// by the original history request. Range BID ticks use a separate path.
  Future<void> _retryEmptyCTraderHistory() async {
    if (!mounted || !widget.active || !_liveRequested ||
        _selectedSymbol.source != TradeSource.ctrader ||
        _mode == ChartMode.range || _replay || _loading ||
        _olderLoading || _refreshingClosedCandles ||
        _retryingEmptyHistory || _actualBars.isNotEmpty ||
        widget.controller.accountId == null) {
      return;
    }
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    if (!ChartFeedHealth.shouldRetryEmptyHistory(
      nowMs: nowMs, lastAttemptMs: _lastEmptyHistoryAttemptMs,
    )) {
      return;
    }

    final revision = _loadRevision;
    final symbol = _selectedSymbol;
    final frame = _timeframe;
    final account = widget.controller.accountId;
    _retryingEmptyHistory = true;
    _lastEmptyHistoryAttemptMs = nowMs;
    try {
      final bars = await widget.controller.history(symbol, frame);
      if (!mounted || !widget.active || revision != _loadRevision ||
          _replay || _mode == ChartMode.range ||
          _selectedSymbol.code != symbol.code ||
          _timeframe != frame ||
          widget.controller.accountId != account ||
          _actualBars.isNotEmpty) {
        return;
      }
      if (bars.isEmpty) {
        // A valid empty broker response does not justify a fabricated bar.
        return;
      }
      // The provider already validated order, OHLC and closed-bar boundaries.
      // Never sort or reconstruct the original broker data on this path.
      setState(() {
        _actualBars = bars;
        _actualCandles = bars.map((bar) => bar.candle).toList(growable: false);
        _actualTimestamps =
            bars.map((bar) => bar.timestamp).toList(growable: false);
        _olderCursorMs = bars.first.timestamp;
        _loadError = null;
      });
      unawaited(MarketCandleStore.archive(symbol, frame, account, bars,
          markFresh: true).catchError((Object _) {}));
    } on MarketDataException {
      // Retain the current error display. The next attempt is throttled.
    } catch (_) {
      // A transient provider/storage failure is not market evidence.
    } finally {
      _retryingEmptyHistory = false;
    }
  }

  Future<void> _refreshClosedCTraderCandles() async {
    if (!mounted || !widget.active || _refreshingClosedCandles ||
        _loading || _olderLoading ||
        _replay || _draggingLine || _draggingPattern ||
        !_liveRequested ||
        _selectedSymbol.source != TradeSource.ctrader ||
        _mode == ChartMode.range || _actualBars.isEmpty) return;
    final revision = _loadRevision;
    final symbol = _selectedSymbol;
    final timeframe = _timeframe;
    final account = widget.controller.accountId;
    final lastTimestamp = _actualBars.last.timestamp;
    _refreshingClosedCandles = true;
    try {
      final recent = await widget.controller.closedCandlesSince(
          symbol, timeframe, lastTimestamp);
      if (!mounted || revision != _loadRevision || _replay ||
          _selectedSymbol.code != symbol.code || _timeframe != timeframe ||
          widget.controller.accountId != account ||
          _mode == ChartMode.range) {
        return;
      }
      final previousBars = _actualBars;
      // The cTrader stitcher's exact overlap validation, 200k-bar memory cap
      // and OHLC conflict policy stay in force, but for large archives run
      // away from the chart's Android gesture/paint isolate.
      final refresh = await VerifiedClosedCandleRefresh.appendVerifiedAsync(
        existing: previousBars, recent: recent);
      if (!mounted || revision != _loadRevision || _replay ||
          _selectedSymbol.code != symbol.code || _timeframe != timeframe ||
          widget.controller.accountId != account ||
          _mode == ChartMode.range ||
          !identical(_actualBars, previousBars)) {
        return;
      }
      if (refresh.appended == 0) {
        // Overlap-only cTrader responses do not allocate or publish a new
        // 100k+ chart snapshot and must not advance the Replay cursor.
        // If no error is displayed, do not rebuild the toolbar or chart
        // just because an unchanged broker-close poll finished.
        if (_loadError != null) {
          setState(() => _loadError = null);
        }
        return;
      }
      final snapshot = refresh.snapshot!;
      setState(() {
        _loadError = null;
        // The cTrader stitcher has already verified an append-only broker
        // response. Extend a prepared HA view causally from its last bar,
        // instead of recalculating the full archive while drawing.
        _heikinCache.adoptVerifiedAppend(
          previousSource: _actualCandles,
          nextSource: snapshot.candles,
          appended: refresh.appended,
        );
        _actualBars = snapshot.bars;
        _actualCandles = snapshot.candles;
        _actualTimestamps = snapshot.timestamps;
        // Keep historical pan/whitespace anchored as each real closed
        // candle arrives; do not jump back to the latest bar.
        _viewport = _viewport.afterAppending(refresh.appended);
      });
      unawaited(MarketCandleStore.archive(symbol, timeframe,
          account, recent, markFresh: true)
          .catchError((Object _) {}));
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

  void _profileTouchGesture(ChartFrameInteraction interaction,
      List<TradeCandle> displayedCandles) {
    // These are safe workload COUNTS, not source quotes, order history,
    // broker names or account identifiers. Disabled in normal releases.
    _frameProfiler.beginInteraction(
      interaction: interaction,
      chartMode: _mode.name,
      replay: _replay || _replaySelectingStart,
      displayedCandles: displayedCandles.length,
      rangeBidTicks: _mode == ChartMode.range
          ? _rangeHistoryTicks.length : 0,
    );
  }

  Future<void> _autoFillRangeHistory(int revision) async {
    if (!mounted || revision != _loadRevision ||
        !_rangeAutoFillRevisionGate.start(revision)) return;
    try {
      final chartWidth = math.max(1.0, MediaQuery.sizeOf(context).width - 61);
      final target = RangeHistoryFillPolicy.targetClosedBars(
        plotWidth: chartWidth,
        candleWidth: _viewport.barWidth,
      );
      for (var page = 0;
          RangeHistoryFillPolicy.shouldContinue(
            completedPages: page,
            closedBars: math.max(0, _actualRange.length - 1),
            targetBars: target,
            loadedTicks: _rangeHistoryTicks.length,
            authenticatedSource: _rangeSourceSupported && _liveRequested,
            chartActive: mounted && widget.active && revision == _loadRevision,
            historicalReplay: _replay || _replaySelectingStart,
            loading: _olderLoading || _loading,
            historyExhausted: _historyExhausted,
            sourceError: _olderLoadError != null || _loadError != null,
          ); page++) {
        final cursorBefore = _rangeOlderCursorMs;
        await _loadOlderRangeHistory();
        if (!mounted || revision != _loadRevision ||
            cursorBefore == _rangeOlderCursorMs) break;
      }
    } finally {
      // Never clear the newer chart's active load after a stale request
      // from a prior symbol finishes.
      _rangeAutoFillRevisionGate.finish(revision);
    }
  }

  Future<void> _loadOlderRangeHistory() async {
    if (_replay && _training.trades.isNotEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('أنهِ أو احفظ جلسة التدريب قبل إعادة بناء تاريخ شموع المدى.')));
      return;
    }
    if (_olderLoading || _loading || _historyExhausted ||
        !_liveRequested || _mode != ChartMode.range ||
        (_rangeHistoryTicks.isEmpty ||
            _rangeHistoryTicks.length >= RangeOlderPage.maxLoadedTicks) ||
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
      // Edge/manual browsing searches up to six successive authenticated
      // twelve-hour BID windows when the market was closed. Automatic
      // background fill still checks one per attempt to honor its 24-page
      // network-work budget. Neither path synthesizes a candle.
      final cursorMs = _rangeOlderCursorMs ?? earliest - 1;
      final previouslyLoaded = _rangeHistoryTicks.length;
      bool isCurrent() => mounted && revision == _loadRevision &&
          widget.controller.accountId == account &&
          _selectedSymbol.code == symbol.code &&
          _mode == ChartMode.range;
      // An unarchived provider page is registered only for this exact
      // inclusive window. The scanner's off-isolate verification must
      // succeed before *any* broker response (including a quiet one) may
      // become a trusted local coverage manifest.
      final pendingArchivePages = <int>{};
      final scanned = await RangeOlderPageScanner.scan(
        cursorMs: cursorMs,
        alreadyLoaded: previouslyLoaded,
        maxPages: _rangeAutoFilling
            ? 1 : RangeOlderPageScanner.maxQuietWindowsPerAttempt,
        isCurrent: isCurrent,
        fetchVerified: (fromMs, toMs) async {
          List<MarketTick>? cached;
          try {
            cached = await RangeTickStore.readCoveredInterval(
              account, symbol.code, fromMs: fromMs, toMs: toMs,
            );
          } catch (_) {
            // A damaged cache is not evidence of broker coverage.
            cached = null;
          }
          if (!isCurrent()) return const <MarketTick>[];
          if (cached != null) return cached;
          // rangeTicks() fetches six days and cannot prove this short
          // interval. Request only the exact missing inclusive BID page.
          final fetched = await widget.controller.rangeTicksBetween(
            symbol, fromMs: fromMs, toMs: toMs,
          );
          if (!isCurrent()) return const <MarketTick>[];
          pendingArchivePages.add(fromMs);
          return fetched;
        },
        onVerifiedPage: (fromMs, toMs, page) {
          if (!isCurrent() || !pendingArchivePages.remove(fromMs)) return;
          // Store only a COMPLETE window confirmed by the scanner, not
          // unverified source ticks from an in-flight broker response.
          unawaited(RangeTickStore.archiveVerifiedWindow(
            account, symbol.code, page, fromMs: fromMs, toMs: toMs,
          ).then<void>((_) {}, onError: (Object _, StackTrace __) {}));
        },
      );
      if (scanned == null || !isCurrent()) return;
      final older = scanned.ticks;
      // The scanner verified the entire original BID page (including
      // same-ms ordering) off the UI isolate. Its last source timestamp
      // alone proves the whole sorted page precedes the display boundary:
      // don't scan all 120k+ authenticated ticks on the touch isolate.
      if (RangeOlderPage.overlapsLoadedHistory(
        sortedVerifiedOlder: older,
        earliestLoadedMs: earliest,
      )) {
        throw const MarketDataException(
          'تيكات الصفحة الأقدم تتداخل مع حد الشارت؛ تم إيقاف الدمج.');
      }
      if (older.isEmpty) {
        // Every skipped window was provider-verified empty. Preserve its
        // exact cursor so the next request never overlaps or skips time.
        _rangeOlderCursorMs = scanned.nextCursorMs;
        if (scanned.nextCursorMs < RangeOlderPage.lookback.inMilliseconds) {
          _historyExhausted = true;
        }
        return;
      }
      final prefix = older;
      // Capture the previous verified source list before the async worker:
      // canceled/superseded requests must never splice newer account data.
      final previousTicks = _rangeHistoryTicks;
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
      // Large history prepends and their full Range rebuild share one
      // background worker, instead of first copying up to 1m BID events
      // synchronously on the gesture/UI isolate.
      final rebuilt = await RangeBarTimeline.prependAndBuildAsync(
        olderTicks: prefix,
        currentTicks: previousTicks,
        priceDistance: _rangeTicks * point,
      );
      if (!mounted || revision != _loadRevision) return;
      final combined = rebuilt.ticks;
      final timeline = rebuilt.timeline;
      // The start selection is not yet a playback cutoff, but it still owns
      // one VERIFIED BID event. Prepending older ticks may shift every Range
      // bar; never leave the cursor attached to a stale bar index.
      final remappedStart = _replaySelectingStart
          ? timeline.rebaseReplayStart(
              oldEndTickIndices: _rangeBarEndTickIndices,
              oldSelectedIndex: _replayCandidateIndex,
              prependedTicks: prefix.length,
            )
          : null;
      if (_replaySelectingStart && remappedStart == null) {
        _olderLoadError =
            'أحدث التاريخ الأقدم بداية جديدة لشموع المدى، ولا توجد '
            'شمعة مغلقة عند تيك البداية المختار. أعد تحديد العمود '
            'قبل متابعة Replay، ولم نعرض بيانات مستقبلية.';
        return; // Retain the original source and original cursor.
      }
      // In an ACTIVE Range Replay, the saved initial candle and the current
      // cutoff must both rebase by their original BID events. Rebasing only
      // the current cutoff made Reset jump to an unrelated historical bar.
      final remappedInitial = _replay
          ? timeline.rebaseReplayStart(
              oldEndTickIndices: _rangeBarEndTickIndices,
              oldSelectedIndex: _replayInitialCount - 1,
              prependedTicks: prefix.length)
          : null;
      if (_replay && remappedInitial == null) {
        _olderLoadError = 'تعذر تثبيت شمعة بداية Replay الأصلية بعد '
            'إعادة بناء شموع Range؛ لن نغيّر موضع التدريب.';
        return;
      }
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
        final offset = pattern.offsetAnchor == null
            ? null : rebaseAnchor(pattern.offsetAnchor!);
        return first == null || last == null ||
                (pattern.offsetAnchor != null && offset == null)
            ? null : pattern.reanchored(first, last, offsetIndex: offset);
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
      final secondChannelIndex = _secondChannelAnchor == null
          ? null : rebaseAnchor(_secondChannelAnchor!);
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
          : timeline.visibleClosedBarsThroughTick(
              prefix.length + replayCutoffTick);
      if (_replay && (safeReplayBars == null || safeReplayBars == 0 ||
          remappedInitial == null || remappedInitial + 1 > safeReplayBars)) {
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
        _rangeOlderCursorMs = scanned.nextCursorMs;
        _actualRange = timeline.bars;
        _rangeBarEndTickIndices = timeline.endTickIndices;
        _rangeBarTimestamps = timeline.endTimestamps;
        if (_replaySelectingStart && remappedStart != null) {
          _replayCandidateIndex = remappedStart;
        }
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
        _secondChannelAnchor = secondChannelIndex == null ? null
            : ChartAnchor(secondChannelIndex, _secondChannelAnchor!.price);
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
          _training.clear(); // Rebuilt Range indices need a fresh cutoff.
          // A non-null, closed-bar cutoff was already checked above.
          _training.moveTo(timeline.bars, safeReplayBars!);
          _visibleThrough = safeReplayBars;
          // Rewind continues to target the same verified BID event.
          _replayInitialCount = remappedInitial! + 1;
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
      // Preserve the exclusive cursor on every broker request. A closed
      // session can span multiple empty windows, especially M1 weekends.
      // Search a bounded number of real cTrader windows automatically,
      // without synthesizing or repeating any source candle.
      final symbol = _selectedSymbol;
      final timeframe = _timeframe;
      final sourceAccount = widget.controller.accountId;
      final List<MarketBar> older;
      var quietCursor = cursor;
      if (symbol.source == TradeSource.ctrader) {
        final page = await CTraderOlderCandlePager.load(
          cursorMs: cursor,
          lookback: MarketApi.ctraderCandleLookback(timeframe),
          fetch: (before) => widget.controller.history(
              symbol, timeframe, before: before),
          isCurrent: () => mounted && revision == _loadRevision &&
              widget.controller.accountId == sourceAccount &&
              _selectedSymbol.code == symbol.code &&
              _timeframe == timeframe,
        );
        if (page == null) return;
        older = page.bars;
        quietCursor = page.nextCursorMs;
      } else {
        final before = DateTime.fromMillisecondsSinceEpoch(
            cursor - 1, isUtc: true);
        older = await widget.controller.history(
            symbol, timeframe, before: before);
      }
      if (revision != _loadRevision || !mounted ||
          _selectedSymbol.code != symbol.code || _timeframe != timeframe ||
          widget.controller.accountId != sourceAccount ||
          _mode == ChartMode.range) return;
      // Keep the exact source snapshot used for this page. A large
      // prepend/axis rebuild is done on a worker isolate so 100k+ locally
      // verified candles do not pause the Android gesture/UI isolate.
      final previousBars = _actualBars;
      final prepared = await OlderCandlePrepend.prepareAsync(
        existing: previousBars, older: older);
      // A slow worker result must never overwrite a newer account, symbol,
      // timeframe, feed or session. Preserve Replay's source candle indices.
      if (revision != _loadRevision || !mounted ||
          _selectedSymbol.code != symbol.code || _timeframe != timeframe ||
          widget.controller.accountId != sourceAccount ||
          _mode == ChartMode.range ||
          !identical(_actualBars, previousBars)) return;
      final unique = prepared.prefix;
      if (unique.isEmpty) {
        if (_selectedSymbol.source == TradeSource.binance) {
          _historyExhausted = true;
        } else {
          // The pager has already checked up to five disjoint, genuinely
          // empty windows. Keep its exclusive cursor for the next request;
          // stop this pass rather than looping indefinitely on holidays.
          _olderCursorMs = quietCursor;
          if (quietCursor < 1) {
            _historyExhausted = true;
          } else {
            _olderLoadError =
                'لم يجد cTrader شموعًا في الفترات السابقة التي فحصناها. '
                'اضغط «أقدم» للبحث قبلها.';
          }
        }
      } else {
        _olderCursorMs = unique.first.timestamp;
        unawaited(MarketCandleStore.archive(_selectedSymbol, _timeframe,
            _selectedSymbol.source == TradeSource.ctrader
                ? widget.controller.accountId : null, unique)
            .catchError((Object _) {}));
        setState(() {
        _actualBars = prepared.bars;
        _actualCandles = prepared.candles;
        _actualTimestamps = prepared.timestamps;
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
        if (_secondChannelAnchor != null) {
          _secondChannelAnchor =
              _secondChannelAnchor!.shifted(unique.length);
        }
        // Undo snapshots contain bar indices from before historical prepend.
        // Keep current drawings but never replay an obsolete anchor snapshot.
        _lineUndo.clear();
        _lineRedo.clear();
        // The Replay cutoff must stay at the SAME historical candle when
        // older candles are prepended. Never reveal new future candles.
        if (_replay) {
          _training.prepend(unique.length);
          _visibleThrough += unique.length;
          _replayInitialCount += unique.length;
        }
        if (_replaySelectingStart) {
          // Prepending older OHLC must keep the cursor on the same UTC bar.
          _replayCandidateIndex += unique.length;
        }
        });
      }
    } on MarketDataException catch (error) {
      if (revision == _loadRevision && mounted) {
        _olderLoadError = error.message;
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
    _recordTraining();
    _frameProfiler.detach();
    _heikinCache.dispose();
    _autoPriceScaleCache.clear();
    widget.controller.removeListener(_onMarketUpdate);
    _loadRevision++;
    _replayTimer?.cancel();
    _closedCandleTimer?.cancel();
    _momentum.dispose();
    _chartRepaint.dispose();
    _rectangleRepaint.dispose();
    _chartTextCache.clear();
    super.dispose();
  }

  void _stopPlayback() {
    _replayTimer?.cancel();
    _replayTimer = null;
    _playing = false;
  }

  /// Execution uses authentic raw OHLC, even when the UI displays
  /// Heikin-Ashi. Never execute on smoothed, synthetic candle prices.
  List<TradeCandle> get _replayMarketCandles =>
      _mode == ChartMode.range ? _actualRange : _actualCandles;

  void _recordTraining() {
    _trainingSaveDebounce?.cancel();
    _trainingSaveDebounce = null;
    if (_trainingSessionId.isEmpty || !_trainingEverTraded) return;
    final sessionId = _trainingSessionId;
    final sourceKey = _trainingSourceKey;
    final count = _training.visibleCount;
    final trades = _training.trades;
    // Serialize writes: a slower previous write must never overwrite a newer
    // replay cutoff, stop fill or manual close in SQLite.
    _trainingSaveQueue = _trainingSaveQueue.then((_) =>
        ReplayTrainingArchive.save(
          sessionId: sessionId,
          sourceKey: sourceKey,
          visibleCount: count,
          trades: trades,
        )).catchError((Object error) {
      if (mounted && _replay) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تعذر حفظ سجل Replay المحلي. تحقق من مساحة التخزين.')));
      }
    });
  }

  /// Avoid one SQLite write for every frame while the user drags the slider.
  /// Closing Replay and disposing the chart flush the final snapshot.
  void _scheduleTrainingSave() {
    if (!_trainingEverTraded) return;
    _trainingSaveDebounce?.cancel();
    _trainingSaveDebounce = Timer(
        const Duration(milliseconds: 300), _recordTraining);
  }

  void _seekReplay(int requestedCount) {
    if (!_replay) return;
    final next = requestedCount.clamp(1, _totalBars).toInt();
    setState(() {
      _stopPlayback();
      _training.moveTo(_replayMarketCandles, next);
      _visibleThrough = next;
    });
    _scheduleTrainingSave();
  }

  void _setReplaySpeed(ReplayPlaybackSpeed speed) {
    final wasPlaying = _playing;
    _stopPlayback();
    setState(() => _replaySpeed = speed);
    if (wasPlaying) _togglePlay();
  }

  Future<void> _openTrainingOrderDialog({
    ReplaySide initialSide = ReplaySide.buy,
  }) async {
    if (!_replay || _visibleThrough < 1 ||
        _visibleThrough > _replayMarketCandles.length) return;

    // Freeze the revealed timeline while the ticket is on screen.
    // Otherwise the playback timer could move the cursor during editing.
    if (_playing) setState(_stopPlayback);
    final entryVisibleCount = _visibleThrough;
    // Execute at the known raw candle close, not Heikin-Ashi averages.
    final price = _replayMarketCandles[entryVisibleCount - 1].close;
    final order = await showDialog<ReplayPracticeOrder>(
      context: context,
      builder: (_) => ReplayTrainingOrderDialog(
        entryPrice: price, initialSide: initialSide),
    );
    if (!mounted || !_replay || order == null) return;

    // The history may have changed while the modal was open. Never place
    // an entry at a newly revealed or newly hidden market price.
    final currentBars = _replayMarketCandles;
    if (_visibleThrough != entryVisibleCount ||
        _visibleThrough < 1 ||
        _visibleThrough > currentBars.length ||
        currentBars[_visibleThrough - 1].close != price) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تحركت الشموع أثناء فتح النافذة. أعد إدخال الصفقة.')));
      return;
    }

    try {
      setState(() {
        _training.enter(
          side: order.side,
          candles: currentBars,
          quantity: order.quantity,
          stopLoss: order.stopLoss,
          takeProfit: order.takeProfit,
        );
      });
      _trainingEverTraded = true;
      _recordTraining();
    } on ArgumentError {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('الوقف أو الهدف أو حجم الصفقة غير صالح للتدريب.')));
    } on StateError {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('بيانات الشمعة تغيرت. حاول مجددًا.')));
    }
  }

  void _closeTrainingTrade(int tradeId) {
    if (!_replay) return;
    try {
      setState(() => _training.closeAtCurrent(
          tradeId, _replayMarketCandles));
      _recordTraining();
    } on StateError {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذر إغلاق الصفقة: لم يعد السعر المكشوف صالحًا.')));
    }
  }

  /// Flatten only local replay practice entries at the currently revealed
  /// raw OHLC close; never contact a live broker, and never use future prices.
  void _flattenReplayTrainingTrades() {
    if (!_replay || _training.openTradeCount == 0) return;
    final openIds = _training.trades.where((t) => t.isOpen)
        .map((t) => t.id).toList(growable: false);
    try {
      setState(() {
        _stopPlayback();
        for (final id in openIds) {
          _training.closeAtCurrent(id, _replayMarketCandles);
        }
      });
      _recordTraining();
      _replayMessage('تم تسطيح ${openIds.length} صفقة تدريب عند '
          'آخر سعر تاريخي مكشوف. لم تُرسل أوامر حقيقية.');
    } on StateError {
      _replayMessage('تعذر إغلاق التدريب: السعر التاريخي غير صالح.');
    }
  }

  Future<void> _showTrainingTrades() async {
    final trades = _training.trades;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('صفقات التدريب التاريخية',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('النتيجة = فرق السعر × الكمية؛ ليست أرباحًا بالدولار.'),
          Text('المحقق: ${_training.realizedPricePnl.toStringAsFixed(4)}',
              textDirection: TextDirection.ltr),
          SizedBox(height: math.min(320.0, 64.0 * trades.length + 20.0),
            child: trades.isEmpty
                ? const Center(child: Text('لم تفتح أي صفقات تدريب'))
                : ListView.builder(
                    itemCount: trades.length,
                    itemBuilder: (_, index) {
                      final trade = trades[index];
                      return ListTile(
                        title: Text(
                          '${trade.side == ReplaySide.buy ? 'شراء' : 'بيع'} '
                          '${trade.entryPrice.toStringAsFixed(5)}'),
                        subtitle: Text(trade.isOpen ? 'مفتوحة، كمية ${trade.quantity}'
                            : 'مغلقة، فرق السعر × الكمية: '
                              '${trade.realizedPricePnl.toStringAsFixed(4)}'),
                        trailing: trade.isOpen ? TextButton(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _closeTrainingTrade(trade.id);
                          },
                          child: const Text('إغلاق'),
                        ) : null,
                      );
                    },
                  ),
          ),
        ]),
      )),
    );
  }

  Future<void> _showTrainingArchive() async {
    try {
      // A slider seek may have a pending debounced snapshot.
      _recordTraining();
      await _trainingSaveQueue;
      final history = await ReplayTrainingArchive.recent();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => SafeArea(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('أرشيف جلسات Replay المحلية',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const Text('نتائج تدريب منفصلة عن حساب التداول والوسيط.'),
            SizedBox(height: 320, child: history.isEmpty
                ? const Center(child: Text('لا توجد جلسات محفوظة'))
                : ListView.builder(
                    itemCount: history.length,
                    itemBuilder: (_, index) {
                      final record = history[index];
                      return ListTile(
                        title: Text('${record['sourceKey']}'),
                        subtitle: Text('عدد الصفقات: ${record['tradeCount']} · '
                            'آخر شمعة مكشوفة: ${record['visibleCount']}'),
                        trailing: Text('${record['realizedPricePnl']}'),
                      );
                    },
                  ),
            ),
          ]),
        )),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('لم نتمكن من قراءة أرشيف التدريب المحلي.')));
    }
  }

  List<int> get _replaySourceTimestamps =>
      _mode == ChartMode.range ? _rangeBarTimestamps : _actualTimestamps;

  void _replayMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message, textDirection: TextDirection.rtl)));
  }

  /// Replay is staged: show full verified historical candles with a draggable
  /// timestamped start cursor. No future candle is hidden until confirmation.
  void _enterReplayStartSelection() {
    final times = _replaySourceTimestamps;
    if (_totalBars < 2 ||
        !ReplayStartResolver.hasVerifiedTimes(times, _totalBars)) {
      _replayMessage('يتطلب تحديد بداية Replay شمعتين مغلقتين '
          'بتوقيت موثق من مصدر السوق. حمّل بيانات الرمز أولًا.');
      return;
    }
    _stopMomentum();
    final plotWidth = math.max(1.0, MediaQuery.sizeOf(context).width - 61);
    final index = ReplayStartResolver.atX(
      viewport: _viewport,
      x: plotWidth * .5,
      plotWidth: plotWidth,
      candleCount: _replayMarketCandles.length,
      completedCount: _totalBars,
      fallbackIndex: math.max(0, _totalBars - 2));
    setState(() {
      _stopPlayback();
      // Historical Replay may be at a very different price from the user's
      // manually scaled live ruler. Restore genuine OHLC auto-range while
      // retaining horizontal zoom and the chosen candle/time anchor.
      _manualPriceScale = null;
      _manualPriceScaleKey = null;
      _draggingPriceAxis = false;
      _replaySelectingStart = true;
      _replayDraggingStart = false;
      _replayShowTradingButtons = false;
      _replayShowDrawingTools = false;
      _replayCandidateIndex = index;
      _crosshair = null;
      // While selecting, the complete market history remains visible (muted
      // to the right of the cursor). Avoid confusing drawing edit gestures.
      _drawing = false;
    });
  }

  void _confirmReplayStart() {
    if (!_replaySelectingStart || _replay) return;
    if (!ReplayStartResolver.hasVerifiedTimes(
        _replaySourceTimestamps, _totalBars)) {
      _replayMessage('تعذر التحقق من توقيت العمود التاريخي المحدد.');
      return;
    }
    final oldCount = _replayMarketCandles.length;
    final selected = _replayCandidateIndex.clamp(
        0, ReplayStartResolver.maxStart(_totalBars)).toInt();
    // Assert the selected bar belongs to actual broker/source timestamps.
    ReplayStartResolver.timestampAt(
        _replaySourceTimestamps, selected, _totalBars);
    _stopMomentum();
    setState(() {
      _stopPlayback();
      _training.clear();
      _trainingEverTraded = false;
      _trainingSessionId =
          DateTime.now().toUtc().microsecondsSinceEpoch.toString();
      _trainingSourceKey =
          '${_selectedSymbol.source.name}:'
          '${widget.controller.accountId ?? 'public'}:'
          '$_symbol:$_timeframe:${_mode.name}';
      // Analysis objects can refer to the future. Keep them separately and
      // show only fresh drawings placed inside the actual Replay timeline.
      _analysisLevels = List<double>.of(_levels);
      _analysisPatterns = List<ChartPattern>.of(_patterns);
      _analysisShortPositions = List<ChartShortPosition>.of(_shortPositions);
      _analysisRectangles = List<ChartPriceRectangle>.of(_rectangles);
      _levels.clear();
      _patterns.clear();
      _shortPositions.clear();
      _rectangles.clear();
      _replaySelectingStart = false;
      _replayDraggingStart = false;
      _replay = true;
      _replayInitialCount = selected + 1;
      _visibleThrough = _replayInitialCount;
      _training.moveTo(_replayMarketCandles, _visibleThrough);
      // Preserve the selected candle's visual x after switching the painter
      // from full history to the strict (future-free) CandlePrefix.
      final plotWidth = math.max(1.0, MediaQuery.sizeOf(context).width - 61);
      final minScroll = -plotWidth / _viewport.barWidth * .68;
      final scroll = (_viewport.scrollBars + _visibleThrough - oldCount)
          .clamp(minScroll, (_visibleThrough - 1).toDouble()).toDouble();
      _viewport = ChartViewport(
        barWidth: _viewport.barWidth,
        scrollBars: scroll,
        rightMarginBars: _viewport.rightMarginBars);
      _crosshair = null;
      _selectedLine = null;
      _selectedPattern = null;
      _selectedShort = null;
      _selectedRectangle = null;
      _lineUndo.clear();
      _lineRedo.clear();
    });
  }

  void _exitReplay() {
    if (!_replay && !_replaySelectingStart) return;
    if (_replay) _recordTraining();
    _stopMomentum();
    setState(() {
      _stopPlayback();
      // Do not carry a zoom anchored to a historical Replay candle into
      // the live broker price range on exiting practice mode.
      _manualPriceScale = null;
      _manualPriceScaleKey = null;
      _draggingPriceAxis = false;
      if (_replay) {
        _levels..clear()..addAll(_analysisLevels);
        _patterns..clear()..addAll(_analysisPatterns);
        _shortPositions..clear()..addAll(_analysisShortPositions);
        _rectangles..clear()..addAll(_analysisRectangles);
      }
      _replay = false;
      _replaySelectingStart = false;
      _replayDraggingStart = false;
      _training.clear();
      _trainingEverTraded = false;
      _trainingSessionId = '';
      _trainingSourceKey = '';
      _viewport = _viewport.jumpToLatest();
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
      _secondChannelAnchor = null;
      _lineUndo.clear();
      _lineRedo.clear();
    });
  }

  void _toggleReplay() {
    if (_replay || _replaySelectingStart) {
      _exitReplay();
    } else {
      _enterReplayStartSelection();
    }
  }

  Future<void> _chooseReplayStartAgain() async {
    if (_replay && _training.trades.isNotEmpty) {
      _stopPlayback();
      final approve = await showDialog<bool>(context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('اختيار بداية جديدة'),
          content: const Text('لديك صفقات تدريب في هذه الجلسة. '
              'اختيار بداية جديدة سيبدأ جلسة مستقلة؛ '
              'ستُحفظ الجلسة السابقة في الأرشيف المحلي.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حفظ وبدء جلسة جديدة')),
          ]));
      if (approve != true || !mounted) return;
    }
    _exitReplay();
    if (mounted) _enterReplayStartSelection();
  }

  /// Date / oldest / random actions must reveal their real candle in the
  /// chart. Merely changing the selected timestamp leaves the blue line
  /// offscreen when jumping to distant historical sessions.
  void _revealReplayCandidate(int index) {
    if (!_replaySelectingStart || index < 0 ||
        index > ReplayStartResolver.maxStart(_totalBars)) return;
    _stopMomentum();
    final width = math.max(1.0, MediaQuery.sizeOf(context).width - 61);
    final viewport = _viewport.revealHistoricalBar(
      index: index,
      candleCount: _replayMarketCandles.length,
      plotWidth: width,
    );
    setState(() {
      _replayCandidateIndex = index;
      _viewport = viewport;
      _crosshair = null;
    });
  }

  Future<void> _chooseReplayStartDate() async {
    if (!_replaySelectingStart) {
      await _chooseReplayStartAgain();
    }
    if (!mounted || !_replaySelectingStart) return;
    final timestamps = _replaySourceTimestamps;
    if (!ReplayStartResolver.hasVerifiedTimes(timestamps, _totalBars)) return;
    final zone = _symbolSettings.timeZone;
    final first = ReplayDateTimeResolver.displayWallTime(
        zone, timestamps.first);
    final last = ReplayDateTimeResolver.displayWallTime(
        zone, timestamps[ReplayStartResolver.maxStart(_totalBars)]);
    final initial = ReplayDateTimeResolver.displayWallTime(
        zone, timestamps[_replayCandidateIndex]);
    // Date and time on the picker MUST use the chart's configured zone.
    // The previous implementation used the device timezone even when chart
    // axis was configured for New York (wrong at historical DST boundaries).
    final date = await showDatePicker(
      context: context,
      helpText: 'اختر التاريخ بتوقيت ${zone.nameArabic}',
      firstDate: DateTime(first.year, first.month, first.day),
      lastDate: DateTime(last.year, last.month, last.day),
      initialDate: DateTime(initial.year, initial.month, initial.day),
    );
    if (date == null || !mounted || !_replaySelectingStart) return;
    final time = await showTimePicker(
      context: context,
      helpText: 'الساعة والدقيقة بتوقيت ${zone.nameArabic}',
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted || !_replaySelectingStart) return;
    final candidates = ReplayDateTimeResolver.utcCandidates(
      zone: zone, year: date.year, month: date.month, day: date.day,
      hour: time.hour, minute: time.minute);
    if (candidates.isEmpty) {
      _replayMessage('هذا الوقت غير موجود في توقيت ${zone.nameArabic} '
          'بسبب انتقال الساعة أو تاريخ غير صالح. اختر وقتًا آخر.');
      return;
    }
    int? candidate;
    if (candidates.length == 1) {
      candidate = candidates.single;
    } else {
      // November DST fall-back repeats the same 01:xx clock time twice.
      // A historical trade decision must not silently pick one of them.
      candidate = await showDialog<int>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('وقت تاريخي مكرر'),
          content: const Text('يحدث هذا الوقت مرتين عند تغيير '
              'التوقيت الصيفي. اختر وقت السوق المقصود:'),
          actions: [
            for (final instant in candidates)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, instant),
                child: Text(
                  '${zone.labelAt(DateTime.fromMillisecondsSinceEpoch(
                      instant, isUtc: true))} · '
                  '${DateTime.fromMillisecondsSinceEpoch(
                      instant, isUtc: true).toIso8601String()
                      .substring(0, 16)} UTC',
                  textDirection: TextDirection.ltr),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء')),
          ],
        ),
      );
    }
    if (candidate == null || !mounted || !_replaySelectingStart) return;
    final index = ReplayStartResolver.atOrBefore(
        timestamps, _totalBars, candidate);
    if (index < 0) {
      _replayMessage('لا توجد شمعة موثقة قبل هذا التاريخ ضمن البيانات المحمّلة.');
      return;
    }
    _revealReplayCandidate(index);
  }

  void _handleReplayStartMenu(ReplayStartMenuAction action) {
    if (action == ReplayStartMenuAction.toggleTrading) {
      setState(() => _replayShowTradingButtons = !_replayShowTradingButtons);
      return;
    }
    if (action == ReplayStartMenuAction.toggleDrawingTools) {
      setState(() => _replayShowDrawingTools = !_replayShowDrawingTools);
      return;
    }
    if (action == ReplayStartMenuAction.date) {
      unawaited(_chooseReplayStartDate());
      return;
    }
    if (_replay) {
      // Choosing "random" or "earliest" during active Replay must REALLY
      // apply that choice after the user approves replacing the session.
      unawaited(_chooseReplayStartAgain().then((_) {
        if (mounted && _replaySelectingStart) {
          _applyReplayStartMenuChoice(action);
        }
      }));
      return;
    }
    _applyReplayStartMenuChoice(action);
  }

  void _applyReplayStartMenuChoice(ReplayStartMenuAction action) {
    if (!_replaySelectingStart) return;
    switch (action) {
      case ReplayStartMenuAction.column:
        break; // The cursor can already be dragged or moved by tapping.
      case ReplayStartMenuAction.earliest:
        _revealReplayCandidate(0);
        _replayMessage('تم اختيار أقدم شمعة موثقة محمّلة. '
            'يمكن تحميل تاريخ أقدم إن أتاحه مصدر السوق.');
        break;
      case ReplayStartMenuAction.random:
        final max = ReplayStartResolver.maxStart(_totalBars);
        _revealReplayCandidate(math.Random().nextInt(max + 1));
        break;
      case ReplayStartMenuAction.date:
      case ReplayStartMenuAction.toggleTrading:
      case ReplayStartMenuAction.toggleDrawingTools:
        break;
    }
  }

  void _handleReplayExtras(ReplayExtrasAction action) {
    switch (action) {
      case ReplayExtrasAction.practiceOrder:
        if (_replay) unawaited(_openTrainingOrderDialog());
      case ReplayExtrasAction.practiceTrades:
        if (_replay) unawaited(_showTrainingTrades());
      case ReplayExtrasAction.practiceArchive:
        unawaited(_showTrainingArchive());
      case ReplayExtrasAction.loadOlder:
        if (!_olderLoading && !_historyExhausted) {
          setState(() => _olderLoadError = null);
          unawaited(_mode == ChartMode.range
              ? _loadOlderRangeHistory()
              : _loadOlderHistory(manual: true));
        }
      case ReplayExtrasAction.candleSettings:
        _showCandleSettings();
      case ReplayExtrasAction.drawingTools:
        setState(() => _replayShowDrawingTools = true);
        unawaited(_showDrawingTools());
      case ReplayExtrasAction.chartType:
        unawaited(_showChartTypePicker());
    }
  }

  void _handleReplayIntervalMenu(ReplayStepMenuAction action) {
    switch (action) {
      case ReplayStepMenuAction.currentBar:
        _replayMessage('التقدم يتم بشمعة مصدر واحدة مكتملة. '
            'لا يتم اختراع تيكات أو حركة داخلية.');
        break;
      case ReplayStepMenuAction.auto:
        setState(() => _replayAutoStep = !_replayAutoStep);
        break;
      case ReplayStepMenuAction.information:
        _replayMessage('تقدم Replay الحالي يعتمد الشموع التاريخية المغلقة فقط. '
            'تقدم التيك أو الثانية يحتاج إلى بيانات تاريخية أدق من المصدر.');
        break;
    }
  }

  Future<void> _resetReplayToStart() async {
    if (!_replay) return;
    // Freeze playback BEFORE asking permission. Otherwise the market cutoff
    // could advance under the user's confirmation dialog.
    if (_playing) setState(_stopPlayback);
    final sourceKey = _trainingSourceKey;
    final sessionId = _trainingSessionId;
    final hasTrades = _training.trades.isNotEmpty;
    final hasDrawings = _levels.isNotEmpty || _patterns.isNotEmpty ||
        _shortPositions.isNotEmpty || _rectangles.isNotEmpty;
    final hasPracticeHistory = _trainingEverTraded || hasTrades;
    if (hasPracticeHistory || hasDrawings) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('العودة إلى بداية Replay'),
          content: Text(
            hasPracticeHistory
              ? 'سيُحفظ سجل الصفقات في الأرشيف المحلي أولًا، '
                'ثم تبدأ جلسة تدريب جديدة من شمعة البداية نفسها. '
                'ستُمسح رسومات Replay الحالية، ولن تُرسل أي أوامر للوسيط.'
              : 'سيتم مسح الرسومات التي أُنشئت خلال Replay '
                'والرجوع إلى شمعة البداية. الرسومات الأصلية خارج '
                'المحاكاة ستبقى محفوظة.',
            textDirection: TextDirection.rtl,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              key: const Key('replay-confirm-reset'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حفظ والعودة للبداية'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted || !_replay ||
          sessionId != _trainingSessionId ||
          sourceKey != _trainingSourceKey) return;
    }

    // A pending historical page might have changed the valid source.
    // Never seek to an incomplete, invalid or future market candle.
    if (_replayInitialCount < 1 || _replayInitialCount > _totalBars) {
      _replayMessage('تعذرت العودة: نقطة البداية لم تعد ضمن '
          'الشموع التاريخية المكتملة المتاحة.');
      return;
    }
    if (hasPracticeHistory) {
      // A previously queued write can fail without throwing (the regular
      // background saver intentionally catches SQLite errors). A reset must
      // independently confirm DURABLE storage before clearing live trades.
      _trainingSaveDebounce?.cancel();
      _trainingSaveDebounce = null;
      try {
        await _trainingSaveQueue;
        if (!mounted || !_replay || sessionId != _trainingSessionId ||
            sourceKey != _trainingSourceKey) return;
        await ReplayTrainingArchive.save(
          sessionId: sessionId,
          sourceKey: sourceKey,
          visibleCount: _training.visibleCount,
          trades: _training.trades,
        );
      } catch (_) {
        _replayMessage('فشل حفظ صفقات Replay في الأرشيف. '
            'تم الإبقاء على الجلسة والصفقات دون إعادة تعيين.');
        return;
      }
      if (!mounted || !_replay || sessionId != _trainingSessionId ||
          sourceKey != _trainingSourceKey) return;
    }
    _stopMomentum();
    setState(() {
      _stopPlayback();
      _training.clear();
      _training.moveTo(_replayMarketCandles, _replayInitialCount);
      _visibleThrough = _replayInitialCount;
      _trainingEverTraded = false;
      // Fresh archive identity: a later save cannot overwrite the prior run.
      _trainingSessionId =
          DateTime.now().toUtc().microsecondsSinceEpoch.toString();
      // Replay-added drawings may refer to candles no longer revealed.
      // Original drawings are still held in _analysis* for normal mode.
      _levels.clear();
      _patterns.clear();
      _shortPositions.clear();
      _rectangles.clear();
      _crosshair = null;
      _selectedLine = null;
      _selectedPattern = null;
      _selectedShort = null;
      _selectedRectangle = null;
      _pendingAnchor = null;
      _secondChannelAnchor = null;
      _rectangleFirstCorner = null;
      _shortEntryAnchor = null;
      _shortStopPrice = null;
      _placingShort = false;
      _placingRectangle = false;
      _lineUndo.clear();
      _lineRedo.clear();
      // The market now displays the short, strictly revealed source prefix.
      // Place its last candle near the right edge, not in blank future space.
      _viewport = _viewport.jumpToLatest();
    });
  }

  void _togglePlay() {
    if (_playing) {
      setState(_stopPlayback);
      _recordTraining(); // Commit the last revealed cursor on manual pause.
      return;
    }
    setState(() => _playing = true);
    _replayTimer = Timer.periodic(_replaySpeed.interval, (timer) {
      if (!mounted || !_replay || _visibleThrough >= _totalBars) {
        timer.cancel();
        if (mounted) {
          setState(() => _playing = false);
          _recordTraining(); // Final cursor reached; flush the current session.
        }
        return;
      }
      final openBefore = _training.openTradeCount;
      setState(() {
        _training.moveTo(_replayMarketCandles, _visibleThrough + 1);
        _visibleThrough++;
      });
      if (openBefore != _training.openTradeCount) _recordTraining();
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
    // Recompute this display-only Heikin-Ashi view when the authentic
    // source list changes. Large histories are built off the Android touch
    // isolate; while pending, never display stale source or raw OHLC as HA.
    final smoothed = _heikinCache.resolve(
      source,
      onReady: () {
        if (mounted && _mode == ChartMode.heikinAshi &&
            identical(_actualCandles, source)) {
          setState(() {});
        }
      },
      onError: () {
        if (mounted && _mode == ChartMode.heikinAshi &&
            identical(_actualCandles, source)) {
          setState(() => _loadError =
              'تعذّر تجهيز شموع هيكناشي من بيانات المصدر. اضغط إعادة المحاولة.');
        }
      },
    );
    if (smoothed == null) return const <TradeCandle>[];
    return _replay ? CandlePrefix(smoothed, _visibleThrough) : smoothed;
  }

  void _changeSymbol(TradeSymbol item) {
    if (item.code == _symbol) return;
    _stopMomentum();
    // Any in-flight response from the previous symbol is invalid from now on.
    _loadRevision++;
    if (_replay) _recordTraining();
    setState(() {
      _stopPlayback();
      _replay = false;
      _replaySelectingStart = false;
      _replayDraggingStart = false;
      _training.clear();
      _trainingEverTraded = false;
      _symbol = item.code;
      // Never reuse an unsupported native provider interval when switching
      // from cTrader to Binance or vice versa. No derived candles.
      _timeframe = ChartTimeframeCatalog.compatibleOnSwitch(
          item.source, _timeframe);
      // Binance does not provide cTrader BID tick Range bars.
      if (_mode == ChartMode.range &&
          item.source != TradeSource.ctrader) {
        _mode = ChartMode.candles;
      }
      _viewport = _freshViewport();
      _resetDrawingObjects();
      _lastObservedQuote = widget.controller.recentQuoteFor(item);
      _lastQuoteRequestAtMs = 0;
      _actualBars = [];
      _actualCandles = [];
      _actualTimestamps = [];
      _actualRange = [];
      _rangeHistoryTicks = [];
      _rangeBarEndTickIndices = [];
      _rangeBarTimestamps = [];
      _rangeOlderCursorMs = null;
      _olderCursorMs = null;
      _olderLoading = false;
      _historyExhausted = false;
      _olderLoadError = null;
      _loadError = null;
      _loading = false;
    });
    if (widget.active && _liveRequested) {
      unawaited(_loadRealHistory());
    }
    if (widget.active && item.source == TradeSource.ctrader) {
      unawaited(_refreshSelectedCTraderQuote());
    }
  }

  Future<void> _showSymbolPicker() async {
    _stopMomentum();
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
                    Navigator.pop(sheetContext);
                    _changeSymbol(item);
                  },
                )),
          ]),
        ),
      ),
    );
  }

  Future<void> _showTimeframePicker() async {
    if (_replay || _replaySelectingStart) {
      _replayMessage('تغيير فاصل الشارت أثناء Replay يتطلب إعادة بناء '
          'السلسلة الزمنية بأمان. أغلق المحاكاة أولًا، ولن تُكشف '
          'الشموع المستقبلية تلقائيًا.');
      return;
    }
    _stopMomentum();
    final frames = ChartTimeframeCatalog.forSource(_selectedSymbol.source);
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
                        _viewport = _freshViewport();
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

  Future<void> _showAnalysisHub() async {
    _stopMomentum();
    final action = await showModalBottomSheet<AnalysisHubAction>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (sheetContext) => AnalysisHubSheet(
        onAction: (selection) => Navigator.pop(sheetContext, selection),
      ),
    );
    if (!mounted || action == null) return;
    await _runAnalysisHubAction(action);
  }

  Future<void> _runAnalysisHubAction(AnalysisHubAction action) async {
    switch (action) {
      case AnalysisHubAction.layoutFormat:
        await _showChartAppearance();
      case AnalysisHubAction.drawingSettings:
        await _showMagnetSettings();
      case AnalysisHubAction.indicators:
        await _showIndicatorCatalog();
      case AnalysisHubAction.replay:
        // Replay is always owned by this ChartScreen, never a separate page.
        _toggleReplay();
      case AnalysisHubAction.chartType:
        await _showChartTypePicker();
      case AnalysisHubAction.objectTree:
        await _showObjectTree();
      case AnalysisHubAction.symbolInformation:
      case AnalysisHubAction.dataSource:
        await _showMarketInformation();
      case AnalysisHubAction.tradeWithBroker:
        if (widget.onOpenAccount != null) {
          widget.onOpenAccount!();
        } else {
          await _showUnavailableAnalysisAction(action);
        }
      case AnalysisHubAction.saveLayout:
        // This tile is disabled in the reference and has no callback.
        break;
      case AnalysisHubAction.layoutManager:
      case AnalysisHubAction.newLayout:
      case AnalysisHubAction.openLayout:
      case AnalysisHubAction.compare:
      case AnalysisHubAction.alerts:
      case AnalysisHubAction.indicatorTemplates:
        await _showUnavailableAnalysisAction(action);
    }
  }

  Future<void> _showUnavailableAnalysisAction(AnalysisHubAction action) async {
    await showDialog<void>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(action.label, textDirection: TextDirection.rtl),
        content: const Text(
          'هذه الوظيفة ظاهرة في المرجع، لكن TradeLab لا يملك محركًا '
          'جاهزًا لتنفيذها حاليًا. لم يتم حفظ مخطط أو إنشاء تنبيه أو '
          'تغيير بيانات السوق.',
          textDirection: TextDirection.rtl),
        actions: [TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('حسنًا'))],
      ));
  }

  Future<void> _showIndicatorCatalog() async {
    await showModalBottomSheet<void>(context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(child: StatefulBuilder(
        builder: (context, updateSheet) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const TradeSectionTitle('المؤشرات'),
            SwitchListTile(
              key: const Key('analysis-sma12-toggle'),
              title: const Text('المتوسط المتحرك البسيط (12)',
                textDirection: TextDirection.rtl),
              subtitle: const Text('مُحتسب من شموع السوق المعروضة فقط',
                textDirection: TextDirection.rtl),
              value: _showIndicators,
              onChanged: (value) {
                setState(() => _showIndicators = value);
                updateSheet(() {});
              },
            ),
          ]),
        ),
      )),
    );
  }

  Future<void> _showChartAppearance() async {
    // Chart display settings must not reset the candle cache or Replay cursor.
    _stopMomentum();
    setState(() => _panelSettingsOpen = true);
  }

  void _showCandleSettings() {
    _stopMomentum();
    setState(() {
      _symbolSettingsReturnToPanel = false;
      _panelSettingsOpen = false;
      _scaleSettingsOpen = false;
      _symbolSettingsOpen = true;
    });
  }

  /// A predictable one-tap exit from drawing/selection modes. Drawing objects
  /// and their undo history remain untouched; finger drags return to pan.
  void _enableMoveChart() {
    _stopMomentum();
    setState(() {
      _drawing = false;
      _eraserMode = false;
      _rulerMode = false;
      _placingShort = false;
      _placingRectangle = false;
      _pendingAnchor = null;
      _secondChannelAnchor = null;
      _rectangleFirstCorner = null;
      _shortEntryAnchor = null;
      _shortStopPrice = null;
      _selectedLine = null;
      _selectedPattern = null;
      _selectedShort = null;
      _selectedRectangle = null;
      _crosshair = null;
    });
  }

  Future<void> _showObjectTree() async {
    final objects = <(String, int)>[
      ('الخطوط الأفقية', _levels.length),
      ('رسومات الاتجاه وفيبوناتشي', _patterns.length),
      ('مناطق السعر', _rectangles.length),
      ('مراكز البيع التجريبية', _shortPositions.length),
    ];
    await showModalBottomSheet<void>(context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const TradeSectionTitle('شجرة الكائنات'),
          for (final object in objects)
            ListTile(
              title: Text(object.$1, textDirection: TextDirection.rtl),
              leading: const Icon(Icons.layers_outlined),
              trailing: Text('${object.$2}'),
            ),
        ]),
      )),
    );
  }

  Future<void> _showMarketInformation() async {
    final source = _selectedSymbol.source == TradeSource.ctrader
        ? 'cTrader' : 'Binance';
    await showDialog<void>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('معلومات الشارت',
          textDirection: TextDirection.rtl),
        content: Text('الرمز: $_symbol\nالمصدر: $source\n'
          'الإطار: $_timeframe\nعدد الشموع المحمّلة: ${_displayCandles.length}\n'
          'Replay: ${_replay ? 'نشط' : 'غير نشط'}',
          textDirection: TextDirection.rtl),
        actions: [TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('إغلاق'))],
      ),
    );
  }

  Future<void> _showChartTypePicker() async {
    _stopMomentum();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      // The reference leaves the small chart header and system status bar
      // undimmed above this nearly full-height bottom sheet.
      barrierColor: Colors.transparent,
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
                _viewport = _freshViewport();
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
    // Count only cTrader BID events verified for this active chart; a forming
    // Range bar is not a completed source-confirmed market bar.
    final bidTickCount = _rangeHistoryTicks.length;
    final closedRangeBars = math.max(0, _actualRange.length - 1);
    final latestTickUtc = bidTickCount == 0
        ? 'غير متاح'
        : DateTime.fromMillisecondsSinceEpoch(
            _rangeHistoryTicks.last.timestamp, isUtc: true).toIso8601String();
    final canRequestOlder = RangeHistoryFillPolicy.canRequestOlderManually(
      rangeMode: _mode == ChartMode.range,
      connected: widget.controller.ctraderConnected && _rangeSourceSupported,
      hasAccount: widget.controller.accountId != null,
      hasVerifiedTicks: bidTickCount > 0,
      loadedTicks: bidTickCount,
      chartActive: widget.active,
      initialLoading: _loading,
      olderLoading: _olderLoading,
      autoFilling: _rangeAutoFilling,
      historyExhausted: _historyExhausted,
      replayActive: _replay,
      selectingReplayStart: _replaySelectingStart,
    );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // The default 9/16-height modal clipped the wrapped 9-size Range picker
      // on phones, causing a real 35px RenderFlex overflow at 390dp.
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
            const TradeSectionTitle('إعدادات شموع المدى'),
            Container(
              key: const Key('range-bid-source-status'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(sheetContext).colorScheme.primary
                    .withValues(alpha: .06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('تيكات BID الموثقة في الشارت: $bidTickCount',
                    textDirection: TextDirection.rtl),
                  Text('شموع Range المكتملة: $closedRangeBars',
                    textDirection: TextDirection.rtl),
                  Text('آخر تيك موثق (UTC): $latestTickUtc',
                    textDirection: TextDirection.rtl),
                  if (bidTickCount == 0)
                    const Text('لا توجد تيكات BID موثقة في الشارت حاليًا. '
                      'لا تُعرض شموع بديلة أو أسعار مُفترضة.',
                      textDirection: TextDirection.rtl),
                  if (bidTickCount > 0 && closedRangeBars == 0)
                    const Text('وصلت تيكات حقيقية، لكن لم تكتمل شمعة مدى '
                      'بعد بهذه المسافة السعرية.',
                      textDirection: TextDirection.rtl),
                  if (_rangeAutoFilling)
                    const Text('جارٍ البحث عن تاريخ BID أقدم ضمن حدود '
                      'التحميل التلقائي الآمنة.',
                      textDirection: TextDirection.rtl),
                  if (bidTickCount >= RangeOlderPage.maxLoadedTicks)
                    const Text('تم الوصول إلى الحد الآمن للتيكات '
                      'المحمّلة في ذاكرة الشارت (مليون BID). '
                      'هذا ليس نهاية التاريخ المتاح لدى الوسيط، '
                      'لكن تحميل المزيد يحتاج إدارة ذاكرة مختلفة.',
                      textDirection: TextDirection.rtl),
                ],
              ),
            ),
            if (canRequestOlder)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SizedBox(width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const Key('range-load-older-action'),
                    icon: const Icon(Icons.history_rounded),
                    label: const Text('تحميل فترة BID موثقة أقدم'),
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      if (mounted) unawaited(_loadOlderRangeHistory());
                    },
                  ),
                ),
              ),
            const SizedBox(height: 12),
            const Text('البدء المقترح: 25 نقطة. تتفاوت كثافة الشموع حسب الرمز والوسيط.',
              textDirection: TextDirection.rtl),
            const Text(
              'المقاس الأكبر قد ينتج شموعًا أقل. اختر مدى أصغر لعرض حركة '
              'أكثر تفصيلًا من تيكات BID الموثقة؛ لا تُنشأ بيانات افتراضية.',
              textDirection: TextDirection.rtl),
            if (_rangePointCache[
                '${widget.controller.accountId}:${_selectedSymbol.code}'] case final point?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'المسافة السعرية الحالية: '
                  '${(_rangeTicks * point).toStringAsFixed(5)} '
                  '${_selectedSymbol.source == TradeSource.ctrader ? 'حسب سعر الوسيط' : ''}',
                  textDirection: TextDirection.rtl),
              ),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final size in const [10, 25, 50, 100, 250, 500, 1000, 2000, 5000])
                ChoiceChip(
                  label: Text('$size'),
                  selected: _rangeTicks == size,
                  onSelected: (_) {
                    final changed = _rangeTicks != size;
                    if (changed) {
                      setState(() {
                        _rangeTicks = size;
                        _viewport = _freshViewport();
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
      ),
    );
  }

  Future<void> _showMagnetSettings() async {
    await showDialog<void>(context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('مغناطيس الأسعار', textDirection: TextDirection.rtl),
        children: [
          for (final option in const <(ChartMagnetMode, String)>[
            (ChartMagnetMode.off, 'إيقاف'),
            (ChartMagnetMode.weak, 'ضعيف'),
            (ChartMagnetMode.strong, 'قوي'),
          ]) SimpleDialogOption(
            onPressed: () {
              setState(() => _magnetMode = option.$1);
              Navigator.pop(dialogContext);
            },
            child: Text(option.$2, textDirection: TextDirection.rtl),
          ),
        ],
      ),
    );
  }

  Future<void> _showDrawingTools() async {
    _stopMomentum();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (sheetContext) => DrawingToolsSheet(
        initialCategory: DrawingCategory.trend,
        favorites: _favoriteDrawingTools,
        showFavoriteShortcuts: _showFavoriteShortcuts,
        onShowFavoriteShortcutsChanged: (visible) {
          if (!mounted) return;
          setState(() => _showFavoriteShortcuts = visible);
          unawaited(_persistDrawingFavoriteVisibility());
        },
        onFavoritesChanged: (favorites) {
          if (!mounted) return;
          setState(() => _favoriteDrawingTools..clear()..addAll(favorites));
          unawaited(_persistDrawingFavorites());
        },
        onGeneralAction: (action) {
          Navigator.pop(sheetContext);
          _runGeneralDrawingAction(action);
        },
        onGeneralMore: (action) {
          Navigator.pop(sheetContext);
          // Only already-supported configuration flows are exposed. The
          // reference does not define additional menu items or delete scopes.
          if (action == DrawingGeneralAction.magnet) {
            _showMagnetSettings();
          } else {
            _runGeneralDrawingAction(action);
          }
        },
        onUnavailable: (tool) => showDialog<void>(
          context: sheetContext,
          builder: (dialogContext) => AlertDialog(
            title: Text(tool.label, textDirection: TextDirection.rtl),
            content: const Text(
              'هذه الأداة ظاهرة في المرجع، لكن محرك رسمها غير متوفر في TradeLab بعد. '
              'لن يتم وضع رسم وهمي على الشارت.',
              textDirection: TextDirection.rtl,
            ),
            actions: [TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('حسنًا'),
            )],
          ),
        ),
        onSelect: (tool) {
          Navigator.pop(sheetContext);
          _activateCatalogDrawingTool(tool);
        },
      ),
    );
  }

  void _activateCatalogDrawingTool(DrawingCatalogKind tool) {
    switch (tool) {
      case DrawingCatalogKind.fibonacciRetracement:
        _selectDrawingMode(tool: ChartDrawingTool.fibonacci);
      case DrawingCatalogKind.trendLine:
        _selectDrawingMode(tool: ChartDrawingTool.trendLine);
      case DrawingCatalogKind.ray:
        _selectDrawingMode(tool: ChartDrawingTool.ray);
      case DrawingCatalogKind.extendedLine:
        _selectDrawingMode(tool: ChartDrawingTool.extendedLine);
      case DrawingCatalogKind.horizontal:
        _selectDrawingMode(tool: ChartDrawingTool.horizontal);
      case DrawingCatalogKind.horizontalRay:
        _selectDrawingMode(tool: ChartDrawingTool.horizontalRay);
      case DrawingCatalogKind.verticalLine:
        _selectDrawingMode(tool: ChartDrawingTool.verticalLine);
      case DrawingCatalogKind.parallelChannel:
        _selectDrawingMode(tool: ChartDrawingTool.parallelChannel);
      case DrawingCatalogKind.shortPosition:
        _selectDrawingMode(short: true);
      case DrawingCatalogKind.priceRectangle:
        _selectDrawingMode(rectangle: true);
      case DrawingCatalogKind.magnet:
        _showMagnetSettings();
      default:
        // Unsupported reference entries are visible in the catalog only.
        break;
    }
  }

  void _drawingNotice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, textDirection: TextDirection.rtl),
      duration: const Duration(seconds: 2),
    ));
  }

  int get _drawingObjectCount => _levels.length + _patterns.length +
      _rectangles.length + _shortPositions.length;

  Future<void> _confirmDeleteDrawings() async {
    final count = _drawingObjectCount;
    if (count == 0) {
      _drawingNotice('لا توجد رسومات لحذفها');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الرسومات', textDirection: TextDirection.rtl),
        content: Text('هل تريد حذف $count من الرسومات على هذا الشارت؟ '
            'يمكن التراجع عن الحذف من أدوات الرسم.',
            textDirection: TextDirection.rtl),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saveDrawingUndo();
      _restoreDrawings((<double>[], <ChartPattern>[],
          <ChartShortPosition>[], <ChartPriceRectangle>[]));
    });
    _drawingNotice('حُذفت الرسومات، ويمكن التراجع');
  }

  void _runGeneralDrawingAction(DrawingGeneralAction action) {
    switch (action) {
      case DrawingGeneralAction.ruler:
        setState(() {
          _drawing = true;
          _eraserMode = false;
          _rulerMode = true;
          _measureStart = null;
          _pendingAnchor = null;
        });
        _drawingNotice('المقياس: اختر نقطتين على شموع الشارت');
      case DrawingGeneralAction.eraser:
        setState(() {
          _eraserMode = true;
          _rulerMode = false;
          _drawing = true;
          _measureStart = null;
          _pendingAnchor = null;
        });
        _drawingNotice('الممحاة: المس رسمة لحذفها، ويمكن التراجع');
      case DrawingGeneralAction.continueDrawing:
        setState(() => _continueDrawing = !_continueDrawing);
        _drawingNotice(_continueDrawing
            ? 'استمر في الرسم: مفعّل' : 'استمر في الرسم: متوقف');
      case DrawingGeneralAction.hideDrawings:
        setState(() => _drawingsVisible = !_drawingsVisible);
        _drawingNotice(_drawingsVisible ? 'الرسومات ظاهرة' : 'الرسومات مخفية');
      case DrawingGeneralAction.lockDrawings:
        setState(() {
          _drawingsLocked = !_drawingsLocked;
          _eraserMode = false;
          _rulerMode = false;
          _measureStart = null;
        });
        _drawingNotice(_drawingsLocked
            ? 'تم قفل أدوات الرسم' : 'تم فتح قفل أدوات الرسم');
      case DrawingGeneralAction.magnet:
        _showMagnetSettings();
      case DrawingGeneralAction.deleteDrawings:
        unawaited(_confirmDeleteDrawings());
      case DrawingGeneralAction.zoomIn:
        _zoomBy(1.25);
      case DrawingGeneralAction.zoomOut:
        // The reference explicitly disables this catalog command.
        break;
    }
  }

  Widget _iconAction({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool active = false,
  }) => IconButton(
        tooltip: label,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 48),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(icon, size: 22,
            color: active ? TradeColors.blue : Theme.of(context).colorScheme.onSurface),
      );

  void _zoomBy(double factor) {
    _stopMomentum();
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
    _secondChannelAnchor = null;
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
    _secondChannelAnchor = null;
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

  ChartPriceScale _priceScale(
      List<TradeCandle> candles, double width, double height) {
    final plotHeight = math.max(1.0, height - 24);
    if (_priceScaleManual) return _manualPriceScale!.withHeight(plotHeight);
    return _autoPriceScaleCache.resolve(
      candles: candles,
      viewport: _viewport,
      plotWidth: width,
      plotHeight: plotHeight,
      topMarginPercent: _panelSettings.topMarginPercent,
      bottomMarginPercent: _panelSettings.bottomMarginPercent,
    );
  }

  void _resetPriceAxisToAuto() {
    setState(() {
      _manualPriceScale = null;
      _manualPriceScaleKey = null;
      _draggingPriceAxis = false;
    });
    // Force a live painter refresh even if its widget snapshot is unchanged.
    _chartRepaint.value++;
  }

  /// Edit an existing, genuine price/bar anchored drawing on paint-only
  /// frames. Its undo snapshot was captured once at finger-down.
  bool _updateDraggedGuide(Offset local, ChartPriceScale scale,
      double plotWidth, int candleCount) {
    if (_draggingLine && _selectedLine != null &&
        _selectedLine! >= 0 && _selectedLine! < _levels.length) {
      final next = scale.price(local.dy.clamp(0, scale.height).toDouble());
      if (!next.isFinite || next == _levels[_selectedLine!]) return false;
      _levels[_selectedLine!] = next;
      return true;
    }
    if (!_draggingPattern || _selectedPattern == null ||
        _selectedPattern! < 0 || _selectedPattern! >= _patterns.length ||
        _patternAtDragStart == null) return false;
    final original = _patternAtDragStart!;
    ChartPattern next;
    if (_draggedEndpoint != null) {
      final anchor = _anchorAt(local, scale, plotWidth, candleCount);
      if (anchor == null) return false;
      next = original.withEndpoint(_draggedEndpoint!, anchor);
    } else {
      final bars = ((local.dx - _gestureFocalX) /
          _viewport.barWidth).round();
      final anchors = [
        original.start.index,
        original.end.index,
        if (original.offsetAnchor != null) original.offsetAnchor!.index,
      ];
      final first = anchors.reduce(math.min);
      final last = anchors.reduce(math.max);
      final deltaBars = bars.clamp(-first,
          math.max(0, candleCount - 1 - last)).toInt();
      final deltaPrice = scale.price(
          local.dy.clamp(0, scale.height).toDouble()) -
          scale.price(_gestureFocalY.clamp(0, scale.height).toDouble());
      if (!deltaPrice.isFinite) return false;
      next = original.moved(deltaBars, deltaPrice);
    }
    _patterns[_selectedPattern!] = next;
    return true;
  }

  int? _hitLine(double y, ChartPriceScale scale) {
    for (var index = _levels.length - 1; index >= 0; index--) {
      if ((scale.y(_levels[index]) - y).abs() <= 18) return index;
    }
    return null;
  }

  int? _hitPattern(Offset position, ChartPriceScale scale,
      double width, int visibleCount) {
    // Never select an offscreen drawing from a touch on the price ruler,
    // time axis or outside the actual, visible candle plot.
    if (!position.dx.isFinite || !position.dy.isFinite ||
        !width.isFinite || width <= 0 ||
        !scale.height.isFinite || scale.height <= 0 ||
        position.dx < 0 || position.dx >= width ||
        position.dy < 0 || position.dy >= scale.height) return null;
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
        // Match the exact plot-clipped segments painted on the canvas.
        // A ratio at y=-8 was previously selectable by a touch at y=0,
        // despite having no visible line at all.
        if (ChartLineGeometry.hitFibonacciLevels(
          point: position,
          fromX: math.min(x1, x2),
          levelYs: ChartPattern.fibonacciRatios.map((ratio) =>
              scale.y(pattern.fibonacciPrice(ratio))),
          plot: Rect.fromLTWH(0, 0, width, scale.height),
        )) return i;
      } else {
        final offset = pattern.offsetAnchor == null ? null : Offset(
          _viewport.chartX(index: pattern.offsetAnchor!.index,
              candleCount: visibleCount, plotWidth: width),
          scale.y(pattern.offsetAnchor!.price));
        final strokes = ChartLineGeometry.strokes(
          tool: pattern.tool,
          start: Offset(x1, y1),
          end: Offset(x2, y2),
          offset: offset,
          bounds: Rect.fromLTWH(0, 0, width, scale.height),
        );
        if (strokes.any(
            (stroke) => ChartLineGeometry.distanceToStroke(
                position, stroke) <= 17)) return i;
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
    final channelOffset = pattern.offsetAnchor;
    if (channelOffset != null) {
      final offsetHandle = Offset(
        _viewport.chartX(index: channelOffset.index,
            candleCount: visibleCount, plotWidth: width),
        scale.y(channelOffset.price),
      );
      if ((position - offsetHandle).distance <= 22) {
        return ChartAnchorEndpoint.offset;
      }
    }
    // Make the displayed selection handles accessible to a finger.
    if ((position - start).distance <= 22) return ChartAnchorEndpoint.start;
    if (pattern.tool.oneAnchor) return null;
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
      _eraserMode = false;
      _rulerMode = false;
      _measureStart = null;
      _placingShort = short;
      _placingRectangle = rectangle;
      if (tool != null) _drawingTool = tool;
      _shortEntryAnchor = null;
      _shortStopPrice = null;
      _rectangleFirstCorner = null;
      _pendingAnchor = null;
      _secondChannelAnchor = null;
      _selectedShort = null;
      _selectedRectangle = null;
      _selectedLine = null;
      _selectedPattern = null;
    });
  }

  Widget _buildDrawingRail(double height) => Positioned(
    left: 0, top: math.min(56.0, height * .11), bottom: 12, width: 38,
    child: Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
        border: Border.all(color: const Color(0xFFF0F0F0)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6)],
      ),
      child: SingleChildScrollView(
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 5),
            child: Icon(Icons.drag_indicator, size: 18, color: Color(0xFFB8B8B8)),
          ),
          IconButton(
            key: const Key('drawing-rail-cursor'),
            tooltip: 'تحريك الشارت',
            onPressed: () => setState(() {
              _drawing = false;
              _eraserMode = false;
              _rulerMode = false;
              _measureStart = null;
              _placingShort = false;
              _placingRectangle = false;
              _pendingAnchor = null;
              _secondChannelAnchor = null;
              _rectangleFirstCorner = null;
            }),
            icon: const Icon(Icons.vertical_align_center, size: 22),
          ),
          if (_showFavoriteShortcuts)
            for (final tool in DrawingFavoriteGroups.fromSelection(
                    _favoriteDrawingTools).values.expand((items) => items))
              if (tool.implemented)
                IconButton(
                  key: Key('drawing-rail-favorite-${tool.name}'),
                  tooltip: tool.label,
                  onPressed: () => _activateCatalogDrawingTool(tool),
                  icon: SizedBox(width: 24, height: 24,
                    child: CustomPaint(painter: DrawingToolGlyphPainter(tool))),
                ),
          IconButton(
            key: const Key('drawing-rail-open-catalog'),
            tooltip: 'أدوات الرسم',
            onPressed: _showDrawingTools,
            icon: const Icon(Icons.edit_outlined, size: 22),
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

  /// Clean Replay layout: a single 48dp source row replaces the live
  /// two-row trading header; the actual plot remains the main surface.
  Widget _compactReplayHeader(List<TradeCandle> candles) {
    final scheme = Theme.of(context).colorScheme;
    final source = _selectedSymbol.source == TradeSource.ctrader
        ? 'cTrader' : 'Binance';
    final warning = _olderLoadError ?? _loadError;
    return Container(
      key: Key(widget.focusMode ? 'chart-focus-header' : 'chart-reference-header'),
      color: scheme.surface,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(children: [
        Flexible(
          flex: 3,
          child: Tooltip(
            message: _replay ? _marketEvidenceLabel :
                'اختر شمعة البداية من التاريخ المتاح',
            child: Text(
              _replay ? 'Replay تاريخي · $source' : 'حدد بداية Replay',
              key: const Key('chart-provenance-header'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: scheme.primary),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(flex: 2, child: Text(_symbol,
          textDirection: TextDirection.ltr, textAlign: TextAlign.end,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
            color: scheme.onSurface))),
        const SizedBox(width: 6),
        Text(_mode == ChartMode.range ? 'R$_rangeTicks' :
          (ChartTimeframeCatalog.displayLabel(_timeframe)),
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        if (warning != null)
          IconButton(
            key: const Key('replay-history-warning'),
            tooltip: warning,
            onPressed: () => _replayMessage(warning),
            icon: const Icon(Icons.info_outline, size: 20),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 44),
            padding: EdgeInsets.zero,
          ),
        IconButton(
          key: const Key('chart-candle-settings-action'),
          tooltip: 'إعدادات الشموع',
          onPressed: _showCandleSettings,
          icon: const Icon(Icons.tune, size: 21),
          constraints: const BoxConstraints(minWidth: 38, minHeight: 44),
          padding: EdgeInsets.zero,
        ),
        IconButton(
          key: const Key('symbol-picker'),
          tooltip: 'اختيار رمز الشارت',
          onPressed: _showSymbolPicker,
          icon: const Icon(Icons.search, size: 21),
          constraints: const BoxConstraints(minWidth: 38, minHeight: 44),
          padding: EdgeInsets.zero,
        ),
      ]),
    );
  }

  Widget _referenceChartHeader(List<TradeCandle> candles) {
    final hasVerifiedPrices = candles.isNotEmpty;
    final fetchingRangeTicks = _mode == ChartMode.range &&
        _loading && _liveRequested && !hasVerifiedPrices;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? Colors.white : const Color(0xFF101010);
    final source = _selectedSymbol.source == TradeSource.ctrader
        ? 'cTrader' : 'Binance';
    final quoteCurrency = _selectedSymbol.source == TradeSource.binance
        ? 'USDT' : 'USD';
    return LayoutBuilder(builder: (context, constraints) {
      final compactWidth = constraints.maxWidth < 360;
      return Container(
      key: const Key('chart-reference-header'),
      height: compactWidth ? 104 : 84,
      color: Theme.of(context).colorScheme.surface,
      child: Stack(children: [
        Positioned(left: 8, top: 4, child: Row(children: [
          Container(
            height: 22, width: 22,
            decoration: BoxDecoration(
              color: const Color(0xFFDBF2EE),
              borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: Icon(Icons.circle, size: 10,
                color: hasVerifiedPrices && (_replay || !_ctraderTimeCandlesStale)
                    ? const Color(0xFF047660) : Colors.grey),
          ),
          Container(
            height: 22, width: 23,
            decoration: const BoxDecoration(
              color: Color(0xFFFCE1ED),
              borderRadius: BorderRadius.horizontal(right: Radius.circular(13))),
            alignment: Alignment.center,
            child: const Icon(Icons.waves,
                color: Color(0xFFAB2373), size: 19),
          ),
        ])),
        if (compactWidth)
          Positioned(left: 65, top: 2, child: _buildChartQuickActions()),
        Positioned(right: 5, top: 4, child: OutlinedButton.icon(
          onPressed: _showSymbolPicker,
          style: OutlinedButton.styleFrom(
            foregroundColor: ink,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            minimumSize: const Size(54, 28),
            side: const BorderSide(color: Color(0xFFE6E6E6)),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5)),
          ),
          icon: const Icon(Icons.keyboard_arrow_down, size: 15),
          label: Text(quoteCurrency, textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 12)),
        )),
        Positioned(left: 8, top: compactWidth ? 47 : 27, right: 66,
          child: GestureDetector(
            onTap: !_liveRequested
                ? (widget.onOpenAccount ?? _notifyUnconnected) : null,
            child: Tooltip(
              message: _marketEvidenceLabel,
              child: Text(
                hasVerifiedPrices
                    ? (_replay ? 'Replay تاريخي · $source' : _ctraderTimeCandlesStale
                        ? 'شموع $source · ${widget.controller.recentQuoteFor(_selectedSymbol) != null ? 'الشموع أقدم من السعر' : 'بيانات متأخرة'}'
                        : 'شموع $source')
                    : fetchingRangeTicks
                        ? 'جارِ التحقق من تيكات BID · cTrader'
                        : 'لا توجد أسعار موثقة · $source',
                key: const Key('chart-provenance-header'),
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.left,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12,
                    color: fetchingRangeTicks
                        ? TradeColors.blue
                        : hasVerifiedPrices && (_replay || !_ctraderTimeCandlesStale)
                            ? const Color(0xFF047660) : TradeColors.negative),
              ),
            ),
          )),
        // The previous '3' button was an inert mock control. All actions in
        // this compact row are functional and stay visible on small phones.
        Positioned(left: 8, top: compactWidth ? 65 : 43, right: 6,
          child: Row(children: [
            OutlinedButton.icon(
              key: const Key('chart-candle-settings-action'),
              onPressed: _showCandleSettings,
              style: OutlinedButton.styleFrom(
                foregroundColor: ink,
                minimumSize: const Size(0, 37),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                side: BorderSide(color: Theme.of(context).dividerColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8))),
              icon: const Icon(Icons.tune, size: 17),
              label: const Text('الشموع',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 3),
            IconButton(
              key: const Key('chart-move-mode'),
              tooltip: 'تحريك الشارت',
              onPressed: _enableMoveChart,
              icon: Icon(Icons.pan_tool_alt_outlined,
                size: 21, color: !_drawing ? TradeColors.blue : ink),
              constraints: const BoxConstraints(
                minWidth: 34, minHeight: 36),
              padding: EdgeInsets.zero,
            ),
            IconButton(
              key: const Key('chart-zoom-in'),
              tooltip: 'تكبير الشارت',
              onPressed: () => _zoomBy(1.25),
              icon: Icon(Icons.add_circle_outline, color: ink, size: 21),
              constraints: const BoxConstraints(
                minWidth: 34, minHeight: 36),
              padding: EdgeInsets.zero,
            ),
            IconButton(
              key: const Key('chart-zoom-out'),
              tooltip: 'تصغير الشارت',
              onPressed: () => _zoomBy(.8),
              icon: Icon(Icons.remove_circle_outline, color: ink, size: 21),
              constraints: const BoxConstraints(
                minWidth: 34, minHeight: 36),
              padding: EdgeInsets.zero,
            ),
            IconButton(
              key: const Key('chart-back-to-live'),
              tooltip: 'العودة إلى أحدث شمعة',
              onPressed: () {
                _stopMomentum();
                setState(() => _viewport = _viewport.jumpToLatest());
              },
              icon: Icon(Icons.last_page_outlined, color: ink, size: 21),
              constraints: const BoxConstraints(
                minWidth: 34, minHeight: 36),
              padding: EdgeInsets.zero,
            ),
            if (!compactWidth) _buildChartQuickActions(),
          ]),
        ),
      ]),
      );
    });
  }

  bool get _hasSelectedDrawing => _drawing &&
      (_selectedLine != null || _selectedPattern != null ||
       _selectedShort != null || _selectedRectangle != null);

  void _deleteSelectedChartDrawing() {
    if (!_hasSelectedDrawing) return;
    setState(() {
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
    });
  }

  // Guidance stays over the chart instead of adding a second footer below
  // the reference toolbar. Its overlay ignores input so chart gestures work.
  String? get _activeChartHint {
    if (_placingShort) {
      return _shortEntryAnchor == null
          ? 'مركز بيع: المس الشارت لتحديد سعر الدخول'
          : _shortStopPrice == null
              ? 'حدد وقف الخسارة فوق سعر الدخول'
              : 'حدد الهدف أسفل سعر الدخول';
    }
    if (_placingRectangle) {
      return _rectangleFirstCorner == null
          ? 'المستطيل: اختر الزاوية الأولى على الشارت'
          : 'المستطيل: اختر الزاوية المقابلة لتحديد السعر والزمن';
    }
    if (_pendingAnchor != null && _drawing) {
      return _secondChannelAnchor != null
          ? 'القناة المتوازية: حدد النقطة الثالثة لضبط عرض القناة'
          : 'المس الشارت لتحديد النقطة الثانية للرسم';
    }
    if (_drawing && _selectedPattern != null) {
      return 'اسحب دائرة البداية أو النهاية لتعديل طرف الرسم فقط';
    }
    return null;
  }

  Widget _buildChartQuickActions() => ChartQuickActions(
    onCandles: _showCandleSettings,
    onChartType: _showChartTypePicker,
    onReplay: _toggleReplay,
    onDrawingTools: _showDrawingTools,
    onAnalysis: _showAnalysisHub,
    onAppearance: _showChartAppearance,
    onIndicators: _showIndicatorCatalog,
    onMove: _enableMoveChart,
    onLatest: () {
      _stopMomentum();
      setState(() {
        _viewport = _viewport.jumpToLatest();
        _crosshair = null;
      });
    },
    onRange: _showRangeSettings,
    rangeMode: _mode == ChartMode.range,
    onFocusMode: widget.onToggleFocusMode,
    focusMode: widget.focusMode,
  );

  /// The chart keeps its controller, drawings, broker history and Replay
  /// cursor when the shell hides navigation; only presentation changes.
  Widget _focusedChartHeader(List<TradeCandle> candles) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('chart-focus-header'),
      height: 48,
      color: colors.surface,
      child: Row(children: [
        IconButton(
          key: const Key('chart-focus-exit'),
          tooltip: 'الخروج من وضع الشارت الموسع',
          onPressed: widget.onToggleFocusMode,
          icon: const Icon(Icons.fullscreen_exit, size: 24),
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          padding: EdgeInsets.zero,
        ),
        Expanded(
          child: Text(_symbol, textDirection: TextDirection.ltr,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w800,
              fontSize: 16, color: colors.onSurface)),
        ),
        if (candles.isNotEmpty)
          Icon(Icons.verified_outlined, size: 17,
            color: colors.primary),
        TextButton(
          key: const Key('chart-focus-timeframe'),
          onPressed: _showTimeframePicker,
          child: Text(ChartTimeframeCatalog.displayLabel(_timeframe)),
        ),
        IconButton(
          key: const Key('symbol-picker'),
          tooltip: 'اختيار رمز الشارت',
          onPressed: _showSymbolPicker,
          icon: const Icon(Icons.search, size: 22),
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          padding: EdgeInsets.zero,
        ),
        _buildChartQuickActions(),
      ]),
    );
  }

  Widget _referenceChartToolbar(Color surface) => Container(
    key: const Key('chart-reference-toolbar'),
    color: surface,
    height: 54,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        TextButton(
          key: const Key('symbol-picker'),
          onPressed: _showSymbolPicker,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(0, 48)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(_selectedSymbol.kind == InstrumentKind.gold
                ? 'GOLD' : _symbol,
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontSize: 16,
                    color: Color(0xFF101010), fontWeight: FontWeight.w800)),
            Text(_symbol, textDirection: TextDirection.ltr,
                style: const TextStyle(fontSize: 10,
                    color: Color(0xFF9B9B9B))),
          ]),
        ),
        TextButton(
          key: const Key('timeframe-picker'),
          onPressed: _showTimeframePicker,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(0, 48)),
          child: Text(ChartTimeframeCatalog.displayLabel(_timeframe),
            style: const TextStyle(fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF333333))),
        ),
        // Most used controls remain in the first 390dp; extra tools scroll.
        _iconAction(icon: Icons.bar_chart_outlined,
            label: 'نوع الشموع', onPressed: _showChartTypePicker),
        if (!_replay && !_replaySelectingStart)
          _iconAction(icon: Icons.replay_circle_filled_outlined,
              label: 'تشغيل Replay داخل الشارت',
              onPressed: _toggleReplay),
        _iconAction(icon: Icons.edit_outlined,
            label: 'أدوات الرسم', active: _drawing,
            onPressed: _showDrawingTools),
        if (_hasSelectedDrawing)
          _iconAction(icon: Icons.tune,
              label: 'خصائص الرسم المحدد',
              onPressed: _selectedRectangle != null ? _rectangleProperties :
                  _selectedShort != null ? _shortProperties : _editSelectedDrawing),
        if (_hasSelectedDrawing)
          _iconAction(icon: Icons.delete_outline,
              label: 'حذف الرسم المحدد', onPressed: _deleteSelectedChartDrawing),
        if (_lineUndo.isNotEmpty)
          _iconAction(icon: Icons.undo, label: 'تراجع',
              onPressed: _undoDrawing),
        if (_lineRedo.isNotEmpty)
          IconButton(
            key: const Key('drawing-redo'),
            tooltip: 'إعادة الرسم',
            onPressed: _redoDrawing,
            icon: const Icon(Icons.redo, size: 22)),
        _iconAction(icon: Icons.tune_outlined,
            label: 'محور التحليل', onPressed: _showAnalysisHub),
        _iconAction(icon: Icons.functions, label: 'المؤشرات',
            active: _showIndicators,
            onPressed: () => setState(() => _showIndicators = !_showIndicators)),
        if (_panelSettings.paneButtons == ChartButtonVisibility.always ||
            (_panelSettings.paneButtons == ChartButtonVisibility.onTap &&
              _panelChartTouched)) ...[
          _iconAction(icon: Icons.zoom_in_outlined,
              label: 'تكبير الشارت من الشريط', onPressed: () => _zoomBy(1.25)),
          _iconAction(icon: Icons.zoom_out_outlined,
              label: 'تصغير الشارت من الشريط', onPressed: () => _zoomBy(.8)),
        ],
        if (_panelSettings.navigationButtons == ChartButtonVisibility.always ||
            (_panelSettings.navigationButtons == ChartButtonVisibility.onTap &&
              _panelChartTouched))
          _iconAction(icon: Icons.last_page, label: 'العودة إلى أحدث شمعة من الشريط',
              onPressed: () {
                _stopMomentum();
                setState(() => _viewport = _viewport.jumpToLatest());
              }),
        if (widget.journal != null && !_replay)
          _iconAction(icon: Icons.add_chart, label: 'صفقة تجريبية',
              onPressed: _openPaperOrder),
        if (_mode == ChartMode.range)
          TextButton(onPressed: _showRangeSettings,
              child: Text('مدى $_rangeTicks')),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_symbolSettingsOpen) {
      return ChartSymbolSettingsPage(
        initial: _symbolSettings,
        onCancel: () => setState(() {
          _symbolSettingsOpen = false;
          _panelSettingsOpen = _symbolSettingsReturnToPanel;
          _symbolSettingsReturnToPanel = false;
        }),
        onApply: (updated) {
          // Redraw the same cached bars; never issue a data request here.
          setState(() {
            _symbolSettings = updated;
            _symbolSettingsOpen = false;
            _symbolSettingsReturnToPanel = false;
            _panelSettingsOpen = false;
          });
          unawaited(_saveSymbolSettings(updated));
        },
      );
    }
    if (_scaleSettingsOpen) {
      return ChartScaleSettingsPage(
        initial: _scaleSettings,
        onCancel: () => setState(() {
          _scaleSettingsOpen = false;
          _panelSettingsOpen = true;
        }),
        onApply: (updated) {
          // Presentation only: keep downloaded OHLC, viewport and Replay.
          setState(() {
            _scaleSettings = updated;
            _scaleSettingsOpen = false;
            _panelSettingsOpen = false;
          });
          unawaited(_saveScaleSettings(updated));
        },
      );
    }
    if (_panelSettingsOpen) {
      return ChartPanelSettingsPage(
        initial: _panelSettings,
        onOpenScales: () => setState(() {
          _scaleSettingsOpen = true;
          _panelSettingsOpen = false;
        }),
        onOpenSymbol: () => setState(() {
          _symbolSettingsReturnToPanel = true;
          _symbolSettingsOpen = true;
          _panelSettingsOpen = false;
        }),
        onCancel: () => setState(() => _panelSettingsOpen = false),
        onApply: (updated) {
          setState(() {
            _panelSettings = updated;
            _viewport = _viewport.withRightMarginBars(
              updated.rightMarginBars.toDouble());
            _panelSettingsOpen = false;
          });
          unawaited(_savePanelSettings(updated));
        },
      );
    }
    final colors = Theme.of(context).colorScheme;
    final candles = _displayCandles;
    final surface = colors.surface;
    final chartHint = _activeChartHint;
    final replayUi = _replay || _replaySelectingStart;
    return Column(children: [
      replayUi ? _compactReplayHeader(candles)
        : widget.focusMode ? _focusedChartHeader(candles)
        : _referenceChartHeader(candles),
      if (_mode == ChartMode.range && !replayUi)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          color: TradeColors.blue.withValues(alpha: .07),
          child: Text(_liveRequested
              ? 'مدى $_rangeTicks نقطة · ${!_rangeSourceSupported ? 'غير مدعوم لهذا المصدر' : _loading && _actualRange.isEmpty ? 'تحميل صفحات BID الموثقة' : _actualRange.isEmpty ? 'لا توجد تيكات BID موثقة' : _actualRange.length == 1 ? 'شمعة قيد التكوين من BID؛ جرّب مدى أصغر' : 'شموع محسوبة من تيكات BID لـ cTrader'}'
              : 'مدى $_rangeTicks · اربط حساب cTrader للحصول على تيكات BID الحقيقية',
              style: const TextStyle(fontSize: 11, color: TradeColors.blue)),
        ),
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      if (_loadError != null && _liveRequested && !replayUi)
        MaterialBanner(content: Text(_loadError!), actions: [
          TextButton(onPressed: _loadRealHistory, child: const Text('إعادة المحاولة')),
        ]),
      if (_mode == ChartMode.heikinAshi &&
          _heikinCache.isPendingFor(_actualCandles))
        const LinearProgressIndicator(minHeight: 2),
      if (_olderLoading) const LinearProgressIndicator(minHeight: 2),
      if (_olderLoadError != null && !replayUi)
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
          final selecting = _replaySelectingStart && candles.isNotEmpty &&
              _replayCandidateIndex < candles.length &&
              _replayCandidateIndex < _replaySourceTimestamps.length;
          final replayLineX = selecting
              ? _viewport.chartX(index: _replayCandidateIndex,
                  candleCount: candles.length, plotWidth: plotWidth)
              : 0.0;
          final replayLineY = selecting
              ? _priceScale(candles, plotWidth, constraints.maxHeight)
                  .y(candles[_replayCandidateIndex].close)
              : 0.0;
          return Stack(children: [
          Positioned.fill(child: Listener(
            onPointerDown: (event) {
              if (_firstChartPointer == null) {
                _firstChartPointer = event.pointer;
                _firstChartDown = event.localPosition;
              }
            },
            onPointerUp: (event) {
              if (_firstChartPointer == event.pointer) {
                _firstChartPointer = null;
                _firstChartDown = null;
              }
            },
            onPointerCancel: (event) {
              if (_firstChartPointer == event.pointer) {
                _firstChartPointer = null;
                _firstChartDown = null;
              }
            },
            child: GestureDetector(
            key: const Key('chart-gesture-area'),
            behavior: HitTestBehavior.opaque,
            onScaleStart: (details) {
              _stopMomentum(); // A new gesture owns the chart immediately.
              if (!_panelChartTouched) setState(() => _panelChartTouched = true);
              // Begin a fresh gesture, independent of any earlier fling.
              // A later second-finger touch rebases the pinch on the viewport
              // the first finger has already moved to.
              _touchGesture = ChartTouchGesture();
              // Anchor ownership and drawing hit-tests to the real
              // touch-down point, NOT the position after touch slop.
              final hitStart = details.pointerCount == 1
                  ? (_firstChartDown ?? details.localFocalPoint)
                  : details.localFocalPoint;
              _draggingPriceAxis = candles.isNotEmpty &&
                  details.pointerCount == 1 &&
                  hitStart.dx >= plotWidth &&
                  !_replaySelectingStart && !_drawing &&
                  !_placingShort && !_placingRectangle;
              // Bottom 24dp is the drawn TIME axis, not the candle plot.
              // Touch there owns an anchored horizontal scale gesture,
              // while touches in the plot continue their usual drag/pinch.
              _draggingTimeAxis = candles.isNotEmpty &&
                  details.pointerCount == 1 &&
                  hitStart.dx < plotWidth &&
                  hitStart.dy >= constraints.maxHeight - 24 &&
                  !_replaySelectingStart && !_drawing &&
                  !_placingShort && !_placingRectangle;
              _gestureFocalX = hitStart.dx;
              _gestureFocalY = hitStart.dy;
              // A touch on the blue Replay line edits the candidate. Touches
              // elsewhere still pan the chart; a second finger still pinches.
              final lineX = _viewport.chartX(
                index: _replayCandidateIndex,
                candleCount: candles.length,
                plotWidth: plotWidth);
              _replayDraggingStart = _replaySelectingStart &&
                  details.pointerCount == 1 &&
                  (hitStart.dx - lineX).abs() <= 28;
              _draggingShortHandle = null;
              _shortAtDragStart = null;
              _draggingRectangle = false;
              _rectangleDragHandle = null;
              _rectangleAtDragStart = null;
              if (_drawing && !_drawingsLocked && _drawingsVisible &&
                  !_eraserMode && !_rulerMode && details.pointerCount == 1) {
                final scale = _priceScale(candles, plotWidth, constraints.maxHeight);
                final rectangleHit = PriceRectangleGeometry.hitTest(
                    hitStart, _rectangles, _viewport,
                    scale, candles.length, plotWidth);
                final shortHit = rectangleHit == null
                    ? _hitShortPosition(hitStart,
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
                    ? _hitSelectedHandle(hitStart,
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
                    ? _hitLine(hitStart.dy, scale) : null;
                _draggingLine = _selectedLine != null;
                if (_draggedEndpoint != null) {
                  _draggingPattern = true;
                } else {
                  _selectedPattern = rectangleHit != null || shortHit != null ||
                      _draggingLine ? null :
                      _hitPattern(hitStart, scale,
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
              // Measure chart interactions separately in Android Profile
              // mode: idle/menu frame timings must not pollute pan/pinch p95.
              _profileTouchGesture(
                _draggingPriceAxis ? ChartFrameInteraction.priceAxis :
                _draggingTimeAxis ? ChartFrameInteraction.timeAxis :
                details.pointerCount > 1 ? ChartFrameInteraction.pinch :
                _replayDraggingStart ? ChartFrameInteraction.replaySelection :
                (_draggingRectangle || _draggingShortHandle != null ||
                    _draggingLine || _draggingPattern)
                    ? ChartFrameInteraction.drawing
                    : ChartFrameInteraction.pan,
                candles,
              );
              // Reveal toolbar/handles once; touch updates avoid full rebuilds.
              if (_draggingRectangle) setState(() {});
            },
            onScaleUpdate: (details) {
              if (details.pointerCount > 1) {
                // A second finger starts a distinct pinch cohort. The
                // previous pan/ruler cohort ends before this switch.
                _profileTouchGesture(ChartFrameInteraction.pinch, candles);
              }
              if (_draggingTimeAxis && details.pointerCount == 1) {
                final next = _viewport.dragTimeAxis(
                  deltaX: details.focalPointDelta.dx,
                  anchorX: _gestureFocalX,
                  plotWidth: plotWidth,
                  candleCount: candles.length,
                );
                if (next != _viewport) {
                  // Candle painter, time ticks, source price scale, drawing
                  // overlays and Replay practice levels use this same live
                  // viewport; avoid rebuilding the header every touch frame.
                  _viewport = next;
                  _chartRepaint.value++;
                  _prefetchOlderAtEdge(plotWidth, candles.length);
                }
                return;
              }
              if (_draggingTimeAxis && details.pointerCount > 1) {
                _draggingTimeAxis = false;
                // A second finger takes over with the existing pinch
                // rebase: no sudden jump from the pointer-centroid change.
              }
              if (_draggingPriceAxis && details.pointerCount == 1) {
                final current = _priceScale(
                    candles, plotWidth, constraints.maxHeight);
                final changed = current.dragPriceAxis(
                  deltaY: details.focalPointDelta.dy,
                  focalY: details.localFocalPoint.dy,
                );
                if (!identical(current, changed)) {
                  _manualPriceScale = changed;
                  _manualPriceScaleKey = _currentPriceScaleKey;
                  // Keep the price ruler, candles and drawing overlays on
                  // one identical live price coordinate system.
                  _chartRepaint.value++;
                }
                return;
              }
              if (_draggingPriceAxis && details.pointerCount > 1) {
                _draggingPriceAxis = false;
                // The second finger now belongs to the usual anchored pinch.
              }
              if (_replaySelectingStart && _replayDraggingStart) {
                if (details.pointerCount == 1) {
                  final candidate = ReplayStartResolver.atX(
                    viewport: _viewport,
                    x: details.localFocalPoint.dx,
                    plotWidth: plotWidth,
                    candleCount: candles.length,
                    completedCount: _totalBars,
                    fallbackIndex: _replayCandidateIndex,
                  );
                  if (candidate != _replayCandidateIndex) {
                    setState(() => _replayCandidateIndex = candidate);
                  }
                  return;
                }
                // Let two-finger pinch take over, with the touch rebased.
                _replayDraggingStart = false;
              }
              if (_draggingRectangle && details.pointerCount == 1) {
                final scale = _priceScale(
                    candles, plotWidth, constraints.maxHeight);
                _updateRectangleDrag(details.localFocalPoint,
                    scale, plotWidth, candles.length);
                // Current coordinates are read from the live drawing list.
                // Do not invalidate the candle canvas or header each frame.
                _rectangleRepaint.value++;
                return;
              }
              final nextViewport = _touchGesture.update(
                viewport: _viewport,
                pointerCount: details.pointerCount,
                focalX: details.localFocalPoint.dx,
                scale: details.scale,
                deltaX: details.focalPointDelta.dx,
                plotWidth: plotWidth,
                candleCount: candles.length,
              );
              // Adding/removing a finger shifts Flutter's gesture centroid.
              // Do not reinterpret that shift as a candle pan, zoom or edit.
              if (_touchGesture.ignoredPointerTransition) return;
              // The retained candle painter observes these exact live
              // source-anchor arrays. Updating guides via setState on each
              // touch sample would rebuild toolbars and copy drawing lists.
              if (details.pointerCount == 1 &&
                  !_draggingRectangle && _draggingShortHandle == null &&
                  (_draggingLine || _draggingPattern)) {
                final scale = _priceScale(
                    candles, plotWidth, constraints.maxHeight);
                if (_updateDraggedGuide(details.localFocalPoint, scale,
                    plotWidth, candles.length)) {
                  _chartRepaint.value++;
                }
                return;
              }
              final movingDrawing = _draggingRectangle ||
                  _draggingShortHandle != null || _draggingLine ||
                  _draggingPattern;
              if (!movingDrawing && nextViewport == _viewport) return;
              // Regular one/two finger gestures only change candle geometry.
              // Keep the header and expensive control tree out of each frame.
              if (chartCanUsePaintOnlyViewportUpdate(
                selectingReplayStart: _replaySelectingStart,
                crosshairVisible: _crosshair != null,
                movingDrawing: movingDrawing,
                visiblePriceRectangles: _drawingsVisible && _rectangles.isNotEmpty,
                priceRectanglesFollowViewport: true,
                replayTradeLevelsVisible: _replay && _training.trades.isNotEmpty,
                replayTradeLevelsFollowViewport: true,
              )) {
                _viewport = nextViewport;
                _chartRepaint.value++;
                _prefetchOlderAtEdge(plotWidth, candles.length);
                return;
              }
              setState(() {
              if (_draggingRectangle && details.pointerCount == 1) {
                final scale = _priceScale(candles, plotWidth, constraints.maxHeight);
                _updateRectangleDrag(details.localFocalPoint, scale,
                    plotWidth, candles.length);
              } else if (_draggingShortHandle != null && details.pointerCount == 1) {
                final scale = _priceScale(candles, plotWidth, constraints.maxHeight);
                _updateShortDrag(details.localFocalPoint, scale,
                    plotWidth, candles.length);
              } else if (details.pointerCount > 1 || _crosshair == null) {
                // Rebased, incremental touch transform; chart geometry and
                // source OHLC remain untouched.
                _viewport = nextViewport;
              }
              });
              // The same paging threshold also applies during momentum.
              if (_draggingShortHandle == null &&
                  !_draggingLine && !_draggingPattern && !_draggingRectangle) {
                _prefetchOlderAtEdge(plotWidth, candles.length);
              }
            },
            onScaleEnd: (details) {
              // Release flushes only measured touch frames. Subsequent
              // toolbars/menus and idle refreshes belong to no gesture.
              _frameProfiler.endInteraction();
              if (_draggingTimeAxis) {
                _draggingTimeAxis = false;
                // Commit the latest scale to any snapshot-only UI once,
                // after the finger leaves the ruler. Never fling the axis.
                setState(() {});
                return;
              }
              if (_draggingPriceAxis) {
                _draggingPriceAxis = false;
                // Only one widget refresh after the completed axis gesture.
                setState(() {});
                return;
              }
              final rectangleEdited = _draggingRectangle;
              final guideEdited = _draggingLine || _draggingPattern;
              final editing = _replayDraggingStart || guideEdited ||
                  _draggingShortHandle != null || _draggingRectangle;
              _replayDraggingStart = false;
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
                  horizontalTravel: _touchGesture.horizontalTravel,
                  candleCount: candles.length,
                  multiTouch: _touchGesture.hadMultiTouch,
                  editingDrawing: editing || _crosshair != null,
                  reducedMotion: MediaQuery.disableAnimationsOf(context))) {
                _startMomentum(velocity, plotWidth);
              }
              // Reconcile selection/undo actions only once at release.
              // The candle painter already displayed each intermediate move.
              if ((rectangleEdited || guideEdited) && mounted) {
                setState(() {});
              }
            },
            onDoubleTapDown: (details) =>
                _doubleTapChartX = details.localPosition.dx,
            onDoubleTap: () {
              _stopMomentum();
              if (_doubleTapChartX >= plotWidth) {
                _resetPriceAxisToAuto();
              } else {
                setState(() {
                  _viewport = _freshViewport();
                  _crosshair = null;
                });
              }
            },
            onLongPressStart: (details) {
              _stopMomentum();
              setState(() => _crosshair = details.localPosition);
            },
            onLongPressMoveUpdate: (details) {
              _crosshair = details.localPosition;
              _chartRepaint.value++;
            },
            onLongPressEnd: (_) => setState(() => _crosshair = null),
            onTapUp: (details) {
              if (_replaySelectingStart &&
                  details.localPosition.dx <= plotWidth) {
                final candidate = ReplayStartResolver.atX(
                  viewport: _viewport,
                  x: details.localPosition.dx,
                  plotWidth: plotWidth,
                  candleCount: candles.length,
                  completedCount: _totalBars,
                  fallbackIndex: _replayCandidateIndex);
                setState(() => _replayCandidateIndex = candidate);
                return;
              }
              if (!_drawing || _drawingsLocked ||
                  details.localPosition.dx > plotWidth) return;
              final scale = _priceScale(candles, plotWidth, constraints.maxHeight);
              if (_rulerMode) {
                final anchor = _anchorAt(details.localPosition,
                    scale, plotWidth, candles.length);
                if (anchor == null) return;
                if (_measureStart == null) {
                  setState(() => _measureStart = anchor);
                } else {
                  final start = _measureStart!;
                  final distance = anchor.price - start.price;
                  final percent = start.price == 0 ? 0.0
                      : distance / start.price * 100;
                  final bars = (anchor.index - start.index).abs();
                  setState(() {
                    _measureStart = null;
                    if (!_continueDrawing) {
                      _rulerMode = false;
                      _drawing = false;
                    }
                  });
                  _drawingNotice('المقياس: ${distance.toStringAsFixed(3)} '
                      '(${percent.toStringAsFixed(2)}%) · $bars شمعة');
                }
                return;
              }
              if (_eraserMode) {
                if (!_drawingsVisible) return;
                final rectangleHit = PriceRectangleGeometry.hitTest(
                    details.localPosition, _rectangles, _viewport,
                    scale, candles.length, plotWidth);
                final shortHit = _hitShortPosition(details.localPosition,
                    scale, plotWidth, candles.length);
                final lineHit = _hitLine(details.localPosition.dy, scale);
                final patternHit = _hitPattern(details.localPosition,
                    scale, plotWidth, candles.length);
                if (rectangleHit == null && shortHit == null &&
                    lineHit == null && patternHit == null) return;
                setState(() {
                  _saveDrawingUndo();
                  if (rectangleHit != null) {
                    _rectangles.removeAt(rectangleHit.$1);
                  } else if (shortHit != null) {
                    _shortPositions.removeAt(shortHit.$1);
                  } else if (lineHit != null) {
                    _levels.removeAt(lineHit);
                  } else if (patternHit != null) {
                    _patterns.removeAt(patternHit);
                  }
                  _selectedRectangle = null;
                  _selectedShort = null;
                  _selectedLine = null;
                  _selectedPattern = null;
                  if (!_continueDrawing) {
                    _eraserMode = false;
                    _drawing = false;
                  }
                });
                return;
              }
              if (!_drawingsVisible) return;
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
                  if (_drawingTool.oneAnchor) {
                    _saveDrawingUndo();
                    _patterns.add(ChartPattern(
                      tool: _drawingTool, start: anchor, end: anchor));
                    _selectedPattern = _patterns.length - 1;
                    _selectedLine = null;
                    _selectedShort = null;
                    _pendingAnchor = null;
                    _secondChannelAnchor = null;
                  } else if (_pendingAnchor == null) {
                    _pendingAnchor = anchor;
                  } else if (_drawingTool.threeAnchors &&
                      _secondChannelAnchor == null) {
                    _secondChannelAnchor = anchor;
                  } else {
                    _saveDrawingUndo();
                    _patterns.add(ChartPattern(
                      tool: _drawingTool,
                      start: _pendingAnchor!,
                      end: _secondChannelAnchor ?? anchor,
                      offsetAnchor: _secondChannelAnchor == null
                          ? null : anchor,
                    ));
                    _selectedPattern = _patterns.length - 1;
                    _selectedLine = null;
                    _selectedShort = null;
                    _pendingAnchor = null;
                    _secondChannelAnchor = null;
                  }
                  if (!_continueDrawing && _pendingAnchor == null &&
                      _secondChannelAnchor == null) _drawing = false;
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
                if (!_continueDrawing) _drawing = false;
              });
            },
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size.infinite,
                painter: _CandleChartPainter(
                  candles: candles,
                  rangeMode: _mode == ChartMode.range,
                  timestamps: _mode == ChartMode.range
                      ? _rangeBarTimestamps : _actualTimestamps,
                  dark: Theme.of(context).brightness == Brightness.dark,
                  viewportSnapshot: _viewport,
                  crosshairSnapshot: _crosshair,
                  viewportProvider: () => _viewport,
                  crosshairProvider: () => _crosshair,
                  priceScaleProvider: (axisWidth, height) =>
                      _priceScale(candles, axisWidth, height),
                  sourceQuoteProvider: () => _replay || !widget.active
                      ? null : widget.controller.recentQuoteFor(_selectedSymbol),
                  repaint: _chartRepaint,
                  textCache: _chartTextCache,
                  // Dynamic geometry for edits; immutable copies below remain
                  // for shouldRepaint after genuine widget rebuilds.
                  levelsProvider: () => _drawingsVisible
                      ? _levels : const <double>[],
                  patternsProvider: () => _drawingsVisible
                      ? _patterns : const <ChartPattern>[],
                  selectedLineProvider: () => _drawing && _drawingsVisible
                      ? _selectedLine : null,
                  selectedPatternProvider: () => _drawing && _drawingsVisible
                      ? _selectedPattern : null,
                  levels: _drawingsVisible ? List<double>.unmodifiable(_levels) : const [],
                  patterns: _drawingsVisible ? List<ChartPattern>.unmodifiable(_patterns) : const [],
                  shortPositions: _drawingsVisible ? List<ChartShortPosition>.unmodifiable(_shortPositions) : const [],
                  selectedLine: _drawing && _drawingsVisible ? _selectedLine : null,
                  selectedPattern: _drawing && _drawingsVisible ? _selectedPattern : null,
                  selectedShort: _drawing && _drawingsVisible ? _selectedShort : null,
                  showShortLabels: _showShortLabels,
                  indicator: _showIndicators,
                  panel: _panelSettings,
                  scaleSettings: _scaleSettings,
                  symbolSettings: _symbolSettings,
                  actualPriceCandles: _mode == ChartMode.range
                    ? const [] : _replay
                      ? CandlePrefix(_actualCandles, _visibleThrough)
                      : _actualCandles,
                  previousSessionClose: _mode == ChartMode.range
                    ? null : ChartAxisSourceLabels.previousSessionClose(
                      _actualBars, candles.length),
                  sourceQuote: _replay ? null
                    : widget.controller.recentQuoteFor(_selectedSymbol),
                  replayActive: _replay,
                ),
              ),
            ),
          ))),
          // Blue Replay cursor is a visual overlay over verified history;
          // it cannot modify prices or reveal future bars after confirmation.
          if (selecting)
            Positioned.fill(child: IgnorePointer(child: RepaintBoundary(
              child: CustomPaint(
                key: const Key('replay-start-overlay'),
                size: Size.infinite,
                painter: ReplayStartOverlayPainter(
                  cursorX: replayLineX,
                  plotWidth: plotWidth,
                  dark: Theme.of(context).brightness == Brightness.dark),
              ),
            ))),
          if (selecting && replayLineX >= 0 && replayLineX <= plotWidth)
            Positioned(
              left: (replayLineX - 15)
                  .clamp(0.0, math.max(0.0, plotWidth - 30)).toDouble(),
              top: (replayLineY - 15).clamp(35.0,
                  math.max(35.0, constraints.maxHeight - 48)).toDouble(),
              child: const IgnorePointer(child: Icon(
                Icons.content_cut, key: Key('replay-start-scissors'),
                color: Color(0xFF171717), size: 28)),
            ),
          if (selecting)
            Positioned(
              left: 6, top: 7,
              child: IgnorePointer(child: Container(
                key: const Key('replay-start-time'),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface
                    .withValues(alpha: .92),
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 5),
                child: Text(
                  'UTC ${DateTime.fromMillisecondsSinceEpoch(
                    _replaySourceTimestamps[_replayCandidateIndex],
                    isUtc: true).toIso8601String().substring(0, 16)
                      .replaceFirst('T', ' ')}',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              )),
            ),
          if (_drawingsVisible && candles.isNotEmpty && _rectangles.isNotEmpty)
            Positioned.fill(child: IgnorePointer(child: RepaintBoundary(
              child: CustomPaint(
                painter: ChartPriceRectanglePainter(
                  textCache: _chartTextCache,
                  drawings: List<ChartPriceRectangle>.unmodifiable(_rectangles),
                  drawingsProvider: () => _rectangles,
                  selectedIndex: _drawing ? _selectedRectangle : null,
                  viewport: _viewport,
                  scale: _priceScale(candles, plotWidth, constraints.maxHeight),
                  // Keep selected handles, price tags and the selected
                  // chart timezone on the SAME source candle and viewport.
                  viewportProvider: () => _viewport,
                  scaleProvider: () => _priceScale(
                      candles, plotWidth, constraints.maxHeight),
                  repaint: _rectanglePaintSignals,
                  candleCount: candles.length,
                  plotWidth: plotWidth,
                  dark: Theme.of(context).brightness == Brightness.dark,
                  timeZone: _symbolSettings.timeZone,
                  timestamps: _mode == ChartMode.range
                      ? _rangeBarTimestamps : _actualTimestamps,
                ),
                size: Size.infinite,
              ),
            ))),
          // Practice orders belong to the current Replay prefix only.
          // A separate, non-interactive painter keeps drawing tools and
          // gesture handling untouched. Each order owns distinct SL/TP
          // segments, rather than connecting unrelated trade levels.
          if (_replay && candles.isNotEmpty && _training.trades.isNotEmpty)
            Positioned.fill(child: IgnorePointer(child: RepaintBoundary(
              child: CustomPaint(
                key: const Key('replay-practice-levels-overlay'),
                size: Size.infinite,
                painter: ReplayTradeOverlayPainter(
                  trades: _training.trades,
                  viewport: _viewport,
                  scale: _priceScale(candles, plotWidth, constraints.maxHeight),
                  // Share live viewport and price auto-scale with candle painter.
                  viewportProvider: () => _viewport,
                  scaleProvider: () => _priceScale(
                      candles, plotWidth, constraints.maxHeight),
                  repaint: _chartRepaint,
                  candleCount: candles.length,
                  plotWidth: plotWidth,
                ),
              ),
            ))),
          // Quick replay trading follows the reference's floating
          // buy/sell/flatten strip without squeezing the chart or time axis.
          // Entries open the existing historical-only practice ticket.
          if (_replay && _replayShowTradingButtons && candles.isNotEmpty)
            Positioned(
              left: 8, right: 65, bottom: 28,
              child: Container(
                key: const Key('replay-inline-trading'),
                height: 46,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface
                      .withValues(alpha: .94),
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: .10),
                    blurRadius: 7,
                    offset: const Offset(0, 2),
                  )],
                ),
                child: Row(children: [
                  Expanded(child: OutlinedButton(
                    key: const Key('replay-flatten-trades'),
                    onPressed: _training.openTradeCount == 0
                        ? null : _flattenReplayTrainingTrades,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 36),
                    ),
                    child: const Text('تسطيح',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(fontSize: 12)),
                  )),
                  const SizedBox(width: 4),
                  Expanded(child: FilledButton(
                    key: const Key('replay-inline-buy'),
                    onPressed: () => _openTrainingOrderDialog(
                        initialSide: ReplaySide.buy),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF009778),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 36),
                    ),
                    child: const Text('شراء',
                      style: TextStyle(fontSize: 13)),
                  )),
                  const SizedBox(width: 4),
                  Expanded(child: FilledButton(
                    key: const Key('replay-inline-sell'),
                    onPressed: () => _openTrainingOrderDialog(
                        initialSide: ReplaySide.sell),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD94959),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 36),
                    ),
                    child: const Text('بيع',
                      style: TextStyle(fontSize: 13)),
                  )),
                ]),
              ),
            ),
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
          // Paint-only OHLC inspection of the exact snapped source candle.
          if (_crosshair != null && !selecting && chartHint == null &&
              candles.isNotEmpty)
            _crosshairOhlcInspector(
              candles: candles,
              timestamps: _mode == ChartMode.range
                  ? _rangeBarTimestamps : _actualTimestamps,
              plotWidth: plotWidth,
              chartHeight: constraints.maxHeight,
              surface: surface,
            ),
          if (candles.isNotEmpty &&
              (!replayUi || _replayShowDrawingTools))
            _buildDrawingRail(constraints.maxHeight),
          if (candles.isNotEmpty && chartHint != null)
            Positioned(
              top: 8, left: 78, right: 68,
              child: IgnorePointer(
                child: Container(
                  key: const Key('chart-interaction-hint-overlay'),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: surface.withValues(alpha: .94),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: TradeColors.blue.withValues(alpha: .25)),
                  ),
                  child: Text(
                    chartHint,
                    key: _placingShort
                        ? const Key('short-position-placement-hint')
                        : _placingRectangle
                            ? const Key('price-rectangle-placement-hint')
                            : null,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: TradeColors.blue),
                  ),
                ),
              ),
            ),
          // TradingView-style one-tap return to the genuine OHLC autoscale.
          // Show only after the owner manually adjusted the price ruler;
          // unlike a constantly running overlay, this is not rebuilt on pan.
          if (_priceScaleManual)
            Positioned(
              right: 3, top: 4,
              child: SizedBox(
                width: 54, height: 26,
                child: TextButton(
                  key: const Key('chart-price-axis-auto'),
                  onPressed: _resetPriceAxisToAuto,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(44, 26),
                  ),
                  child: const Text('AUTO',
                    style: TextStyle(fontSize: 10,
                        fontWeight: FontWeight.w700)),
                ),
              ),
            ),
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
      // No broker-info or drawing-hint footer: chart tools meet navigation.
      // Active drawing guidance now overlays the chart without using height.
      // TradingView reference: Replay sits directly below the plot; drawing
      // toolbar remains below Replay, adjacent to bottom navigation.
      // Retain both bands so Replay never steals the existing drawing actions.
      if (_replay || _replaySelectingStart) _replayControls(context),
      if (!widget.focusMode && !replayUi)
        _referenceChartToolbar(surface),
    ]);
  }

  Widget _crosshairOhlcInspector({
    required List<TradeCandle> candles,
    required List<int> timestamps,
    required double plotWidth,
    required double chartHeight,
    required Color surface,
  }) => Positioned(
    left: 8, top: 8, right: 67,
    child: IgnorePointer(
      child: ValueListenableBuilder<int>(
        valueListenable: _chartRepaint,
        builder: (context, _, __) {
          final cursor = _crosshair;
          if (cursor == null) return const SizedBox.shrink();
          final selected = ChartOhlcInspector.atCrosshair(
            viewport: _viewport,
            touchX: cursor.dx,
            plotWidth: plotWidth,
            candles: candles,
            timestampsUtcMs: timestamps,
          );
          if (selected == null) return const SizedBox.shrink();
          final scale = _priceScale(candles, plotWidth, chartHeight);
          final digits = _symbolSettings.digitsForTickStep(
            ChartAxisTicks.decimals(
              ChartAxisTicks.interval(scale.minimum, scale.maximum)),
          );
          final ink = Theme.of(context).colorScheme.onSurface;
          final trendColor = selected.rising
              ? TradeColors.positive : TradeColors.negative;
          final style = TextStyle(
            color: ink, fontSize: 11, fontWeight: FontWeight.w600,
          );
          Widget field(String prefix, String key, double price) => Expanded(
            child: Text(
              '$prefix ${selected.formatPrice(price, digits)}',
              key: Key(key),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              style: style,
            ),
          );
          return Semantics(
            label: 'بيانات الشمعة المحددة رقم ${selected.index + 1}',
            child: Container(
              key: const Key('chart-crosshair-ohlc-inspector'),
              padding: const EdgeInsets.symmetric(
                horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: surface.withValues(alpha: .93),
                border: Border(
                  left: BorderSide(color: trendColor, width: 3)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    field('O', 'chart-ohlc-open', selected.candle.open),
                    const SizedBox(width: 5),
                    field('H', 'chart-ohlc-high', selected.candle.high),
                  ]),
                  const SizedBox(height: 2),
                  Row(children: [
                    field('L', 'chart-ohlc-low', selected.candle.low),
                    const SizedBox(width: 5),
                    field('C', 'chart-ohlc-close', selected.candle.close),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _replayControls(BuildContext context) => ReplayMobileControls(
    selecting: _replaySelectingStart,
    playing: _playing,
    visibleCount: _visibleThrough,
    totalBars: _totalBars,
    chartFrame: _timeframe,
    speed: _replaySpeed,
    showTrading: _replayShowTradingButtons,
    showDrawingTools: _replayShowDrawingTools,
    canLoadOlder: _liveRequested &&
        (_mode == ChartMode.range
            ? _rangeHistoryTicks.isNotEmpty : _actualBars.isNotEmpty) &&
        !_historyExhausted &&
        !(_mode == ChartMode.range && _training.trades.isNotEmpty),
    olderLoading: _olderLoading,
    tradeCount: _training.trades.length,
    autoStep: _replayAutoStep,
    onClose: _exitReplay,
    onConfirm: _confirmReplayStart,
    onStartMenu: _handleReplayStartMenu,
    onExtras: _handleReplayExtras,
    onStepMenu: _handleReplayIntervalMenu,
    onReset: () => unawaited(_resetReplayToStart()),
    onStepBack: () => _seekReplay(_visibleThrough - 1),
    onStepForward: () => _seekReplay(_visibleThrough + 1),
    onPlayPause: _togglePlay,
    onSpeed: _setReplaySpeed,
    onChooseAgain: () => unawaited(_chooseReplayStartAgain()),
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
    required this.rangeMode,
    required this.dark,
    required this.viewportSnapshot,
    required this.crosshairSnapshot,
    required ChartViewport Function() viewportProvider,
    required Offset? Function() crosshairProvider,
    required ChartPriceScale Function(double, double) priceScaleProvider,
    required MarketQuote? Function() sourceQuoteProvider,
    required Listenable repaint,
    required this.textCache,
    required List<double> Function() levelsProvider,
    required List<ChartPattern> Function() patternsProvider,
    required int? Function() selectedLineProvider,
    required int? Function() selectedPatternProvider,
    required this.levels,
    required this.patterns,
    required this.shortPositions,
    required this.selectedLine,
    required this.selectedPattern,
    required this.selectedShort,
    required this.showShortLabels,
    required this.indicator,
    required this.panel,
    required this.scaleSettings,
    required this.symbolSettings,
    required this.actualPriceCandles,
    required this.previousSessionClose,
    required this.sourceQuote,
    required this.replayActive,
  }) : _viewportProvider = viewportProvider,
       _crosshairProvider = crosshairProvider,
       _priceScaleProvider = priceScaleProvider,
       _sourceQuoteProvider = sourceQuoteProvider,
       _levelsProvider = levelsProvider,
       _patternsProvider = patternsProvider,
       _selectedLineProvider = selectedLineProvider,
       _selectedPatternProvider = selectedPatternProvider,
       super(repaint: repaint);

  final List<TradeCandle> candles;
  final List<int> timestamps;
  final bool rangeMode;
  final ChartTextLayoutCache textCache;
  final bool dark;
  // Stable build-time values are for shouldRepaint comparisons. The getters
  // below follow motion between widget builds via the repaint notifier.
  final ChartViewport viewportSnapshot;
  final Offset? crosshairSnapshot;
  final ChartViewport Function() _viewportProvider;
  final Offset? Function() _crosshairProvider;
  final ChartPriceScale Function(double, double) _priceScaleProvider;
  final MarketQuote? Function() _sourceQuoteProvider;
  // Live read-only-on-paint callbacks allow frequent pointer edits without
  // rebuilding the toolbar or copying every existing drawing on each move.
  final List<double> Function() _levelsProvider;
  final List<ChartPattern> Function() _patternsProvider;
  final int? Function() _selectedLineProvider;
  final int? Function() _selectedPatternProvider;
  ChartViewport get viewport => _viewportProvider();
  Offset? get crosshair => _crosshairProvider();
  final List<double> levels;
  final List<ChartPattern> patterns;
  final List<ChartShortPosition> shortPositions;
  final int? selectedLine;
  final int? selectedPattern;
  final int? selectedShort;
  final bool showShortLabels;
  final bool indicator;
  final ChartPanelSettings panel;
  final ChartScaleSettings scaleSettings;
  final ChartSymbolSettings symbolSettings;
  final List<TradeCandle> actualPriceCandles;
  final double? previousSessionClose;
  final MarketQuote? sourceQuote;
  final bool replayActive;

  @override
  void paint(Canvas canvas, Size size) {
    final background = dark && panel.backgroundColor == 0xFFFFFFFF
        ? const Color(0xFF000D16) : Color(panel.backgroundColor);
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final axis = size.width - 61;
    if (axis < 30 || size.height < 60 || candles.isEmpty) return;
    final chartHeight = size.height - 24;
    final (start, ending) = viewport.visibleIndices(
      plotWidth: axis,
      candleCount: candles.length,
    );
    if (start >= ending) return;
    final scale = _priceScaleProvider(axis, size.height);
    final maximum = scale.maximum;
    final minimum = scale.minimum;
    double y(double price) => scale.y(price);
    // Reference: no visible candle-area grid. Labels derive from the actual
    // visible price interval, never from screenshot numbers or fake candles.
    final step = ChartAxisTicks.interval(minimum, maximum);
    final decimals = symbolSettings.digitsForTickStep(
      ChartAxisTicks.decimals(step));
    for (final tick in ChartAxisTicks.ticksWithStep(
        minimum, maximum, step: step)) {
      final py = y(tick);
      final important = (tick / (step * 5) -
          (tick / (step * 5)).round()).abs() < 0.000001;
      _text(canvas, _price(tick, decimals),
          Offset(axis + 6, py - 8), Color(panel.axisTextColor),
          panel.axisTextSize.toDouble(),
          bold: important);
      if (panel.horizontalGridVisible && py >= 0 && py < chartHeight) {
        _configuredLine(canvas, Offset(0, py), Offset(axis, py),
          Color(panel.horizontalGridColor), panel.horizontalGridStroke, .55);
      }
    }
    if (panel.verticalGridVisible) {
      for (var tick = 1; tick < 5; tick++) {
        final x = axis * tick / 5;
        _configuredLine(canvas, Offset(x, 0), Offset(x, chartHeight),
          Color(panel.verticalGridColor), panel.verticalGridStroke, .55);
      }
    }
    // Replay is already identified in the compact header. A large centered
    // watermark obscures real candles and does not aid playback.
    if (panel.scaleLineColor != 0x00000000) {
      canvas.drawLine(Offset(axis, 0), Offset(axis, chartHeight), Paint()
        ..color = Color(panel.scaleLineColor)
        ..strokeWidth = .75);
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, axis, chartHeight));
    final positiveWick = Paint()
      ..color = Color(symbolSettings.wickBull)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    final negativeWick = Paint()
      ..color = Color(symbolSettings.wickBear)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    final positiveBody = Paint()..color = Color(symbolSettings.bodyBull);
    final negativeBody = Paint()..color = Color(symbolSettings.bodyBear);
    final positiveBorder = Paint()
      ..color = Color(symbolSettings.borderBull)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    final negativeBorder = Paint()
      ..color = Color(symbolSettings.borderBear)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    // One stroke path per wick color instead of a drawLine per candle on
    // every momentum/pinch frame. All wicks stay behind their own bodies;
    // price, market-data order and bar-width geometry are unchanged.
    if (symbolSettings.wickVisible) {
      final wicks = ChartCandleWicks.visible(
        candles: candles,
        viewport: viewport,
        start: start,
        end: ending,
        plotWidth: axis,
        priceY: y,
        colorByPreviousClose: symbolSettings.colorByPreviousClose,
      );
      canvas.drawPath(wicks.rising, positiveWick);
      canvas.drawPath(wicks.falling, negativeWick);
    }
    // Keep the per-candle drawRect pipeline and its exact fill/border order.
    // Raster QA (#541) found pixel differences from grouping the same
    // rectangles into Paths at every tested bar width. Correct visual
    // output takes precedence over reducing draw calls for candle bodies.
    for (var i = start; i < ending; i++) {
      final candle = candles[i];
      final rising = symbolSettings.colorByPreviousClose && i > 0
          ? candle.close >= candles[i - 1].close : candle.positive;
      final centerX = viewport.chartX(
        index: i, candleCount: candles.length, plotWidth: axis);
      if (centerX < -viewport.barWidth || centerX > axis + viewport.barWidth) continue;
      final openY = y(candle.open);
      final closeY = y(candle.close);
      final bodyRect = Rect.fromLTRB(
        centerX - viewport.barWidth * .34, math.min(openY, closeY),
        centerX + viewport.barWidth * .34, math.max(openY + 1, closeY + 1),
      );
      if (symbolSettings.bodyVisible) {
        canvas.drawRect(bodyRect, rising ? positiveBody : negativeBody);
      }
      if (symbolSettings.borderVisible) {
        canvas.drawRect(bodyRect, rising ? positiveBorder : negativeBorder);
      }
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
    final paintLevels = _levelsProvider();
    final paintPatterns = _patternsProvider();
    final activeLine = _selectedLineProvider();
    final activePattern = _selectedPatternProvider();
    for (var index = 0; index < paintLevels.length; index++) {
      final levelY = y(paintLevels[index]);
      final marker = Paint()..color = TradeColors.blue.withValues(alpha: .8)
        ..strokeWidth = activeLine == index ? 2.4 : 1;
      canvas.drawLine(Offset(0, levelY), Offset(axis, levelY), marker);
    }
    for (var index = 0; index < paintPatterns.length; index++) {
      final drawing = paintPatterns[index];
      // Replay is strictly prefix-only: drawings ending in the future stay
      // invisible, even if their coordinates were created in analysis mode.
      if (!drawing.visibleAt(candles.length)) continue;
      final x1 = viewport.chartX(index: drawing.start.index,
          candleCount: candles.length, plotWidth: axis);
      final x2 = viewport.chartX(index: drawing.end.index,
          candleCount: candles.length, plotWidth: axis);
      final selected = activePattern == index;
      // Skip only finite annotations whose source-anchor geometry proves
      // they cannot touch this plot. The selected pattern keeps its handles;
      // rays, infinite lines and parallel channels keep their long reach.
      if (!selected && ChartLineGeometry.definitelyOffscreenHorizontally(
          tool: drawing.tool, startX: x1, endX: x2, plotWidth: axis)) {
        continue;
      }
      final y1 = y(drawing.start.price);
      final y2 = y(drawing.end.price);
      final color = Color(drawing.colorValue);
      final drawingPaint = Paint()
        ..color = color
        ..strokeWidth = drawing.strokeWidth + (selected ? 1 : 0)
        ..style = PaintingStyle.stroke;
      if (drawing.tool == ChartDrawingTool.fibonacci) {
        final fromX = math.min(x1, x2);
        final plot = Rect.fromLTWH(0, 0, axis, chartHeight);
        for (final ratio in ChartPattern.fibonacciRatios) {
          final price = drawing.fibonacciPrice(ratio);
          final stroke = ChartLineGeometry.fibonacciLevelStroke(
            fromX: fromX,
            levelY: y(price),
            plot: plot,
          );
          if (stroke == null) continue;
          canvas.drawLine(stroke.start, stroke.end, drawingPaint);
          if (drawing.showLabels) {
            final label =
                '${(ratio * 100).toStringAsFixed(1)}% ${price.toStringAsFixed(decimals)}';
            final paragraph = textCache.layout(label, color, 10);
            // Keep the label at its visible beginning and entirely before
            // the right price ruler, even with an ancient off-screen anchor.
            if (stroke.end.dx - stroke.start.dx >= paragraph.width + 10) {
              paragraph.paint(canvas,
                  Offset(stroke.start.dx + 5, stroke.start.dy - 13));
            }
          }
        }
      } else {
        final offsetAnchor = drawing.offsetAnchor;
        final offset = offsetAnchor == null ? null : Offset(
          viewport.chartX(index: offsetAnchor.index,
              candleCount: candles.length, plotWidth: axis),
          y(offsetAnchor.price),
        );
        final strokes = ChartLineGeometry.strokes(
          tool: drawing.tool,
          start: Offset(x1, y1),
          end: Offset(x2, y2),
          offset: offset,
          bounds: Rect.fromLTWH(0, 0, axis, chartHeight),
        );
        for (final stroke in strokes) {
          canvas.drawLine(stroke.start, stroke.end, drawingPaint);
        }
      }
      if (selected) {
        final handle = Paint()..color = color;
        canvas.drawCircle(Offset(x1, y1), 4.2, handle);
        if (!drawing.tool.oneAnchor) {
          canvas.drawCircle(Offset(x2, y2), 4.2, handle);
        }
        final offsetAnchor = drawing.offsetAnchor;
        if (offsetAnchor != null) {
          canvas.drawCircle(Offset(
            viewport.chartX(index: offsetAnchor.index,
                candleCount: candles.length, plotWidth: axis),
            y(offsetAnchor.price)), 4.2, handle);
        }
      }
    }
    _paintShortPositions(canvas, scale, axis, candles.length, decimals);
    canvas.restore();
    // All axis annotations are sourced from broker/market history already in
    // memory. Toggling settings never requests an additional OHLC candle.
    final occupiedAxis = <double>[];
    void annotate(double price, Color color, ChartPriceLabelMode mode) {
      if (mode == ChartPriceLabelMode.hidden || !price.isFinite) return;
      final py = y(price);
      if (py < 4 || py > chartHeight - 18) return;
      if (scaleSettings.avoidOverlappingLabels &&
          occupiedAxis.any((other) => (other - py).abs() < 23)) return;
      occupiedAxis.add(py);
      if (mode == ChartPriceLabelMode.valueAndLine) {
        canvas.drawLine(Offset(0, py), Offset(axis, py),
          Paint()..color = color.withValues(alpha: .75)..strokeWidth = .7);
      }
      final top = (py - 11).clamp(0, chartHeight - 22).toDouble();
      canvas.drawRect(Rect.fromLTWH(axis, top, 61, 22),
        Paint()..color = color);
      _text(canvas, _price(price, decimals), Offset(axis + 3, top + 4),
        Colors.white, math.max(9, panel.axisTextSize - 2).toDouble());
    }
    // A source-derived last-close marker, not a simulated tick or countdown.
    final lastClose = candles.last.close;
    final lastY = y(lastClose);
    if (scaleSettings.symbolLabel != ChartPriceLabelMode.hidden &&
        lastY >= 0 && lastY <= chartHeight) {
      occupiedAxis.add(lastY);
      final lastColor = candles.last.positive
          ? Color(scaleSettings.symbolLabelColor)
          : Color(scaleSettings.symbolNegativeColor);
      if (scaleSettings.symbolLabel == ChartPriceLabelMode.valueAndLine) {
        final marker = Paint()..color = lastColor..strokeWidth = .9;
        // Batch identical dash contours into one Canvas call per frame.
        // Each dash remains 2.2px long with a 6px period, clipped to
        // the source-candle plot rather than extending onto the price ruler.
        canvas.drawPath(ChartLineGeometry.lastCloseDashPath(
          y: lastY, plotWidth: axis), marker);
      }
      final tagY = (lastY - 14).clamp(0, chartHeight - 30).toDouble();
      canvas.drawRect(Rect.fromLTWH(axis, tagY, 61, 30),
          Paint()..color = lastColor);
      _text(canvas, _price(lastClose, decimals),
          Offset(axis + 3, tagY + 7), Colors.white,
          panel.axisTextSize.toDouble());
    }
    if (previousSessionClose != null) {
      annotate(previousSessionClose!, Color(scaleSettings.previousCloseColor),
        scaleSettings.previousClose);
    }
    if (scaleSettings.highLow != ChartPriceLabelMode.hidden) {
      final extremes = ChartAxisSourceLabels.visibleHighLow(
        actualPriceCandles, start, ending);
      if (extremes != null) {
        annotate(extremes.$1, Color(scaleSettings.highColor), scaleSettings.highLow);
        annotate(extremes.$2, Color(scaleSettings.lowColor), scaleSettings.highLow);
      }
    }
    if (indicator &&
        scaleSettings.indicatorLabels != ChartPriceLabelMode.hidden) {
      // The rightmost PAINTED SMA12 point belongs to visible bar ending-1.
      // The full broker archive can contain later candles while the user
      // scrolls into history. Never label their unseen SMA as the currently
      // plotted indicator, including in historical Replay or Range mode.
      final visibleSma = ChartVisibleSma.atVisibleEnd(candles, ending);
      if (visibleSma != null) {
        annotate(visibleSma, TradeColors.blue,
            scaleSettings.indicatorLabels);
      }
    }
    // Paint-time source quote freshness is necessary for retained painters:
    // the most recent BID/ASK can change without reconstructing this widget.
    // The live getter is disabled for Replay; no future price may leak in.
    final verifiedQuote = replayActive ? null : _sourceQuoteProvider();
    if (verifiedQuote != null &&
        scaleSettings.bidAsk != ChartPriceLabelMode.hidden) {
      annotate(verifiedQuote.ask, Color(scaleSettings.askColor),
        scaleSettings.bidAsk);
      annotate(verifiedQuote.bid, Color(scaleSettings.bidColor),
        scaleSettings.bidAsk);
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
      // Label widths are measured using the same font/RTL direction as the
      // painter. Never let overlapping text corrupt the mobile time axis.
      // This affects presentation only; the underlying UTC times are intact.
      final timeAxisLayout = ChartTimeAxisLabelLayout(plotWidth: axis);
      final fontSize = math.max(9, panel.axisTextSize - 2).toDouble();
      final labelColor = Color(panel.axisTextColor);
      final zoneLabel = ChartHistoricalTimeZone.labelAtVisibleBar(
          zone: symbolSettings.timeZone,
          timestampsUtcMs: timestamps,
          lastVisibleIndex: ending - 1);
      final zoneWidth = math.min(120.0, axis * .30);
      if (zoneWidth > 24) {
        final zonePainter = textCache.layoutBoundedAxis(
          zoneLabel, labelColor, 9, maxWidth: zoneWidth);
        final zoneLeft = axis - zonePainter.width - 3;
        // Place timezone at the right of the plot, away from the drawing
        // rail overlay on the left, then reserve its measured width.
        if (timeAxisLayout.reserve(
            left: zoneLeft, right: zoneLeft + zonePainter.width)) {
          zonePainter.paint(canvas, Offset(zoneLeft, chartHeight + 4));
        }
      }

      // Real UTC dates only. Range uses the originating BID tick timestamp,
      // never a fabricated equal-duration interval.
      DateTime? priorTick;
      for (var tick = 1; tick <= 4; tick++) {
        final x = axis * tick / 5;
        final index = viewport.indexAt(
            x: x, plotWidth: axis, candleCount: candles.length);
        if (index == null) continue;
        final local = symbolSettings.timeZone.displayDate(timestamps[index]);
        final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
        final isDayBoundary = priorTick == null ||
            priorTick.day != local.day || priorTick.month != local.month ||
            priorTick.year != local.year;
        priorTick = local;
        final isWeekdayLabel =
            scaleSettings.weekdayOnLabels && isDayBoundary;
        final label = isWeekdayLabel
            ? ChartScaleSettings.weekdayForDisplayedDate(local)
            : '${hour.toString().padLeft(2, '0')}:'
              '${local.minute.toString().padLeft(2, '0')} '
              '${local.hour < 12 ? 'AM' : 'PM'}';
        // Reuse text shaping on ordinary pan, pinch and momentum frames.
        // Width, RTL direction and the original 500 font weight are intact.
        final labelPainter = textCache.layout(
          label, labelColor, fontSize, rtl: isWeekdayLabel);
        if (timeAxisLayout.reserveCentered(
            centerX: x, width: labelPainter.width)) {
          labelPainter.paint(
              canvas, Offset(x - labelPainter.width / 2, chartHeight + 4));
        }
      }
    }
    if (crosshair != null) {
      // Resolve ONE candle index for both the vertical guide and its time
      // tag. At 3px/bar the unsnapped guide could sit between two candles
      // while the label claimed the time of a different source bar.
      final selected = ChartCrosshairSnap.resolve(
        viewport: viewport,
        touchX: crosshair!.dx,
        plotWidth: axis,
        candleCount: candles.length,
      );
      final location = Offset(
        selected.x,
        crosshair!.dy.clamp(0, chartHeight).toDouble(),
      );
      _configuredLine(canvas, Offset(location.dx, 0),
        Offset(location.dx, chartHeight), Color(panel.crosshairColor),
        panel.crosshairStroke, 1);
      _configuredLine(canvas, Offset(0, location.dy),
        Offset(axis, location.dy), Color(panel.crosshairColor),
        panel.crosshairStroke, 1);
      // Match the exact canvas price transform, even at sub-pip forex zoom.
      // A separate 0.00001 span floor used to put the cursor's numerical
      // tag at a different price from its horizontal line.
      final crossPrice = scale.crosshairPrice(location.dy);
      if (crossPrice != null) {
        final markerY = (location.dy - 9).clamp(
            0, chartHeight - 18).toDouble();
        canvas.drawRect(Rect.fromLTWH(axis, markerY, 61, 18),
            Paint()..color = TradeColors.blue);
        _text(canvas, _price(crossPrice, decimals),
            Offset(axis + 3, markerY + 2), Colors.white, 10);
      }
      if (timestamps.length >= candles.length &&
          selected.index != null) {
          // This is the same REAL candle that owns the guide at selected.x.
          // The Replay list is already limited to its confirmed prefix.
          final label = ChartCrosshairTimeLabel.fromSource(
            utcTimestampMs: timestamps[selected.index!],
            zone: symbolSettings.timeZone,
            rangeMode: rangeMode,
          );
          final painter = textCache.layout(label, Colors.white, 9);
          final badgeWidth = ChartCrosshairTimeLabel.badgeWidth(
            measuredTextWidth: painter.width, plotWidth: axis);
          final startX = (location.dx - badgeWidth / 2).clamp(
              0.0, math.max(0, axis - badgeWidth)).toDouble();
          canvas.drawRect(Rect.fromLTWH(
              startX, chartHeight, badgeWidth, 20),
              Paint()..color = TradeColors.blue);
          // The measured width carries milliseconds for Range ticks, but
          // the badge never paints into the right price scale.
          canvas.save();
          canvas.clipRect(Rect.fromLTWH(
              startX, chartHeight, badgeWidth, 20));
          painter.paint(canvas, Offset(startX + 5, chartHeight + 4));
          canvas.restore();
      }
    }
    // A separate LTR price axis keeps digits and decimal points predictable in RTL.
    if (timestamps.length < candles.length) {
      _text(canvas, 'شموع مدى',
          Offset(axis / 2 - 18, chartHeight + 3),
          Color(panel.axisTextColor),
          math.max(9, panel.axisTextSize - 2).toDouble());
    }
  }

  void _text(Canvas canvas, String value, Offset offset, Color color,
      double size, {bool bold = false, bool rtl = false}) {
    textCache.paint(
      canvas, value, offset, color, size, bold: bold, rtl: rtl);
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

  void _shortAxisTag(Canvas canvas, double axis, double height,
      double y, String value, Color color) {
    if (y < 0 || y > height) return;
    final top = (y - 9).clamp(0, height - 18).toDouble();
    canvas.drawRect(Rect.fromLTWH(axis, top, 61, 18), Paint()..color = color);
    _text(canvas, value, Offset(axis + 2, top + 2), Colors.white, 10);
  }

  void _shortPill(Canvas canvas, String value, Offset location,
      Color fill, double axis, double chartHeight, {bool twoLines = false}) {
    // These three selected-trade labels used to construct fresh paragraphs
    // on every pinch, pan and animated repaint. Reuse their exact measured
    // RTL layout via the chart-owned, capacity-bounded text cache.
    final painter = textCache.layoutPill(value,
        maxWidth: math.max(40, axis - 16), twoLines: twoLines);
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

  static void _configuredLine(Canvas canvas, Offset from, Offset to,
    Color color, ChartGridStroke stroke, double width) {
    final paint = Paint()..color = color..strokeWidth = width;
    if (stroke == ChartGridStroke.solid) {
      canvas.drawLine(from, to, paint);
      return;
    }
    // Keep the original dash positions and lengths, but issue one canvas
    // draw call instead of a drawLine for every 8px during pan/pinch.
    canvas.drawPath(
      ChartLineGeometry.configuredDashPath(from: from, to: to),
      paint..style = PaintingStyle.stroke,
    );
  }

  static String _price(double value, int digits) =>
      ChartPriceTextFormatter.price(value, digits);

  @override
  bool shouldRepaint(covariant _CandleChartPainter old) =>
      old.candles != candles || old.timestamps != timestamps ||
      old.dark != dark || old.viewportSnapshot != viewportSnapshot ||
      old.panel != panel ||
      old.scaleSettings != scaleSettings ||
      old.symbolSettings != symbolSettings ||
      old.actualPriceCandles != actualPriceCandles ||
      old.previousSessionClose != previousSessionClose ||
      old.sourceQuote != sourceQuote ||
      old.replayActive != replayActive || old.rangeMode != rangeMode ||
      old.crosshairSnapshot != crosshairSnapshot || old.indicator != indicator ||
      !listEquals(old.levels, levels) ||
      !listEquals(old.patterns, patterns) ||
      !listEquals(old.shortPositions, shortPositions) ||
      old.selectedLine != selectedLine || old.selectedPattern != selectedPattern ||
      old.selectedShort != selectedShort || old.showShortLabels != showShortLabels;
}
