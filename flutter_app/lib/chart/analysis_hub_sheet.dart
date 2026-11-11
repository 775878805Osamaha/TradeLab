import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tradelab_theme.dart';

/// Command identifiers only. The chart owns all operations, market history,
/// viewport, Replay and navigation; opening this sheet never fetches candles.
enum AnalysisHubAction {
  layoutFormat('إعداد التنسيق'),
  layoutManager('إدارة \u2066Unnamed\u2069'),
  drawingSettings('إعدادات الرسم ال...'),
  newLayout('جديد'),
  saveLayout('حفظ'),
  openLayout('افتتاح'),
  tradeWithBroker('تداول مع وسيطك'),
  indicators('مؤشرات'),
  compare('قارن'),
  alerts('تنبيهات'),
  replay('إعادة تشغيل الأعمدة'),
  indicatorTemplates('قوالب المؤشر'),
  chartType('نوع الرسم البياني'),
  objectTree('شجرة الكائنات'),
  symbolInformation('معلومات الرمز'),
  dataSource('مصدر البيانات');

  const AnalysisHubAction(this.label);
  final String label;

  bool get enabled => this != saveLayout;
}

/// Pixel-reference command surface, presented with showModalBottomSheet.
/// It is intentionally distinct from the app-wide Material theme.
class AnalysisHubSheet extends StatelessWidget {
  const AnalysisHubSheet({required this.onAction, super.key});

  final ValueChanged<AnalysisHubAction> onAction;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final unit = width / 691;
    final side = width * (30 / 691);
    final gap = width * (15 / 691);
    final available = math.max(260.0,
        media.size.height - media.padding.top - media.padding.bottom);
    final idealHeight = width * (1310 / 691);
    // Preserve the reference's visible chart strip on taller Android displays.
    // Android's reserved system areas require a slightly taller modal than
    // the visible 691x1536 screenshot ratio suggests.
    final height = math.min(idealHeight,
      math.min(available - media.viewInsets.bottom,
        media.size.height * .881));

    Widget row(List<AnalysisHubAction> actions, double height) {
      return Row(children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i != 0) SizedBox(width: gap),
          Expanded(child: AnalysisActionTile(
            action: actions[i], height: height * unit,
            filled: actions[i] != AnalysisHubAction.layoutFormat &&
                actions[i] != AnalysisHubAction.layoutManager &&
                actions[i] != AnalysisHubAction.drawingSettings &&
                actions[i] != AnalysisHubAction.newLayout &&
                actions[i] != AnalysisHubAction.saveLayout &&
                actions[i] != AnalysisHubAction.openLayout,
            onTap: actions[i].enabled ? () => onAction(actions[i]) : null,
          )),
        ],
      ]);
    }

    Widget sectionTitle(String label) => Padding(
      padding: EdgeInsetsDirectional.only(start: side, end: side),
      child: Align(alignment: AlignmentDirectional.centerStart,
        child: Text(label, textDirection: TextDirection.rtl,
          style: TextStyle(color: TradeColors.analysisMuted,
            fontWeight: FontWeight.w700,
            fontSize: (27 * unit).clamp(14.0, 20.0))),
      ),
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        key: const Key('analysis-hub-sheet'),
        width: width,
        height: height,
        decoration: const BoxDecoration(
          color: TradeColors.analysisSheet,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(children: [
          SizedBox(height: 196 * unit,
            child: Stack(children: [
              Positioned(top: 44 * unit, left: 0, right: 0,
                child: Center(child: Container(
                  key: const Key('analysis-hub-handle'),
                  width: 60 * unit, height: math.max(3.5, 7 * unit),
                  decoration: BoxDecoration(
                    color: TradeColors.analysisHandle,
                    borderRadius: BorderRadius.circular(8),
                  ),
                )),
              ),
              Positioned(top: 96 * unit, right: side,
                child: Text('محور التحليل',
                  key: const Key('analysis-hub-title'),
                  textDirection: TextDirection.rtl,
                  style: TextStyle(color: TradeColors.analysisInk,
                    fontSize: (47 * unit).clamp(24.0, 31.0),
                    fontWeight: FontWeight.w800, height: 1.17),
                ),
              ),
            ]),
          ),
          Expanded(child: SingleChildScrollView(
            key: const Key('analysis-hub-scroll'),
            physics: const ClampingScrollPhysics(),
            child: Column(children: [
              Padding(padding: EdgeInsets.symmetric(horizontal: side),
                child: Column(children: [
                  row(const [AnalysisHubAction.layoutFormat,
                    AnalysisHubAction.layoutManager,
                    AnalysisHubAction.drawingSettings], 112),
                  SizedBox(height: 23 * unit),
                  row(const [AnalysisHubAction.newLayout,
                    AnalysisHubAction.saveLayout,
                    AnalysisHubAction.openLayout], 112),
                ]),
              ),
              SizedBox(height: 46 * unit),
              const Divider(height: 1, thickness: 1,
                color: TradeColors.analysisBorder),
              SizedBox(height: 47 * unit),
              Padding(padding: EdgeInsets.symmetric(horizontal: side),
                child: AnalysisBrokerCard(onTap: () =>
                    onAction(AnalysisHubAction.tradeWithBroker),
                  height: 138 * unit)),
              SizedBox(height: 28 * unit),
              sectionTitle('أدوات'),
              SizedBox(height: 12 * unit),
              Padding(padding: EdgeInsets.symmetric(horizontal: side),
                child: Column(children: [
                  row(const [AnalysisHubAction.indicators,
                    AnalysisHubAction.compare], 138),
                  SizedBox(height: 15 * unit),
                  row(const [AnalysisHubAction.alerts,
                    AnalysisHubAction.replay], 138),
                  SizedBox(height: 16 * unit),
                  row(const [AnalysisHubAction.indicatorTemplates,
                    AnalysisHubAction.chartType,
                    AnalysisHubAction.objectTree], 139),
                ]),
              ),
              SizedBox(height: 25 * unit),
              sectionTitle('معلومات'),
              SizedBox(height: 12 * unit),
              Padding(padding: EdgeInsets.symmetric(horizontal: side),
                child: row(const [AnalysisHubAction.symbolInformation,
                  AnalysisHubAction.dataSource], 137)),
              SizedBox(height: math.max(20.0, 45 * unit)),
            ]),
          )),
        ]),
      ),
    );
  }
}

