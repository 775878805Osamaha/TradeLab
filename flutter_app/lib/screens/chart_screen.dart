import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../chart/chart_viewport.dart';
import '../data/range_bar_builder.dart';
import '../data/tradelab_data.dart';
import '../theme/tradelab_theme.dart';
import '../widgets/trade_components.dart';

enum ChartMode { candles, heikinAshi, range }

class ChartScreen extends StatefulWidget {
  const ChartScreen({super.key});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  final _fixture = previewCandles();
  final _rangeCache = <int, List<TradeCandle>>{};
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

  @override
  void dispose() {
    _replayTimer?.cancel();
    super.dispose();
  }

  void _stopPlayback() {
    _replayTimer?.cancel();
    _replayTimer = null;
    _playing = false;
  }

  void _toggleReplay() => setState(() {
        _stopPlayback();
        _replay = !_replay;
        _visibleThrough = _fixture.length ~/ 2;
        _viewport = const ChartViewport();
        _crosshair = null;
      });

  void _togglePlay() {
    if (_playing) {
      setState(_stopPlayback);
      return;
    }
    setState(() => _playing = true);
    _replayTimer = Timer.periodic(const Duration(milliseconds: 650), (timer) {
      if (!mounted || !_replay || _visibleThrough >= _fixture.length) {
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
      if (!_replay) {
        return _rangeCache.putIfAbsent(_rangeTicks,
            () => previewRangeCandles(_rangeTicks));
      }
      final throughTick = (_visibleThrough / _fixture.length * 1800).round();
      return previewRangeCandles(_rangeTicks, throughTick: throughTick);
    }
    final count = _replay ? _visibleThrough : _fixture.length;
    final raw = _fixture.take(count).toList(growable: false);
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
            const Text('القيم هنا لضبط الواجهة فقط؛ الحساب الحقيقي سيستخدم أسعار BID من cTrader.'),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final size in const [100, 250, 500, 1000, 2000, 5000])
                ChoiceChip(
                  label: Text('$size'),
                  selected: _rangeTicks == size,
                  onSelected: (_) {
                    setState(() => _rangeTicks = size);
                    Navigator.pop(sheetContext);
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
                  Text('تحليل السوق · غير متصل',
                      style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
                ]),
              ),
            ),
          ),
          const TradeStatusChip(label: 'تجريبي'),
          _iconAction(icon: Icons.fullscreen, label: 'ملء الشاشة', onPressed: _notifyUnconnected),
          _iconAction(icon: Icons.refresh, label: 'تحديث أسعار السوق', onPressed: _notifyUnconnected),
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
          child: Text('مدى $_rangeTicks · عرض محسوب من تيكات تجريبية، وليس cTrader',
              style: const TextStyle(fontSize: 11, color: TradeColors.blue)),
        ),
      Expanded(
        child: LayoutBuilder(builder: (context, constraints) {
          final plotWidth = math.max(1.0, constraints.maxWidth - 61);
          return GestureDetector(
            key: const Key('chart-gesture-area'),
            behavior: HitTestBehavior.opaque,
            onScaleStart: (details) {
              _gestureStart = _viewport;
              _gestureFocalX = details.localFocalPoint.dx;
            },
            onScaleUpdate: (details) => setState(() {
              if (details.pointerCount > 1) {
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
            }),
            onDoubleTap: () => setState(() { _viewport = const ChartViewport(); _crosshair = null; }),
            onLongPressStart: (details) => setState(() => _crosshair = details.localPosition),
            onLongPressMoveUpdate: (details) => setState(() => _crosshair = details.localPosition),
            onLongPressEnd: (_) => setState(() => _crosshair = null),
            onTapUp: (details) {
              if (!_drawing || details.localPosition.dx > plotWidth) return;
              setState(() => _levels.add(details.localPosition.dy / constraints.maxHeight));
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
                  indicator: _showIndicators,
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
          const Expanded(child: Text('شموع توضيحية للتصميم وليست أسعارًا حقيقية',
              maxLines: 2, style: TextStyle(fontSize: 11))),
          if (_levels.isNotEmpty)
            TextButton.icon(
              onPressed: () => setState(() => _levels.removeLast()),
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
            Text('$_visibleThrough / ${_fixture.length} شمعة توضيحية',
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
              onPressed: _visibleThrough >= _fixture.length ? null : () => setState(() => _visibleThrough++),
              icon: const Icon(Icons.skip_next)),
            Expanded(child: Slider(
              value: _visibleThrough.toDouble(), min: 1, max: _fixture.length.toDouble(),
              divisions: _fixture.length - 1,
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
    required this.indicator,
  });

  final List<TradeCandle> candles;
  final bool dark;
  final ChartViewport viewport;
  final Offset? crosshair;
  final List<double> levels;
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
    final selected = candles.sublist(start, ending);
    final maximum = selected.map((c) => c.high).reduce(math.max) + .8;
    final minimum = selected.map((c) => c.low).reduce(math.min) - .8;
    final span = math.max(.00001, maximum - minimum);
    double y(double price) => (maximum - price) / span * chartHeight;
    final gridPaint = Paint()..color = line..strokeWidth = .8;
    for (var i = 0; i <= 5; i++) {
      final lineY = chartHeight * i / 5;
      canvas.drawLine(Offset(0, lineY), Offset(axis, lineY), gridPaint);
      _text(canvas, (maximum - span * i / 5).toStringAsFixed(2),
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
    for (final fraction in levels) {
      final levelY = fraction * size.height;
      final marker = Paint()..color = TradeColors.blue.withValues(alpha: .8)..strokeWidth = 1;
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
      _text(canvas, crossPrice.toStringAsFixed(2),
          Offset(axis + 3, markerY + 2), Colors.white, 10);
    }
    // A separate LTR price axis keeps digits and decimal points predictable in RTL.
    _text(canvas, 'معاينة', Offset(axis / 2 - 18, chartHeight + 3), text, 10);
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
      old.levels != levels;
}
