import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../chart/chart_viewport.dart';
import '../data/range_bar_builder.dart';
import '../data/tradelab_data.dart';
import '../data/market_api.dart';
import '../data/market_controller.dart';
import '../theme/tradelab_theme.dart';
import '../widgets/trade_components.dart';

enum ChartMode { candles, heikinAshi, range }

class ChartScreen extends StatefulWidget {
  const ChartScreen({required this.controller, super.key});
  final MarketController controller;

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  final _fixture = previewCandles();
  final _rangeCache = <int, List<TradeCandle>>{};
  List<MarketBar> _actualBars = [];
  List<TradeCandle> _actualCandles = [];
  List<TradeCandle> _actualRange = [];
  int _loadRevision = 0;
  bool _loading = false;
  bool _olderLoading = false;
  bool _historyExhausted = false;
  String? _loadError;
  bool _linkedBefore = false;
  String? _accountBefore;
  String _symbol = 'XAUUSD';
  String _timeframe = '15m';
  ChartMode _mode = ChartMode.candles;
  int _rangeTicks = 1000;
  bool _replay = false;
  bool _drawing = false;
  bool _showIndicators = false;
  int _visibleThrough = 60;
  ChartViewport _viewport = const ChartViewport();
  ChartViewport _gestureStart = const ChartViewport();
  double _gestureFocalX = 0;
  Offset? _crosshair;
  Timer? _replayTimer;
  bool _playing = false;
  final List<double> _levels = [];
  final List<List<double>> _lineUndo = [];
  int? _selectedLine;
  bool _draggingLine = false;

  TradeSymbol get _selectedSymbol => tradeSymbols.firstWhere((s) => s.code == _symbol);
  bool get _liveRequested => _selectedSymbol.source == TradeSource.binance ||
      widget.controller.ctraderConnected;
  int get _totalBars => _mode == ChartMode.range && _liveRequested
      ? _actualRange.length : _liveRequested ? _actualBars.length : _fixture.length;

  @override
  void initState() {
    super.initState();
    _linkedBefore = widget.controller.ctraderConnected;
    _accountBefore = widget.controller.accountId;
    widget.controller.addListener(_onMarketUpdate);
    if (_linkedBefore) Future.microtask(_loadRealHistory);
  }

  void _onMarketUpdate() {
    final linked = widget.controller.ctraderConnected;
    final changedAccount = _accountBefore != widget.controller.accountId;
    if (_linkedBefore != linked || changedAccount) {
      _linkedBefore = linked;
      _accountBefore = widget.controller.accountId;
      if (linked && _selectedSymbol.source == TradeSource.ctrader) {
        _loadRealHistory();
      }
      if (!linked && _selectedSymbol.source == TradeSource.ctrader) {
        _loadRevision++;
        _actualBars = [];
        _actualRange = [];
        if (mounted) setState(() {});
      }
    }
  }

