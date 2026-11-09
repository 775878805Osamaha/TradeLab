import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../chart/chart_annotations.dart';
import '../chart/chart_viewport.dart';
import '../chart/candle_prefix.dart';
import '../data/range_bar_builder.dart';
import '../data/tradelab_data.dart';
import '../data/market_api.dart';
import '../data/market_controller.dart';
import '../paper/paper_journal_controller.dart';
import '../paper/paper_ledger.dart';
import '../paper/paper_order_sheet.dart';
import '../paper/paper_trade_service.dart';
import '../theme/tradelab_theme.dart';
import '../widgets/trade_components.dart';

enum ChartMode { candles, heikinAshi, range }

class ChartScreen extends StatefulWidget {
  const ChartScreen({required this.controller, this.journal, super.key});
  final MarketController controller;
  final PaperJournalController? journal;

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  final _fixture = previewCandles();
  final _rangeCache = <int, List<TradeCandle>>{};
  List<MarketBar> _actualBars = [];
  List<TradeCandle> _actualCandles = [];
  List<int> _actualTimestamps = [];
  List<TradeCandle> _actualRange = [];
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
  bool _showIndicators = false;
  int _visibleThrough = 60;
  ChartViewport _viewport = const ChartViewport();
  ChartViewport _gestureStart = const ChartViewport();
  double _gestureFocalX = 0;
  Offset? _crosshair;
  Timer? _replayTimer;
  bool _playing = false;
  final List<double> _levels = [];
  final List<ChartPattern> _patterns = [];
  final List<(List<double>, List<ChartPattern>)> _lineUndo = [];
  List<double> _analysisLevels = [];
  List<ChartPattern> _analysisPatterns = [];
  ChartAnchor? _pendingAnchor;
  int? _selectedLine;
  int? _selectedPattern;
  bool _draggingLine = false;
  bool _draggingPattern = false;
  ChartPattern? _patternAtDragStart;
  double _gestureFocalY = 0;

