import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tradelab_theme.dart';

/// Reference order: the visible Gann/Fibonacci tab contains 15 independent
/// tools. Only an engine already present in ChartScreen can be activated.
enum DrawingCatalogKind {
  fibonacciRetracement('تصحيحات فيبوناتشي', DrawingCategory.gann),
  fibonacciExtension('امتداد فيبوناتشي', DrawingCategory.gann),
  fibonacciChannel('قناة فيبوناتشي', DrawingCategory.gann),
  fibonacciTimeZone('منطقة الزمن فيبوناتشي', DrawingCategory.gann),
  resistanceFan('مروحة مقاومة السرعة', DrawingCategory.gann),
  fibonacciTime('وقت فيبوناتشي', DrawingCategory.gann),
  fibonacciCircles('دوائر فيبوناتشي', DrawingCategory.gann),
  fibonacciSpiral('حلزون فيبوناتشي', DrawingCategory.gann),
  resistanceArcs('أقواس مقاومة السرعة', DrawingCategory.gann),
  fibonacciWedge('إسفين فيبوناتشي', DrawingCategory.gann),
  pitchfan('بيتشَفان', DrawingCategory.gann),
  gannBox('صندوق جان', DrawingCategory.gann),
  fixedGannSquare('مربع جان الثابت', DrawingCategory.gann),
  gannSquare('مربع جان', DrawingCategory.gann),
  gannFan('مروحة جان', DrawingCategory.gann),
  // PROMPT 05: exact RTL grid order, seven rows are not inferred: 3+3+3+3+3+2.
  trendLine('خط اتجاه', DrawingCategory.trend),
  ray('شعاع', DrawingCategory.trend),
  infoLine('خط معلومات', DrawingCategory.trend),
  extendedLine('خط ممتد', DrawingCategory.trend),
  trendAngle('زاوية الاتجاه', DrawingCategory.trend),
  horizontal('خط أفقي', DrawingCategory.trend),
  horizontalRay('شعاع أفقي', DrawingCategory.trend),
  verticalLine('خط رأسي', DrawingCategory.trend),
  crossLine('خط عرضي', DrawingCategory.trend),
  parallelChannel('قناة متوازية', DrawingCategory.trend),
  regressionTrend('اتجاه الانحدار', DrawingCategory.trend),
  flatTopBottom('قمة/قاع مسطح', DrawingCategory.trend),
  disjointChannel('قناة منفصلة', DrawingCategory.trend),
  pitchfork('بيتش فورك', DrawingCategory.trend),
  schiffPitchfork('شوكة شيف', DrawingCategory.trend),
  modifiedSchiffPitchfork('شوكة شيف المعدلة', DrawingCategory.trend),
  insidePitchfork('شوكة داخلية', DrawingCategory.trend),
  shortPosition('مركز بيع · الدخول ثم الوقف والهدف', DrawingCategory.tools),
  priceRectangle('مستطيل نطاق سعري · زاويتان', DrawingCategory.tools),
  magnet('مغناطيس الأسعار', DrawingCategory.tools);

  const DrawingCatalogKind(this.label, this.category);
  final String label;
  final DrawingCategory category;

  bool get implemented => switch (this) {
    fibonacciRetracement || trendLine || ray || extendedLine || horizontal ||
      horizontalRay || verticalLine || parallelChannel || shortPosition ||
      priceRectangle || magnet => true,
    _ => false,
  };
}

enum DrawingCategory {
  favorites('المفضلة'),
  tools('أدوات'),
  trend('أدوات الاتجاه'),
  gann('جان وفيبوناتشي');

  const DrawingCategory(this.label);
  final String label;
}

/// Unknown IDs are ignored so stored favorites survive catalog upgrades.
class DrawingFavoritesCodec {
  const DrawingFavoritesCodec._();

  static String encode(Set<DrawingCatalogKind> favorites) =>
      jsonEncode(favorites.map((tool) => tool.name).toList());