  Future<void> _loadRealHistory() async {
    final revision = ++_loadRevision;
    if (!mounted) return;
    setState(() {
      _stopPlayback();
      _replay = false;
      _loading = true;
      _loadError = null;
      _historyExhausted = false;
      _actualBars = [];
      _actualCandles = [];
      _actualRange = [];
    });
    try {
      if (_mode == ChartMode.range) {
        final ticks = await widget.controller.rangeTicks(_selectedSymbol);
        final point = await widget.controller.pointSize(_selectedSymbol);
        if (ticks.isEmpty) throw const MarketDataException('لم يُرجع cTrader تيكات ضمن الفترة المطلوبة.');
        final builder = RangeBarBuilder(_rangeTicks * point);
        for (final tick in ticks) {builder.appendBidTick(tick.bid);}
        if (revision != _loadRevision || !mounted) return;
        _actualRange = builder.snapshot();
      } else {
        final bars = await widget.controller.history(_selectedSymbol, _timeframe);
        if (revision != _loadRevision || !mounted) return;
        _actualBars = bars;
        _actualCandles = bars.map((bar) => bar.candle).toList(growable: false);
      }
    } on MarketDataException catch (e) {
      if (revision == _loadRevision) _loadError = e.message;
    } catch (_) {
      if (revision == _loadRevision) _loadError = 'تعذر تحميل بيانات السوق. أعد المحاولة.';
    } finally {
      if (revision == _loadRevision && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadOlderHistory() async {
    if (_olderLoading || _loading || _historyExhausted || !_liveRequested ||
        _mode == ChartMode.range || _actualBars.isEmpty) return;
    final revision = _loadRevision;
    _olderLoading = true;
    try {
      final before = DateTime.fromMillisecondsSinceEpoch(_actualBars.first.timestamp, isUtc: true);
      final older = await widget.controller.history(_selectedSymbol, _timeframe, before: before);
      if (revision != _loadRevision || !mounted) return;
      final earliest = _actualBars.first.timestamp;
      final unique = older.where((bar) => bar.timestamp < earliest).toList();
      if (unique.isEmpty) _historyExhausted = true;
      if (unique.isNotEmpty) setState(() {
        _actualBars = [...unique, ..._actualBars];
        _actualCandles = _actualBars.map((bar) => bar.candle).toList(growable: false);
        if (_replay) _visibleThrough += unique.length;
      });
    } catch (_) {
      // Old loaded candles remain valid; retry on another deliberate drag.
    } finally {_olderLoading = false;}
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onMarketUpdate);
    _loadRevision++;
    _replayTimer?.cancel();
    super.dispose();
  }

  void _stopPlayback() {
    _replayTimer?.cancel();
    _replayTimer = null;
    _playing = false;
  }

  void _toggleReplay() {
    if (_liveRequested && _totalBars < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('حمّل شموع السوق أولًا لبدء Replay.')));
      return;
    }
    setState(() {
        _stopPlayback();
        _replay = !_replay;
        _visibleThrough = math.max(1, _totalBars ~/ 2);
        _viewport = const ChartViewport();
        _crosshair = null;
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
          content: Text('هذه معاينة للواجهة. ربط cTrader وبيانات Room بالنسخة الجديدة لم يكتمل بعد.'),
        ),
      );

  List<TradeCandle> get _displayCandles {
    if (_mode == ChartMode.range) {
      if (_liveRequested) {
        final range = _replay ? _actualRange.take(_visibleThrough).toList() : _actualRange;
        return range;
      }
      if (!_replay) {
        return _rangeCache.putIfAbsent(_rangeTicks,
            () => previewRangeCandles(_rangeTicks));
      }
      final throughTick = (_visibleThrough / _fixture.length * 1800).round();
      return previewRangeCandles(_rangeTicks, throughTick: throughTick);
    }
    final source = _liveRequested ? _actualCandles : _fixture;
    final count = _replay ? _visibleThrough.clamp(0, source.length) : source.length;
    final raw = source.take(count).toList(growable: false);
    if (raw.isEmpty) return raw;
    if (_mode != ChartMode.heikinAshi) return raw;
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
                      setState(() { _timeframe = frame; _viewport = const ChartViewport(); });
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
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const TradeSectionTitle('نوع الشموع'),
            for (final item in const <(ChartMode, String, IconData)>[
              (ChartMode.candles, 'الشموع اليابانية', Icons.candlestick_chart),
              (ChartMode.heikinAshi, 'هيكن آشي', Icons.stacked_line_chart),
              (ChartMode.range, 'شموع المدى', Icons.tune),
            ])
              ListTile(
                leading: Icon(item.$3),
                title: Text(item.$2),
                trailing: _mode == item.$1
                    ? const Icon(Icons.check_circle, color: TradeColors.blue)
                    : null,
                onTap: () {
                  setState(() { _mode = item.$1; _viewport = const ChartViewport(); });
                  Navigator.pop(sheetContext);
                  if (item.$1 == ChartMode.range) _showRangeSettings();
                  if (_liveRequested) _loadRealHistory();
                },
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _showRangeSettings() async {
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
                    setState(() => _rangeTicks = size);
                    Navigator.pop(sheetContext);
                    if (_liveRequested) _loadRealHistory();
                  },
                ),
            ]),
            const SizedBox(height: 16),
          ]),
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

  void _saveDrawingUndo() {
    _lineUndo.add(List<double>.of(_levels));
    if (_lineUndo.length > 30) _lineUndo.removeAt(0);
  }

  void _undoDrawing() {
    if (_lineUndo.isEmpty) return;
    setState(() {
      _levels..clear()..addAll(_lineUndo.removeLast());
      _selectedLine = null;
    });
  }

  ChartPriceScale _priceScale(List<TradeCandle> candles, double width, double height) =>
      ChartPriceScale.visible(candles, _viewport, width, math.max(1, height - 24));

  int? _hitLine(double y, ChartPriceScale scale) {
    for (var index = _levels.length - 1; index >= 0; index--) {
      if ((scale.y(_levels[index]) - y).abs() <= 18) return index;
    }
    return null;
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
                    Text(_symbol, textDirection: TextDirection.ltr,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down, size: 19),
                  ]),
                  Text(_liveRequested ? 'تحليل السوق · ${_selectedSymbol.source == TradeSource.binance ? 'Binance' : 'cTrader'}'
                      : 'تحليل السوق · غير متصل',
                      style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
                ]),
              ),
            ),
          ),
          TradeStatusChip(label: _liveRequested
              ? (_loading ? 'جار التحميل' : _loadError != null ? 'خطأ في المصدر' : 'بيانات فعلية')
              : 'معاينة', connected: _liveRequested && !_loading && _loadError == null && candles.isNotEmpty),
          _iconAction(icon: Icons.fullscreen, label: 'ملء الشاشة', onPressed: _notifyUnconnected),
          _iconAction(icon: Icons.refresh, label: 'تحديث أسعار السوق',
            onPressed: _liveRequested ? _loadRealHistory : _notifyUnconnected),
        ]),
      ),
      const Divider(height: 1),
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
            onPressed: () => setState(() => _drawing = !_drawing)),
          _iconAction(icon: Icons.zoom_in_outlined, label: 'تكبير الشارت',
            onPressed: () => _zoomBy(1.25)),
          _iconAction(icon: Icons.zoom_out_outlined, label: 'تصغير الشارت',
            onPressed: () => _zoomBy(.8)),
          _iconAction(icon: Icons.last_page, label: 'العودة إلى أحدث شمعة',
            onPressed: () => setState(() => _viewport = _viewport.jumpToLatest())),
          const SizedBox(width: 8),
          if (_mode == ChartMode.range)
            TextButton(onPressed: _showRangeSettings, child: Text('مدى $_rangeTicks')),
         ])),
      ),
      const Divider(height: 1),
      if (_mode == ChartMode.range)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          color: TradeColors.blue.withValues(alpha: .07),
          child: Text(_liveRequested
              ? 'مدى $_rangeTicks نقطة · ${_actualRange.isEmpty ? 'انتظار تيكات cTrader' : 'تيكات BID موثقة من cTrader'}'
              : 'مدى $_rangeTicks · عرض محسوب من تيكات تجريبية، وليس cTrader',
              style: const TextStyle(fontSize: 11, color: TradeColors.blue)),
        ),
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      if (_loadError != null && _liveRequested)
        MaterialBanner(content: Text(_loadError!), actions: [
          TextButton(onPressed: _loadRealHistory, child: const Text('إعادة المحاولة')),
        ]),
      Expanded(
        child: LayoutBuilder(builder: (context, constraints) {
          final plotWidth = math.max(1.0, constraints.maxWidth - 61);
          return GestureDetector(
            key: const Key('chart-gesture-area'),
            behavior: HitTestBehavior.opaque,
            onScaleStart: (details) {
              _gestureStart = _viewport;
              _gestureFocalX = details.localFocalPoint.dx;
              if (_drawing && details.pointerCount == 1) {
                final scale = _priceScale(candles, plotWidth, constraints.maxHeight);
                _selectedLine = _hitLine(details.localFocalPoint.dy, scale);
                _draggingLine = _selectedLine != null;
                if (_draggingLine) _saveDrawingUndo();
              } else {_draggingLine = false;}
            },
            onScaleUpdate: (details) {
              setState(() {
              if (_draggingLine && _selectedLine != null && details.pointerCount == 1) {
                final scale = _priceScale(candles, plotWidth, constraints.maxHeight);
                _levels[_selectedLine!] = scale.price(
                    details.localFocalPoint.dy.clamp(0, scale.height).toDouble());
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
              if (!_draggingLine && _liveRequested && _actualBars.isNotEmpty && !_replay &&
                  _viewport.scrollBars > _actualBars.length - plotWidth / _viewport.barWidth - 25) {
                unawaited(_loadOlderHistory());
              }
            },
            onScaleEnd: (_) => _draggingLine = false,
            onDoubleTap: () => setState(() { _viewport = const ChartViewport(); _crosshair = null; }),
            onLongPressStart: (details) => setState(() => _crosshair = details.localPosition),
            onLongPressMoveUpdate: (details) => setState(() => _crosshair = details.localPosition),
            onLongPressEnd: (_) => setState(() => _crosshair = null),
            onTapUp: (details) {
              if (!_drawing || details.localPosition.dx > plotWidth) return;
              final scale = _priceScale(candles, plotWidth, constraints.maxHeight);
              final hit = _hitLine(details.localPosition.dy, scale);
              setState(() {
                if (hit != null) {_selectedLine = hit; return;}
                _saveDrawingUndo();
                _levels.add(scale.price(
                    details.localPosition.dy.clamp(0, scale.height).toDouble()));
                _selectedLine = _levels.length - 1;
              });
            },
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size.infinite,
                painter: _CandleChartPainter(
                  candles: candles,
                  dark: Theme.of(context).brightness == Brightness.dark,
                  viewport: _viewport,
                  crosshair: _crosshair,
                  levels: List<double>.unmodifiable(_levels),
                  selectedLine: _drawing ? _selectedLine : null,
                  indicator: _showIndicators,
                  isPreview: !_liveRequested,
                ),
              ),
            ),
          );
        }),
      ),
      Container(
        padding: const EdgeInsetsDirectional.only(start: 12, end: 8, top: 6, bottom: 6),
        color: surface,
        child: Row(children: [
          const Icon(Icons.info_outline, size: 15, color: TradeColors.blue),
          const SizedBox(width: 6),
          Expanded(child: Text(_liveRequested
              ? (_loading ? 'جار تحميل شموع موثقة من المصدر' :
                  _loadError != null ? 'البيانات غير متاحة حاليًا' :
                  'شموع المصدر الفعلي · Replay للشموع المحمّلة فقط')
              : 'شموع توضيحية للتصميم وليست أسعارًا حقيقية',
              maxLines: 2, style: TextStyle(fontSize: 11))),
          if (_drawing && _selectedLine != null && _selectedLine! < _levels.length)
            IconButton(tooltip: 'حذف الخط المحدد', onPressed: () => setState(() {
              _saveDrawingUndo();
              _levels.removeAt(_selectedLine!);
              _selectedLine = null;
            }), icon: const Icon(Icons.delete_outline)),
          if (_lineUndo.isNotEmpty)
            TextButton.icon(
              onPressed: _undoDrawing,
              icon: const Icon(Icons.undo, size: 18),
              label: const Text('تراجع'),
            ),
        ]),
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
            Text('$_visibleThrough / $_totalBars ${_liveRequested ? 'شمعة' : 'شمعة توضيحية'}',
                style: Theme.of(context).textTheme.labelSmall),
          ]),
          Row(children: [
            IconButton(tooltip: 'رجوع شمعة',
              onPressed: _visibleThrough <= 1 ? null : () => setState(() => _visibleThrough--),
              icon: const Icon(Icons.skip_previous)),
            IconButton(key: const Key('replay-play-pause'),
              tooltip: _playing ? 'إيقاف' : 'تشغيل',
              onPressed: _togglePlay,
              icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle_fill,
                  color: TradeColors.blue)),
            IconButton(tooltip: 'تقدم شمعة',
              onPressed: _visibleThrough >= _totalBars ? null : () => setState(() => _visibleThrough++),
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

class _CandleChartPainter extends CustomPainter {
  _CandleChartPainter({
    required this.candles,
    required this.dark,
    required this.viewport,
    required this.crosshair,
    required this.levels,
    required this.selectedLine,
    required this.indicator,
    required this.isPreview,
  });

  final List<TradeCandle> candles;
  final bool dark;
  final ChartViewport viewport;
  final Offset? crosshair;
  final List<double> levels;
  final int? selectedLine;
  final bool indicator;
  final bool isPreview;

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
    for (var i = start; i < ending; i++) {
      final candle = candles[i];
      final centerX = viewport.chartX(
        index: i, candleCount: candles.length, plotWidth: axis);
      if (centerX < -viewport.barWidth || centerX > axis + viewport.barWidth) continue;
      final color = candle.positive ? TradeColors.positive : TradeColors.negative;
      final center = Paint()..color = color..strokeWidth = 1.3;
      canvas.drawLine(Offset(centerX, y(candle.high)), Offset(centerX, y(candle.low)), center);
      final openY = y(candle.open);
      final closeY = y(candle.close);
      canvas.drawRect(Rect.fromLTRB(
        centerX - viewport.barWidth * .31, math.min(openY, closeY),
        centerX + viewport.barWidth * .31, math.max(openY + 1, closeY + 1),
      ), Paint()..color = color);
    }
    if (indicator) {
      final linePath = Path();
      for (var i = start; i < ending; i++) {
        final from = math.max(0, i - 11);
        final section = candles.sublist(from, i + 1);
        final average = section.fold<double>(0, (sum, bar) => sum + bar.close) / section.length;
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
    canvas.restore();
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
    }
    // A separate LTR price axis keeps digits and decimal points predictable in RTL.
    _text(canvas, isPreview ? 'معاينة' : 'سوق فعلي',
        Offset(axis / 2 - 18, chartHeight + 3), text, 10);
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

  @override
  bool shouldRepaint(covariant _CandleChartPainter old) =>
      old.candles != candles || old.dark != dark || old.viewport != viewport ||
      old.crosshair != crosshair || old.indicator != indicator ||
      old.levels != levels || old.selectedLine != selectedLine ||
      old.isPreview != isPreview;
}