/// A single tile supports disabled and enabled states, true RTL, and a stable
/// key for interaction and golden tests. Unsupported actions still open a
/// truthful explanation provided by the owning chart.
class AnalysisActionTile extends StatelessWidget {
  const AnalysisActionTile({required this.action, required this.height,
    required this.filled, required this.onTap, super.key});

  final AnalysisHubAction action;
  final double height;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final unit = width / 691;
    final enabled = onTap != null;
    final ink = enabled
        ? TradeColors.analysisInk : TradeColors.analysisDisabled;
    return Semantics(
      button: true, enabled: enabled, label: action.label,
      child: GestureDetector(
        key: Key('analysis-action-${action.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: filled ? TradeColors.analysisTile : TradeColors.analysisSheet,
            borderRadius: BorderRadius.circular(22 * unit),
            border: filled ? null : Border.all(
              color: TradeColors.analysisBorder,
              width: math.max(.6, 1.5 * unit)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(5 * unit, 13 * unit,
                5 * unit, 6 * unit),
            child: Column(children: [
              ExcludeSemantics(child: SizedBox(
                height: 48 * unit, width: 52 * unit,
                child: CustomPaint(painter: AnalysisGlyphPainter(
                  action: action, color: ink)),
              )),
              SizedBox(height: 5 * unit),
              Expanded(child: Center(child: Text(action.label,
                key: Key('analysis-action-label-${action.name}'),
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: ink,
                  fontWeight: FontWeight.w700,
                  fontSize: (25 * unit).clamp(12.0, 17.0),
                  height: 1.1),
              ))),
            ]),
          ),
        ),
      ),
    );
  }
}