  TradeSymbol get _selectedSymbol => tradeSymbols.firstWhere((s) => s.code == _symbol);
  bool get _liveRequested => _selectedSymbol.source == TradeSource.binance ||
      widget.controller.ctraderConnected;
  bool get _rangeSourceSupported => _selectedSymbol.source == TradeSource.ctrader;
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
      // Never carry another broker account's drawings into this account.
      _resetDrawingObjects();
      if (linked && _selectedSymbol.source == TradeSource.ctrader) {
        _loadRealHistory();
      }
      if (!linked && _selectedSymbol.source == TradeSource.ctrader) {
        _loadRevision++;
        _actualBars = [];
        _actualTimestamps = [];
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
      if (_replay) {
        _levels..clear()..addAll(_analysisLevels);
        _patterns..clear()..addAll(_analysisPatterns);
      }
      _replay = false;
      _loading = true;
      _loadError = null;
      _historyExhausted = false;
      _olderCursorMs = null;
      _olderLoadError = null;
      _actualBars = [];
      _actualCandles = [];
      _actualTimestamps = [];
      _actualRange = [];
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
        _actualTimestamps = bars.map((bar) => bar.timestamp).toList(growable: false);
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
      final before = DateTime.fromMillisecondsSinceEpoch(cursor, isUtc: true);
      final older = await widget.controller.history(_selectedSymbol, _timeframe, before: before);
      if (revision != _loadRevision || !mounted) return;
      final earliest = _actualBars.first.timestamp;
      final unique = older.where((bar) => bar.timestamp < earliest).toList();
      if (unique.isEmpty) {
        if (_selectedSymbol.source == TradeSource.binance) {
          _historyExhausted = true;
        } else {
          // A broker may have a quiet 89-day window. An empty page is not
          // proof that all earlier history is exhausted. Continue on demand.
          _olderCursorMs = cursor - const Duration(days: 89).inMilliseconds;
          _olderLoadError = 'لا توجد شموع في هذه الفترة. اضغط «أقدم» للبحث قبلها.';
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
        if (_replay) {
          _analysisPatterns = _analysisPatterns
              .map((drawing) => drawing.shifted(unique.length))
              .toList(growable: false);
        }
        if (_pendingAnchor != null) {
          _pendingAnchor = _pendingAnchor!.shifted(unique.length);
        }
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
        if (!_replay) {
          // Drawings created after the Replay cutoff could expose future
          // information. Keep analysis objects separately until Replay ends.
          _analysisLevels = List<double>.of(_levels);
          _analysisPatterns = List<ChartPattern>.of(_patterns);
          _levels.clear();
          _patterns.clear();
        } else {
          _levels..clear()..addAll(_analysisLevels);
          _patterns..clear()..addAll(_analysisPatterns);
        }
        _replay = !_replay;
        _visibleThrough = math.max(1, _totalBars ~/ 2);
        _viewport = const ChartViewport();
        _crosshair = null;
        _selectedLine = null;
        _selectedPattern = null;
        _pendingAnchor = null;
        _lineUndo.clear();
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
    if (_mode == ChartMode.range) {
      if (_liveRequested) {
        final range = _replay
            ? CandlePrefix(_actualRange, _visibleThrough) : _actualRange;
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
                  setState(() {
                    _mode = item.$1;
                    _viewport = const ChartViewport();
                    _resetDrawingObjects();
                  });
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

  Future<void> _showDrawingTools() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const TradeSectionTitle('أدوات الرسم'),
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
                    _drawingTool = option.$1;
                    _pendingAnchor = null;
                    _selectedLine = null;
                    _selectedPattern = null;
                  });
                  Navigator.pop(sheetContext);
                },
              ),
            ListTile(
              title: const Text('إنهاء الرسم والعودة إلى تحريك الشارت'),
              leading: const Icon(Icons.pan_tool_outlined),
              onTap: () {
                setState(() {
                  _drawing = false;
                  _pendingAnchor = null;
                });
                Navigator.pop(sheetContext);
              },
            ),
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
    _lineUndo.add((List<double>.of(_levels), List<ChartPattern>.of(_patterns)));
    if (_lineUndo.length > 30) _lineUndo.removeAt(0);
  }

  void _undoDrawing() {
    if (_lineUndo.isEmpty) return;
    setState(() {
      final previous = _lineUndo.removeLast();
      _levels..clear()..addAll(previous.$1);
      _patterns..clear()..addAll(previous.$2);
      _selectedLine = null;
      _selectedPattern = null;
      _pendingAnchor = null;
    });
  }