  static Set<DrawingCatalogKind> decode(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! List) return {};
    final valid = {for (final tool in DrawingCatalogKind.values) tool.name: tool};
    return {
      for (final item in decoded)
        if (item is String && valid.containsKey(item)) valid[item]!,
    };
  }
}

class DrawingToolsSheet extends StatefulWidget {
  const DrawingToolsSheet({
    required this.favorites,
    required this.onFavoritesChanged,
    required this.onSelect,
    required this.onUnavailable,
    this.initialCategory = DrawingCategory.gann,
    super.key,
  });

  final Set<DrawingCatalogKind> favorites;
  final ValueChanged<Set<DrawingCatalogKind>> onFavoritesChanged;
  final ValueChanged<DrawingCatalogKind> onSelect;
  final ValueChanged<DrawingCatalogKind> onUnavailable;
  final DrawingCategory initialCategory;

  @override
  State<DrawingToolsSheet> createState() => _DrawingToolsSheetState();
}

class _DrawingToolsSheetState extends State<DrawingToolsSheet> {
  late Set<DrawingCatalogKind> _favorites;
  final TextEditingController _search = TextEditingController();
  final ScrollController _categories = ScrollController();
  late DrawingCategory _category;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    _favorites = {...widget.favorites};
  }

  @override
  void dispose() {
    _categories.dispose();
    _search.dispose();
    super.dispose();
  }

  List<DrawingCatalogKind> get _visibleTools {
    final query = _search.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      return DrawingCatalogKind.values.where((t) =>
          t.label.toLowerCase().contains(query)).toList();
    }
    if (_category == DrawingCategory.favorites) {
      return DrawingCatalogKind.values.where(_favorites.contains).toList();
    }
    return DrawingCatalogKind.values.where((t) =>
        t.category == _category).toList();
  }

  void _toggleFavorite(DrawingCatalogKind tool) {
    setState(() {
      if (!_favorites.add(tool)) _favorites.remove(tool);
    });
    widget.onFavoritesChanged({..._favorites});
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final side = width * (30 / 691);
    final gap = width * (15 / 691);
    final available = math.max(200.0,
        media.size.height - media.padding.top - media.padding.bottom);
    // 691px reference: sheet starts after the Android status bar, with its
    // bottom held above system navigation, leaving whitespace after row five.
    final ideal = width * (1398 / 691);
    final insetBottom = media.viewInsets.bottom;
    final height = math.max(240.0, math.min(ideal, available - insetBottom));

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        key: const Key('drawing-tools-bottom-sheet'),
        height: height,
        decoration: const BoxDecoration(
          color: TradeColors.drawingSheet,
          borderRadius: BorderRadius.vertical(top: Radius.circular(19)),
        ),
        child: Column(children: [
          SizedBox(
            height: width * (157 / 691),
            child: Stack(children: [
              Positioned(
                left: 0, right: 0, top: width * (25 / 691),
                child: Center(child: Container(
                  width: width * (60 / 691),
                  height: math.max(3.5, width * (7 / 691)),
                  decoration: BoxDecoration(
                    color: TradeColors.drawingHandle,
                    borderRadius: BorderRadius.circular(8),
                  ),
                )),
              ),
              Positioned(
                right: side, top: width * (82 / 691),
                child: Text('رسومات',
                  key: const Key('drawing-tools-title'),
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: (width * (47 / 691)).clamp(20.0, 27.0),
                    color: TradeColors.drawingInk,
                    fontWeight: FontWeight.w800,
                    height: 1.18,
                  ),
                ),
              ),
            ]),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: side),
            child: SizedBox(
              height: width * (82 / 691),
              child: TextField(
                key: const Key('drawing-tools-search'),
                controller: _search,
                onChanged: (_) => setState(() {}),
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                textInputAction: TextInputAction.search,
                style: TextStyle(
                  fontSize: (width * (29 / 691)).clamp(14.0, 19.0),
                  fontWeight: FontWeight.w600,
                  color: TradeColors.drawingInk,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: TradeColors.drawingTile,
                  hintText: 'بحث',
                  hintStyle: const TextStyle(
                    color: TradeColors.drawingMutedInk,
                    fontWeight: FontWeight.w600,
                  ),
                  prefixIcon: Icon(Icons.search,
                    size: width * (37 / 691),
                    color: TradeColors.drawingInk),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: width * (19 / 691)),
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(width * (22 / 691)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(width * (22 / 691)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(width * (22 / 691)),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: width * (22 / 691)),
          SizedBox(
            height: width * (62 / 691),
            // The reference presents the selected final RTL category at the
            // *left* edge, with Favorites partially clipped on the right.
            // A physical LTR scrolling row keeps this initial offset stable;
            // every category label itself remains Arabic/RTL.
            child: Directionality(textDirection: TextDirection.ltr,
              child: SingleChildScrollView(
              key: const Key('drawing-tools-category-scroll'),
              scrollDirection: Axis.horizontal,
              controller: _categories,
              padding: EdgeInsets.symmetric(
                horizontal: width * (34 / 691),
              ),
              child: Row(children: [
                for (final category in DrawingCategory.values.toList().reversed)
                  Padding(
                    padding: EdgeInsets.only(right: width * (22 / 691)),
                    child: DrawingCategoryTab(
                      category: category,
                      selected: _category == category,
                      referenceWidth: width,
                      onTap: () {
                        setState(() {
                          _category = category;
                          _search.clear();
                        });
                      },
                    ),
                  ),
              ]),
            ),
            ),
          ),
          SizedBox(height: width * (24 / 691)),
          Expanded(child: _visibleTools.isEmpty
              ? Center(child: Text('لا توجد أدوات مطابقة',
                  style: TextStyle(color: TradeColors.drawingMutedInk,
                      fontSize: (width * (25 / 691)).clamp(13.0, 18.0))))
              : GridView.builder(
                  key: const Key('drawing-tools-grid'),
                  padding: EdgeInsets.fromLTRB(side, 0, side, width * (20 / 691)),
                  physics: const ClampingScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: gap,
                    mainAxisSpacing: gap,
                    childAspectRatio: 200 / 135,
                  ),
                  itemCount: _visibleTools.length,
                  itemBuilder: (context, i) {
                    final tool = _visibleTools[i];
                    return DrawingToolTile(
                      tool: tool,
                      isFavorite: _favorites.contains(tool),
                      onToggleFavorite: () => _toggleFavorite(tool),
                      onTap: () => tool.implemented
                          ? widget.onSelect(tool)
                          : widget.onUnavailable(tool),
                    );
                  },
                )),
        ]),
      ),
    );
  }
}