class AnalysisBrokerCard extends StatelessWidget {
  const AnalysisBrokerCard({required this.onTap, required this.height,
    super.key});

  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final unit = MediaQuery.sizeOf(context).width / 691;
    return Semantics(button: true, label: 'تداول مع وسيطك', child:
      GestureDetector(
        key: const Key('analysis-action-tradeWithBroker'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(height: height, width: double.infinity,
          padding: EdgeInsets.all(math.max(1.1, 2.5 * unit)),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [
              TradeColors.analysisBrokerPink,
              TradeColors.analysisBrokerBlue,
            ]),
            borderRadius: BorderRadius.circular(23 * unit),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: TradeColors.analysisTile,
              borderRadius: BorderRadius.circular(21 * unit),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 56 * unit, height: 50 * unit,
                  child: CustomPaint(painter: const AnalysisGlyphPainter(
                    action: AnalysisHubAction.tradeWithBroker,
                    color: TradeColors.analysisInk))),
                SizedBox(height: 10 * unit),
                Text('تداول مع وسيطك',
                  style: TextStyle(color: TradeColors.analysisInk,
                    fontSize: (27 * unit).clamp(14.0, 19.0),
                    fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Original stroke illustrations: no copied TradingView icon assets.
class AnalysisGlyphPainter extends CustomPainter {
  const AnalysisGlyphPainter({required this.action, required this.color});
  final AnalysisHubAction action;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);
    final p = Paint()..color = color..strokeWidth = 2.6
      ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void line(double x, double y, double x2, double y2) =>
        canvas.drawLine(Offset(x,y),Offset(x2,y2),p);
    void path(List<Offset> points) {
      final shape = Path()..moveTo(points.first.dx,points.first.dy);
      for (final v in points.skip(1)) { shape.lineTo(v.dx,v.dy); }
      canvas.drawPath(shape,p);
    }
    void rect(double x,double y,double w,double h,[double radius=3]) =>
        canvas.drawRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(x,y,w,h),Radius.circular(radius)),p);
    void circle(double x,double y,double radius) =>
        canvas.drawCircle(Offset(x,y),radius,p);

    switch (action) {
      case AnalysisHubAction.layoutFormat:
        rect(8,7,32,33,3);
      case AnalysisHubAction.layoutManager:
        rect(8,8,29,31,4);path(const [Offset(13,26),Offset(19,20),
          Offset(24,26),Offset(30,19)]);
        canvas.drawCircle(const Offset(35,35),7,p);
        circle(35,35,2);
      case AnalysisHubAction.drawingSettings:
        path(const [Offset(14,6),Offset(34,6),Offset(44,24),
          Offset(34,42),Offset(14,42),Offset(4,24),Offset(14,6)]);
        circle(24,24,7);
      case AnalysisHubAction.newLayout:
        rect(7,8,31,30);path(const [Offset(12,26),Offset(19,18),
          Offset(25,24),Offset(31,15)]);
        line(38,31,38,43);line(32,37,44,37);
      case AnalysisHubAction.saveLayout:
        path(const [Offset(10,32),Offset(7,28),Offset(8,21),
          Offset(14,16),Offset(19,16),Offset(24,9),Offset(32,9),
          Offset(39,15),Offset(40,21),Offset(44,25),Offset(43,32)]);
        line(24,19,24,40);path(const [Offset(16,27),Offset(24,19),
          Offset(32,27)]);
      case AnalysisHubAction.openLayout:
        path(const [Offset(6,16),Offset(6,38),Offset(42,38),
          Offset(42,17),Offset(25,17),Offset(20,12),Offset(6,12),
          Offset(6,16)]);
        line(7,21,42,21);
      case AnalysisHubAction.tradeWithBroker:
        path(const [Offset(6,31),Offset(18,19),Offset(27,28),
          Offset(38,17),Offset(43,22),Offset(27,38),
          Offset(18,29),Offset(11,36),Offset(6,31)]);
        path(const [Offset(9,27),Offset(18,18),Offset(28,28),
          Offset(37,19)]);
      case AnalysisHubAction.indicators:
        rect(7,33,8,9,0);rect(19,28,8,14,0);rect(31,23,8,19,0);
        path(const [Offset(6,22),Offset(15,13),Offset(23,20),
          Offset(36,6)]);
      case AnalysisHubAction.compare:
        circle(24,24,19);line(24,13,24,35);line(13,24,35,24);
      case AnalysisHubAction.alerts:
        circle(24,25,15);line(24,15,24,25);line(24,25,32,25);
        line(9,6,4,13);line(39,6,44,13);
      case AnalysisHubAction.replay:
        path(const [Offset(5,24),Offset(21,9),Offset(21,39),
          Offset(5,24)]);
        path(const [Offset(21,24),Offset(39,9),Offset(39,39),
          Offset(21,24)]);
      case AnalysisHubAction.indicatorTemplates:
        for (final x in [7.0,26.0]) {
          for (final y in [8.0,27.0]) {rect(x,y,14,14);}
        }
      case AnalysisHubAction.chartType:
        line(16,5,16,42);rect(11,12,10,25,1);
        line(34,10,34,42);rect(29,16,10,18,1);
      case AnalysisHubAction.objectTree:
        path(const [Offset(8,21),Offset(24,11),Offset(40,21),
          Offset(24,30),Offset(8,21)]);
        path(const [Offset(8,29),Offset(24,39),Offset(40,29)]);
      case AnalysisHubAction.symbolInformation:
        circle(24,24,18);circle(24,15,1);
        line(24,22,24,34);
      case AnalysisHubAction.dataSource:
        rect(8,28,8,14,0);rect(20,19,8,23,0);rect(32,11,8,31,0);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AnalysisGlyphPainter old) =>
      old.action != action || old.color != color;
}
