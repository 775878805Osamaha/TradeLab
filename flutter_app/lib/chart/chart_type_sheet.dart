import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/tradelab_theme.dart';

/// All 21 visible entries, in the reference's RTL reading order.
enum ChartKind {
  bars('أعمدة'),
  candles('شموع'),
  hollowCandles('الشموع المجوفة'),
  volumeCandles('شموع الحجم'),
  line('خط'),
  markedLine('خط بعلامات'),
  steppedLine('خط متدرج'),
  area('مساحة'),
  hlcArea('منطقة HLC'),
  baseline('خط الأساس'),
  columns('الأعمدة'),
  highLow('أعلى-أدنى'),
  volumeFootprint('بصمة الحجم'),
  timePriceOpportunity('فرصة السعر الزمني'),
  sessionVolumeProfile('بروفايل أحجام التداول للجلسة'),
  heikinAshi('هايكين آشي'),
  renko('رينكو'),
  lineBreak('كسر الخط'),
  kagi('كاجي'),
  pointAndFigure('النقطة والرقم'),
  range('مدى');

  const ChartKind(this.label);
  final String label;

  // Never advertise an unimplemented chart engine as a working selection.
  bool get implemented =>
      this == candles || this == heikinAshi || this == range;
}

/// Only a bottom-sheet presentation. Market, Replay and viewport state remain
/// owned by ChartScreen; opening this does not touch a single candle.
class ChartTypeSheet extends StatelessWidget {
  const ChartTypeSheet({
    required this.selected,
    required this.onSelect,
    required this.onUnavailable,
    super.key,
  });