class DrawingCategoryTab extends StatelessWidget {
  const DrawingCategoryTab({
    required this.category,
    required this.selected,
    required this.referenceWidth,
    required this.onTap,
    super.key,
  });

  final DrawingCategory category;
  final bool selected;
  final double referenceWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: GestureDetector(
      key: Key('drawing-category-' + category.name),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: referenceWidth * (62 / 691),
        padding: EdgeInsets.symmetric(
          horizontal: referenceWidth * ((selected ? 27 : 18) / 691),
        ),
        decoration: BoxDecoration(
          color: selected ? TradeColors.drawingTile : Colors.transparent,
          borderRadius: BorderRadius.circular(referenceWidth * (16 / 691)),
        ),
        alignment: Alignment.center,
        child: Text(category.label,
          textDirection: TextDirection.rtl,
          style: TextStyle(
            color: selected ? TradeColors.drawingInk
                : TradeColors.drawingMutedInk,
            fontSize: (referenceWidth * (28 / 691)).clamp(13.5, 18.0),
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

class DrawingToolTile extends StatelessWidget {
  const DrawingToolTile({
    required this.tool,
    required this.isFavorite,
    required this.onTap,
    required this.onToggleFavorite,
    super.key,
  });

  final DrawingCatalogKind tool;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    // Use the *actual grid cell*, not MediaQuery width: the legacy chart can
    // be narrower than the window, and fixed icon heights then overflow.
    return LayoutBuilder(builder: (context, constraints) {
    final unit = constraints.maxWidth / 200;
    return Semantics(
      button: true,
      label: tool.label,
      hint: tool.implemented
          ? 'اختيار أداة رسم، الضغط المطول لتغيير المفضلة'
          : 'أداة غير مدعومة بعد، الضغط المطول لتغيير المفضلة',
      child: GestureDetector(
        key: Key('drawing-tool-' + tool.name),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onToggleFavorite,
        child: Container(
          decoration: BoxDecoration(
            color: TradeColors.drawingTile,
            borderRadius: BorderRadius.circular(19 * unit),
          ),
          child: Stack(children: [
            Column(children: [
              SizedBox(height: 13 * unit),
              SizedBox(
                height: 61 * unit,
                child: Center(child: SizedBox(
                  width: 54 * unit,
                  height: 54 * unit,
                  child: CustomPaint(painter: DrawingToolGlyphPainter(tool)),
                )),
              ),
              Expanded(child: Center(child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 5 * unit),
                child: Text(tool.label,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: (24 * unit).clamp(10.5, 14.0),
                    fontWeight: FontWeight.w700,
                    color: TradeColors.drawingInk,
                  ),
                ),
              ))),
            ]),
            if (isFavorite) Positioned(
              top: 8 * unit,
              left: 8 * unit,
              child: Semantics(
                button: true,
                label: 'إزالة ${tool.label} من المفضلة',
                child: GestureDetector(
                  key: Key('drawing-favorite-' + tool.name),
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggleFavorite,
                  child: Icon(Icons.star,
                    size: 27 * unit,
                    color: TradeColors.drawingFavorite),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
    });
  }
}

/// Independent vector symbols for the tools visible in the reference.
/// No TradingView-owned bitmap or glyph file is used.
class DrawingToolGlyphPainter extends CustomPainter {
  const DrawingToolGlyphPainter(this.tool);
  final DrawingCatalogKind tool;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 52, size.height / 52);
    final linePaint = Paint()
      ..color = TradeColors.drawingInk
      ..strokeWidth = 3.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final thin = Paint()
      ..color = TradeColors.drawingInk
      ..strokeWidth = 2.3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    void line(double a, double b, double c, double d, [Paint? p]) =>
        canvas.drawLine(Offset(a,b), Offset(c,d), p ?? linePaint);
    void poly(List<Offset> pts, [Paint? p]) {
      final path = Path()..moveTo(pts.first.dx,pts.first.dy);
      for (final v in pts.skip(1)) { path.lineTo(v.dx,v.dy); }
      canvas.drawPath(path,p ?? linePaint);
    }
    void dot(double x,double y,[double radius=4]) {
      canvas.drawCircle(Offset(x,y),radius,
          Paint()..color = TradeColors.drawingTile);
      canvas.drawCircle(Offset(x,y),radius,linePaint);
    }
    void rectangle(double x,double y,double w,double h) =>
        canvas.drawRect(Rect.fromLTWH(x,y,w,h),linePaint);
    void arc(double radius,double start,double sweep,Offset center) =>
        canvas.drawArc(Rect.fromCircle(center:center,radius:radius),
            start,sweep,false,linePaint);
    void spokes(int count,{double from=7,double to=45}) {
      for (var i=0;i<count;i++) {
        final a=-math.pi/2 + i*(math.pi/2)/(count-1);
        line(from,43,from+(to-from)*math.cos(a),
            43+(to-from)*math.sin(a));
      }
      dot(from,43,3.4);
    }

    switch(tool) {
      case DrawingCatalogKind.fibonacciRetracement:
        line(7,7,46,7);line(13,18,46,18);
        line(7,29,46,29);line(7,40,46,40);
        dot(37,18);dot(13,29);
      case DrawingCatalogKind.fibonacciExtension:
        line(6,20,45,20);line(6,30,45,30);line(6,40,45,40);
        poly(const [Offset(7,26),Offset(9,11),Offset(40,4)]);
        dot(7,26);dot(9,11);dot(40,4);
      case DrawingCatalogKind.fibonacciChannel:
        poly(const [Offset(7,39),Offset(43,20)]);
        poly(const [Offset(7,28),Offset(43,9)]);
        poly(const [Offset(7,49),Offset(43,30)]);
        dot(7,28);dot(43,9);dot(7,39);
      case DrawingCatalogKind.fibonacciTimeZone:
        for (final x in [15.0,25.0,36.0,45.0]) line(x,6,x,46);
        poly(const [Offset(7,9),Offset(10,30),Offset(22,41)]);
        dot(10,30,3);dot(22,41,3);
      case DrawingCatalogKind.resistanceFan:
        spokes(5,from:6,to:45);
        line(6,43,6,5,thin);
        line(6,43,48,43,thin);
      case DrawingCatalogKind.fibonacciTime:
        for (final x in [17.0,27.0,38.0,47.0]) line(x,5,x,45);
        poly(const [Offset(6,7),Offset(15,34),Offset(26,41)]);
        dot(6,7,3);dot(15,34,3);dot(26,41,3);
      case DrawingCatalogKind.fibonacciCircles:
        for(final r in [10.0,17.0,23.0])
          canvas.drawCircle(const Offset(26,26),r,linePaint);
        dot(10,42,3);dot(42,9,3);
      case DrawingCatalogKind.fibonacciSpiral:
        final points=<Offset>[];
        for(var i=0;i<85;i++) {
          final a=i/84*5*math.pi;
          final r=2+i/84*21;
          points.add(Offset(26+r*math.cos(a),26+r*math.sin(a)));
        }
        poly(points);
        dot(35,20,3);
      case DrawingCatalogKind.resistanceArcs:
        for(final r in [13.0,20.0,28.0])
          arc(r,0.1,math.pi-0.2,const Offset(26,15));
        dot(26,15,3);dot(26,44,3);
      case DrawingCatalogKind.fibonacciWedge:
        line(6,45,47,45);line(6,45,6,4);
        for(final r in [15.0,25.0,36.0])
          arc(r,-math.pi/2,math.pi/2,const Offset(6,45));
        dot(6,45,3);dot(47,45,3);
      case DrawingCatalogKind.pitchfan:
        spokes(5,from:8,to:46);dot(15,17,3);
      case DrawingCatalogKind.gannBox:
        rectangle(6,6,40,40);
        for(var x=16.0;x<46;x+=10) line(x,6,x,46,thin);
        for(var y=16.0;y<46;y+=10) line(6,y,46,y,thin);
        dot(6,46,3);dot(46,6,3);
      case DrawingCatalogKind.fixedGannSquare:
        rectangle(7,7,38,38);
        for(var x=18.0;x<45;x+=12) line(x,7,x,45,thin);
        for(var y=18.0;y<45;y+=12) line(7,y,45,y,thin);
        line(7,45,45,7);line(7,7,45,45,thin);
        dot(7,45,3);
      case DrawingCatalogKind.gannSquare:
        rectangle(6,6,40,40);
        for(var x=16.0;x<46;x+=10) line(x,6,x,46,thin);
        for(var y=16.0;y<46;y+=10) line(6,y,46,y,thin);
        line(6,46,46,6);dot(6,46,3);dot(46,6,3);
      case DrawingCatalogKind.gannFan:
        spokes(6,from:7,to:46);dot(26,23,3);
      case DrawingCatalogKind.trendLine:
        line(5,44,46,7);dot(5,44);dot(46,7);
      case DrawingCatalogKind.ray:
        line(6,45,45,6);dot(6,45);dot(25,26,3);
      case DrawingCatalogKind.infoLine:
        line(8,43,42,7);dot(8,43,3.4);dot(42,7,3.4);
        canvas.drawRRect(RRect.fromRectAndRadius(
          const Rect.fromLTWH(25,33,17,12),const Radius.circular(3)),linePaint);
      case DrawingCatalogKind.extendedLine:
        line(4,46,48,2);dot(23,27,3);dot(33,17,3);
      case DrawingCatalogKind.trendAngle:
        line(7,45,45,45);line(7,45,44,6);
        line(7,45,33,34,thin);dot(7,45);dot(44,6);
      case DrawingCatalogKind.horizontal:
        line(5,26,47,26);dot(26,26,3);
      case DrawingCatalogKind.horizontalRay:
        line(7,26,48,26);dot(7,26,3);
      case DrawingCatalogKind.verticalLine:
        line(26,5,26,47);dot(26,26,3);
      case DrawingCatalogKind.crossLine:
        line(26,4,26,48);line(4,26,48,26);dot(26,26,3);
      case DrawingCatalogKind.parallelChannel:
        line(7,34,42,7);line(11,46,46,19);
        dot(7,34,3);dot(42,7,3);dot(30,32,3);
      case DrawingCatalogKind.regressionTrend:
        line(9,31,42,12);line(9,45,42,26);line(9,31,9,45);
        line(42,12,42,26);dot(9,38,3);dot(42,19,3);
      case DrawingCatalogKind.flatTopBottom:
        poly(const [Offset(8,19),Offset(43,6)]);
        line(8,43,43,43);dot(8,19,3);dot(43,6,3);
        dot(8,43,3);dot(43,43,3);
      case DrawingCatalogKind.disjointChannel:
        line(7,18,44,8);line(7,34,44,44);
        dot(7,18,3);dot(44,8,3);dot(7,34,3);dot(44,44,3);
      case DrawingCatalogKind.pitchfork:
        poly(const [Offset(8,13),Offset(26,32),Offset(45,14)]);
        poly(const [Offset(8,32),Offset(26,45),Offset(45,26)]);
        line(18,38,42,8);dot(8,13,3);dot(8,32,3);dot(26,45,3);
      case DrawingCatalogKind.schiffPitchfork:
        line(11,14,43,46);line(6,35,34,5);line(18,44,47,15);
        poly(const [Offset(6,35),Offset(31,45),Offset(47,29)]);
        dot(11,14,3);dot(6,35,3);dot(31,45,3);
      case DrawingCatalogKind.modifiedSchiffPitchfork:
        line(11,6,44,43);line(7,30,30,8);line(21,44,46,20);
        poly(const [Offset(7,30),Offset(26,45),Offset(46,28)]);
        dot(11,6,3);dot(7,30,3);dot(26,45,3);
      case DrawingCatalogKind.insidePitchfork:
        line(23,6,8,46);line(35,12,23,46);line(46,20,39,46);
        poly(const [Offset(8,46),Offset(23,28),Offset(39,46)]);
        dot(8,46,3);dot(23,28,3);dot(39,46,3);
      case DrawingCatalogKind.shortPosition:
        rectangle(10,9,31,13);rectangle(10,22,31,21);
        line(7,22,45,22);dot(10,22,3);
      case DrawingCatalogKind.priceRectangle:
        rectangle(7,8,38,34);
        for(final p in const [Offset(7,8),Offset(45,8),Offset(7,42),Offset(45,42)])
          dot(p.dx,p.dy,3);
      case DrawingCatalogKind.magnet:
        poly(const [Offset(8,8),Offset(8,30),Offset(15,40),Offset(36,40),
          Offset(44,30),Offset(44,8),Offset(33,8),Offset(33,27),
          Offset(29,30),Offset(23,30),Offset(19,27),Offset(19,8),Offset(8,8)]);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(DrawingToolGlyphPainter old) => old.tool != tool;
}
