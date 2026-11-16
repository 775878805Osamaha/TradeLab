import 'package:flutter/material.dart';

/// Always-reachable shortcuts for chart actions that would otherwise require
/// discovering horizontal scrolling in the compact phone toolbar.
enum ChartQuickAction {
  candles,
  chartType,
  replay,
  drawingTools,
  analysis,
  appearance,
  indicators,
  move,
  latest,
  range,
  focusMode,
}

class ChartQuickActions extends StatelessWidget {
  const ChartQuickActions({
    required this.onCandles,
    required this.onChartType,
    required this.onReplay,
    required this.onDrawingTools,
    required this.onAnalysis,
    required this.onAppearance,
    required this.onIndicators,
    required this.onMove,
    required this.onLatest,
    required this.onRange,
    required this.onFocusMode,
    required this.rangeMode,
    required this.focusMode,
    super.key,
  });

  final VoidCallback onCandles;
  final VoidCallback onChartType;
  final VoidCallback onReplay;
  final VoidCallback onDrawingTools;
  final VoidCallback onAnalysis;
  final VoidCallback onAppearance;
  final VoidCallback onIndicators;
  final VoidCallback onMove;
  final VoidCallback onLatest;
  final VoidCallback onRange;
  final VoidCallback onFocusMode;
  final bool rangeMode;
  final bool focusMode;

  void _select(ChartQuickAction action) {
    switch (action) {
      case ChartQuickAction.candles:
        onCandles();
        break;
      case ChartQuickAction.chartType:
        onChartType();
        break;
      case ChartQuickAction.replay:
        onReplay();
        break;
      case ChartQuickAction.drawingTools:
        onDrawingTools();
        break;
      case ChartQuickAction.analysis:
        onAnalysis();
        break;
      case ChartQuickAction.appearance:
        onAppearance();
        break;
      case ChartQuickAction.indicators:
        onIndicators();
        break;
      case ChartQuickAction.move:
        onMove();
        break;
      case ChartQuickAction.latest:
        onLatest();
        break;
      case ChartQuickAction.range:
        if (rangeMode) onRange();
        break;
      case ChartQuickAction.focusMode:
        onFocusMode();
        break;
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 44,
    height: 44,
    child: PopupMenuButton<ChartQuickAction>(
      key: const Key('chart-quick-actions'),
      tooltip: 'المزيد من أدوات الشارت',
      child: const Icon(Icons.more_horiz, size: 21),
      onSelected: _select,
      itemBuilder: (_) => [
        PopupMenuItem(
          key: const Key('chart-quick-focus'),
          value: ChartQuickAction.focusMode,
          child: Text(focusMode ? 'الخروج من وضع الشارت الموسع' : 'توسيع الشارت ملء مساحة التطبيق')),
        const PopupMenuItem(
          key: Key('chart-quick-candles'),
          value: ChartQuickAction.candles,
          child: Text('إعدادات الشموع')),
        const PopupMenuItem(
          key: Key('chart-quick-chart-type'),
          value: ChartQuickAction.chartType,
          child: Text('نوع الرسم البياني')),
        const PopupMenuItem(
          key: Key('chart-quick-replay'),
          value: ChartQuickAction.replay,
          child: Text('إعادة تشغيل الشموع · Replay')),
        const PopupMenuItem(
          key: Key('chart-quick-drawing-tools'),
          value: ChartQuickAction.drawingTools,
          child: Text('أدوات الرسم')),
        const PopupMenuItem(
          key: Key('chart-quick-analysis'),
          value: ChartQuickAction.analysis,
          child: Text('محور التحليل')),
        const PopupMenuItem(
          key: Key('chart-quick-appearance'),
          value: ChartQuickAction.appearance,
          child: Text('إعدادات عرض الشارت')),
        const PopupMenuItem(
          key: Key('chart-quick-indicators'),
          value: ChartQuickAction.indicators,
          child: Text('المؤشرات')),
        const PopupMenuItem(
          key: Key('chart-quick-move'),
          value: ChartQuickAction.move,
          child: Text('تحريك الشارت')),
        const PopupMenuItem(
          key: Key('chart-quick-latest'),
          value: ChartQuickAction.latest,
          child: Text('العودة إلى أحدث شمعة')),
        if (rangeMode)
          const PopupMenuItem(
            key: Key('chart-quick-range'),
            value: ChartQuickAction.range,
            child: Text('إعدادات شموع المدى Range')),
      ],
    ),
  );
}