  final ChartKind selected;
  final ValueChanged<ChartKind> onSelect;
  final ValueChanged<ChartKind> onUnavailable;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final side = width * (30 / 691);
    final gap = width * (23 / 691);
    final cardWidth = (width - side * 2 - gap * 2) / 3;
    final cardHeight = cardWidth * (139 / 195);
    final headerHeight = width * (192 / 691);
    final footer = width * (49 / 691);
    final idealHeight = headerHeight + cardHeight * 7 + gap * 6 + footer;
    final available = math.max(1.0,
        media.size.height - media.padding.top - media.padding.bottom - 4);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        key: const Key('chart-type-bottom-sheet'),
        height: math.min(idealHeight, available),
        decoration: const BoxDecoration(
          color: TradeColors.chartTypeSheet,
          borderRadius: BorderRadius.vertical(top: Radius.circular(19)),
        ),
        child: Column(children: [
          SizedBox(
            height: headerHeight,
            child: Stack(children: [
              Positioned(
                top: width * (31 / 691),
                left: 0,
                right: 0,
                child: Center(child: Container(
                  width: width * (60 / 691),
                  height: math.max(3.5, width * (7 / 691)),
                  decoration: BoxDecoration(
                    color: TradeColors.chartTypeDragHandle,
                    borderRadius: BorderRadius.circular(8),
                  ),
                )),
              ),
              Positioned(
                bottom: width * (40 / 691),
                right: side,
                child: Text('نوع الرسم البياني',
                  key: const Key('chart-type-title'),
                  style: TextStyle(
                    color: TradeColors.chartTypeInk,
                    fontSize: (width * (47 / 691)).clamp(20.0, 26.0),
                    fontWeight: FontWeight.w800,
                    height: 1.18,
                  ),
                  textDirection: TextDirection.rtl,
                ),
              ),
            ]),
          ),
          Expanded(
            child: GridView.builder(
              key: const Key('chart-type-grid'),
              padding: EdgeInsets.fromLTRB(side, 0, side, footer),
              physics: const ClampingScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: gap,
                mainAxisSpacing: gap,
                childAspectRatio: 195 / 139,
              ),
              itemCount: ChartKind.values.length,
              itemBuilder: (context, index) {
                final kind = ChartKind.values[index];
                return ChartKindCard(kind: kind, selected: kind == selected,
                  onPressed: () => kind.implemented
                      ? onSelect(kind) : onUnavailable(kind));
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class ChartKindCard extends StatelessWidget {
  const ChartKindCard({
    required this.kind,
    required this.selected,
    required this.onPressed,
    super.key,
  });
  final ChartKind kind;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ink = selected ? Colors.white : TradeColors.chartTypeInk;
    return Semantics(
      button: true,
      selected: selected,
      label: kind.label,
      hint: kind.implemented ? 'اختيار نوع الرسم' : 'غير مدعوم حاليًا',
      child: GestureDetector(
        key: Key('chart-kind-' + kind.name),
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          decoration: BoxDecoration(
            color: selected
                ? TradeColors.chartTypeSelected : TradeColors.chartTypeTile,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.fromLTRB(3, 9, 3, 5),
          child: Column(children: [
            ExcludeSemantics(child: SizedBox(
              width: 28, height: 28,
              child: CustomPaint(
                painter: ChartKindGlyphPainter(kind: kind, color: ink)),
            )),
            const SizedBox(height: 2),
            Expanded(child: Center(child: Text(kind.label,
              key: Key('chart-kind-label-' + kind.name),
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              maxLines: 3,
              style: TextStyle(color: ink, fontSize: 12.5,
                fontWeight: FontWeight.w700, height: 1.14),
            ))),
          ]),
        ),
      ),
    );
  }
}

/// Small, individually identifiable vector glyphs. They cannot be mistaken
/// for real market history and add no package or licensed icon dependency.
class ChartKindGlyphPainter extends CustomPainter {
  const ChartKindGlyphPainter({required this.kind, required this.color});
  final ChartKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32, size.height / 32);
    final stroke = Paint()..color = color..strokeWidth = 2.2
      ..style = PaintingStyle.stroke..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final thin = Paint()..color = color..strokeWidth = 1.5
      ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    void line(double x, double y, double x2, double y2, [Paint? p]) =>
        canvas.drawLine(Offset(x,y),Offset(x2,y2),p ?? stroke);
    void box(double x,double y,double w,double h,[Paint? p]) =>
        canvas.drawRect(Rect.fromLTWH(x,y,w,h),p ?? stroke);
    void path(List<Offset> points,[Paint? p]) {
      final v = Path()..moveTo(points.first.dx,points.first.dy);
      for (final q in points.skip(1)) { v.lineTo(q.dx,q.dy); }
      canvas.drawPath(v,p ?? stroke);
    }
    void candle(double x,double y1,double y2,double body1,double body2) {
      line(x,y1,x,y2,thin);
      box(x-3.5,body1,7,body2-body1);
    }

    switch (kind) {
      case ChartKind.bars:
        line(11,5,11,27);line(5,13,11,13);line(11,20,17,20);
        line(23,3,23,25);line(19,11,23,11);line(23,18,28,18);
      case ChartKind.candles:
        candle(10,4,28,8,22);candle(23,5,26,11,20);
      case ChartKind.hollowCandles:
        candle(10,3,28,7,22);candle(23,6,26,11,19);
        for (var y=8.0;y<22;y+=3.2) { line(7,y,13,y+3,thin); }
      case ChartKind.volumeCandles:
        candle(11,7,27,11,21);candle(23,3,29,7,23);line(6,29,27,29,thin);
      case ChartKind.line:
        path(const [Offset(3,22),Offset(12,12),Offset(19,19),Offset(29,8)]);
      case ChartKind.markedLine:
        path(const [Offset(3,25),Offset(12,14),Offset(19,20),Offset(29,7)]);
        for (final p in const [Offset(12,14),Offset(19,20)]) {
          canvas.drawCircle(p,3.2,Paint()..color=TradeColors.chartTypeTile);
          canvas.drawCircle(p,3.2,stroke);
        }
      case ChartKind.steppedLine:
        path(const [Offset(3,26),Offset(10,26),Offset(10,14),Offset(17,14),
          Offset(17,20),Offset(24,20),Offset(24,6),Offset(30,6)]);
      case ChartKind.area:
        path(const [Offset(3,22),Offset(11,13),Offset(18,20),Offset(29,8)]);
        for (var x=4.0;x<30;x+=3.5) {line(x,26,x,28,thin);}
        line(4,29,29,29,thin);
      case ChartKind.hlcArea:
        path(const [Offset(3,18),Offset(10,8),Offset(16,17),Offset(23,6),Offset(29,10)]);
        path(const [Offset(3,23),Offset(10,13),Offset(16,22),Offset(23,12),Offset(29,16)],thin);
        path(const [Offset(3,28),Offset(10,18),Offset(16,27),Offset(23,17),Offset(29,21)],thin);
      case ChartKind.baseline:
        path(const [Offset(3,22),Offset(12,12),Offset(19,18),Offset(29,7)]);
        for(var x=3.0;x<29;x+=5) {line(x,26,x+2.5,26,thin);}
      case ChartKind.columns:
        box(3,16,6,13);box(13,7,6,22);box(23,20,6,9);
      case ChartKind.highLow:
        box(7,6,7,22);box(19,10,7,15);
      case ChartKind.volumeFootprint:
        candle(7,4,29,10,22);
        for(var y=8.0;y<27;y+=6) {line(15,y,28,y);}
      case ChartKind.timePriceOpportunity:
        for(var i=0;i<4;i++) {
          line(4,5+i*6,4,10+i*6,thin);
          line(11,5+i*6,11,10+i*6,thin);
          line(18,11+i*4,18,15+i*4,thin);
        }
        line(3,11,24,11,thin);line(3,17,29,17,thin);line(3,23,23,23,thin);
      case ChartKind.sessionVolumeProfile:
        line(5,3,5,28);
        for(final v in const [(7.0,11.0),(13.0,16.0),(19.0,22.0),(25.0,14.0)]) {
          box(5,v.$1,v.$2,4);
        }
      case ChartKind.heikinAshi:
        candle(7,8,26,11,23);candle(17,4,28,7,19);candle(27,9,25,12,22);
      case ChartKind.renko:
        box(4,20,7,8);box(13,13,7,8);box(22,6,7,8);
      case ChartKind.lineBreak:
        box(4,16,7,12);box(13,5,7,12);box(22,19,7,11);
      case ChartKind.kagi:
        path(const [Offset(3,27),Offset(3,20),Offset(10,20),Offset(10,5),
          Offset(17,5),Offset(17,27),Offset(25,27),Offset(25,12),Offset(29,12)]);
      case ChartKind.pointAndFigure:
        for(var x=5.0;x<=27;x+=11) {
          for(var y=6.0;y<=28;y+=11) {
            if(x==16) {canvas.drawCircle(Offset(x,y),2.5,stroke);}
            else {line(x-2.4,y-2.4,x+2.4,y+2.4,thin);
              line(x-2.4,y+2.4,x+2.4,y-2.4,thin);}
          }
        }
      case ChartKind.range:
        path(const [Offset(3,26),Offset(9,26),Offset(9,7),Offset(18,7),
          Offset(18,17),Offset(24,17)]);
        final text=TextPainter(text:TextSpan(text:'R',
          style:TextStyle(color:color,fontSize:10,fontWeight:FontWeight.w800)),
          textDirection:TextDirection.ltr)..layout();
        text.paint(canvas,const Offset(21,20));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ChartKindGlyphPainter previous) =>
      previous.kind!=kind || previous.color!=color;
}