  void _resetDrawingObjects() {
    _levels.clear();
    _patterns.clear();
    _analysisLevels = [];
    _analysisPatterns = [];
    _lineUndo.clear();
    _pendingAnchor = null;
    _selectedLine = null;
    _selectedPattern = null;
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

  ChartAnchor? _anchorAt(Offset point, ChartPriceScale scale,
      double plotWidth, int count) {
    final index = _viewport.indexAt(
        x: point.dx, plotWidth: plotWidth, candleCount: count);
    if (index == null) return null;
    return ChartAnchor(index,
        scale.price(point.dy.clamp(0, scale.height).toDouble()));
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
                  Text(_liveRequested ? 'تحليل السوق · ${_selectedSymbol.source == TradeSource.binance ? 'Binance' : 'cTrader'}'
                      : 'تحليل السوق · غير متصل',
                      style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
                ]),
              ),
            ),
          ),
          Flexible(child: TradeStatusChip(label: _liveRequested
              ? (_loading ? 'جار التحميل' : _loadError != null ? 'خطأ في المصدر' : 'بيانات فعلية')
              : 'معاينة', connected: _liveRequested && !_loading && _loadError == null && candles.isNotEmpty)),
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
            onPressed: _showDrawingTools),
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
              ? 'مدى $_rangeTicks نقطة · ${!_rangeSourceSupported ? 'غير مدعوم لهذا المصدر' : _actualRange.isEmpty ? 'انتظار تيكات cTrader' : 'شموع محسوبة من تيكات BID لـ cTrader'}'
              : 'مدى $_rangeTicks · عرض محسوب من تيكات تجريبية، وليس cTrader',
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
              unawaited(_loadOlderHistory(manual: true));
            }, child: const Text('إعادة المحاولة')),
          ]),
        ),
      Expanded(
        child: LayoutBuilder(builder: (context, constraints) {
          final plotWidth = math.max(1.0, constraints.maxWidth - 61);
          return Stack(children: [
          Positioned.fill(child: GestureDetector(
            key: const Key('chart-gesture-area'),
            behavior: HitTestBehavior.opaque,
            onScaleStart: (details) {
              _gestureStart = _viewport;
              _gestureFocalX = details.localFocalPoint.dx;
              _gestureFocalY = details.localFocalPoint.dy;
              if (_drawing && details.pointerCount == 1) {
                final scale = _priceScale(candles, plotWidth, constraints.maxHeight);
                _selectedLine = _hitLine(details.localFocalPoint.dy, scale);
                _draggingLine = _selectedLine != null;
                _selectedPattern = _draggingLine ? null :
                    _hitPattern(details.localFocalPoint, scale,
                        plotWidth, candles.length);
                _draggingPattern = _selectedPattern != null;
                _patternAtDragStart = _draggingPattern
                    ? _patterns[_selectedPattern!] : null;
                if (_draggingLine || _draggingPattern) _saveDrawingUndo();
              } else {
                _draggingLine = false;
                _draggingPattern = false;
              }
            },
            onScaleUpdate: (details) {
              setState(() {
              if (_draggingLine && _selectedLine != null && details.pointerCount == 1) {
                final scale = _priceScale(candles, plotWidth, constraints.maxHeight);
                _levels[_selectedLine!] = scale.price(
                    details.localFocalPoint.dy.clamp(0, scale.height).toDouble());
              } else if (_draggingPattern && _selectedPattern != null &&
                  _patternAtDragStart != null && details.pointerCount == 1) {
                final scale = _priceScale(candles, plotWidth, constraints.maxHeight);
                final original = _patternAtDragStart!;
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
              if (!_draggingLine && _liveRequested && _actualBars.isNotEmpty &&
                  _mode != ChartMode.range &&
                  _viewport.scrollBars > candles.length - plotWidth / _viewport.barWidth - 25) {
                unawaited(_loadOlderHistory());
              }
            },
            onScaleEnd: (_) {
              _draggingLine = false;
              _draggingPattern = false;
              _patternAtDragStart = null;
            },
            onDoubleTap: () => setState(() { _viewport = const ChartViewport(); _crosshair = null; }),
            onLongPressStart: (details) => setState(() => _crosshair = details.localPosition),
            onLongPressMoveUpdate: (details) => setState(() => _crosshair = details.localPosition),
            onLongPressEnd: (_) => setState(() => _crosshair = null),
            onTapUp: (details) {
              if (!_drawing || details.localPosition.dx > plotWidth) return;
              final scale = _priceScale(candles, plotWidth, constraints.maxHeight);
              final hit = _hitLine(details.localPosition.dy, scale);
              setState(() {
                if (hit != null) {
                  _selectedLine = hit;
                  _selectedPattern = null;
                  _pendingAnchor = null;
                  return;
                }
                final hitPattern = _hitPattern(details.localPosition,
                    scale, plotWidth, candles.length);
                if (hitPattern != null) {
                  _selectedPattern = hitPattern;
                  _selectedLine = null;
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
                    _pendingAnchor = null;
                  }
                  return;
                }
                _saveDrawingUndo();
                _levels.add(scale.price(
                    details.localPosition.dy.clamp(0, scale.height).toDouble()));
                _selectedLine = _levels.length - 1;
                _selectedPattern = null;
              });
            },
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size.infinite,
                painter: _CandleChartPainter(
                  candles: candles,
                  timestamps: _mode == ChartMode.range ? const [] : _actualTimestamps,
                  dark: Theme.of(context).brightness == Brightness.dark,
                  viewport: _viewport,
                  crosshair: _crosshair,
                  levels: List<double>.unmodifiable(_levels),
                  patterns: List<ChartPattern>.unmodifiable(_patterns),
                  selectedLine: _drawing ? _selectedLine : null,
                  selectedPattern: _drawing ? _selectedPattern : null,
                  indicator: _showIndicators,
                  isPreview: !_liveRequested,
                ),
              ),
            ),
          )),
          if (_liveRequested && candles.isEmpty)
            Positioned.fill(child: IgnorePointer(child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_loading)
                    const CircularProgressIndicator(strokeWidth: 2),
                  if (_loading) const SizedBox(height: 14),
                  Text(_loading ? 'جارِ تحميل شموع السوق الفعلية…'
                    : _loadError ?? 'لا توجد شموع متاحة من المصدر.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
                ]),
              ),
            ))),
          ]);
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
                  'شموع المصدر الفعلي · اسحب للشموع الأقدم أو حمّلها في Replay')
              : 'شموع توضيحية للتصميم وليست أسعارًا حقيقية',
              maxLines: 2, style: TextStyle(fontSize: 11))),
          if (_drawing && (_selectedLine != null || _selectedPattern != null))
            IconButton(tooltip: 'خصائص الرسم المحدد',
              onPressed: _editSelectedDrawing,
              icon: const Icon(Icons.tune)),
          if (_drawing && (_selectedLine != null || _selectedPattern != null))
            IconButton(tooltip: 'حذف الرسم المحدد', onPressed: () => setState(() {
              _saveDrawingUndo();
              if (_selectedLine != null && _selectedLine! < _levels.length) {
                _levels.removeAt(_selectedLine!);
              } else if (_selectedPattern != null && _selectedPattern! < _patterns.length) {
                _patterns.removeAt(_selectedPattern!);
              }
              _selectedLine = null;
              _selectedPattern = null;
            }), icon: const Icon(Icons.delete_outline)),
          if (_lineUndo.isNotEmpty)
            TextButton.icon(
              onPressed: _undoDrawing,
              icon: const Icon(Icons.undo, size: 18),
              label: const Text('تراجع'),
            ),
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
          if (_liveRequested && _mode != ChartMode.range && _actualBars.isNotEmpty)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _olderLoading || _historyExhausted
                    ? null : () => _loadOlderHistory(manual: true),
                icon: _olderLoading
                    ? const SizedBox(width: 15, height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.history, size: 18),
                label: Text(_historyExhausted ? 'لا تتوفر شموع أقدم'
                    : 'تحميل شموع أقدم'),
              ),
            ),
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
    required this.timestamps,
    required this.dark,
    required this.viewport,
    required this.crosshair,
    required this.levels,
    required this.patterns,
    required this.selectedLine,
    required this.selectedPattern,
    required this.indicator,
    required this.isPreview,
  });

  final List<TradeCandle> candles;
  final List<int> timestamps;
  final bool dark;
  final ChartViewport viewport;
  final Offset? crosshair;
  final List<double> levels;
  final List<ChartPattern> patterns;
  final int? selectedLine;
  final int? selectedPattern;
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
    canvas.restore();
    if (timestamps.length >= candles.length) {
      // Real UTC dates only. Range bars and design fixtures have no
      // trustworthy candle timestamps and must not fabricate them.
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
      _text(canvas, isPreview ? 'معاينة' : 'شموع مدى',
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
      old.levels != levels || old.patterns != patterns ||
      old.selectedLine != selectedLine || old.selectedPattern != selectedPattern ||
      old.isPreview != isPreview;
}
