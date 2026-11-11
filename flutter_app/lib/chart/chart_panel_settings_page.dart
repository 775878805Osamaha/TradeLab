import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tradelab_theme.dart';
import 'chart_panel_settings.dart';

/// A full-height page within the chart tab. Its header/footer are fixed while
/// only its form scrolls; TradeLabShell keeps the bottom navigation mounted.
/// All edits stay in [_draft] until the user explicitly presses «موافق».
class ChartPanelSettingsPage extends StatefulWidget {
  const ChartPanelSettingsPage({
    required this.initial,
    required this.onApply,
    required this.onCancel,
    super.key,
  });

  final ChartPanelSettings initial;
  final ValueChanged<ChartPanelSettings> onApply;
  final VoidCallback onCancel;

  @override
  State<ChartPanelSettingsPage> createState() => _ChartPanelSettingsPageState();
}

class _ChartPanelSettingsPageState extends State<ChartPanelSettingsPage> {
  late ChartPanelSettings _draft = widget.initial;
  late final _top = TextEditingController(text: '${_draft.topMarginPercent}');
  late final _bottom = TextEditingController(text: '${_draft.bottomMarginPercent}');
  late final _right = TextEditingController(text: '${_draft.rightMarginBars}');
  final _scroll = ScrollController();
  String? _validationError;

  @override
  void dispose() {
    _scroll.dispose();
    _top.dispose();
    _bottom.dispose();
    _right.dispose();
    super.dispose();
  }

  void _apply() {
    FocusScope.of(context).unfocus();
    final top = int.tryParse(_top.text);
    final bottom = int.tryParse(_bottom.text);
    final right = int.tryParse(_right.text);
    if (top == null || bottom == null || right == null ||
        !ChartPanelSettings.marginsValid(top, bottom, right)) {
      setState(() => _validationError =
        'تأكد من الهوامش: الأعلى والأسفل حتى 80% إجمالًا، واليمين من 0 إلى 100.');
      return;
    }
    widget.onApply(_draft.copyWith(
      topMarginPercent: top,
      bottomMarginPercent: bottom,
      rightMarginBars: right,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, layout) {
    // The reference is 691 physical pixels wide. Scale dimensions in its
    // coordinate space only after using the actual logical viewport width.
    final unit = layout.maxWidth / 691;
    final textSize = (26 * unit).clamp(14.0, 19.0);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onCancel();
      },
      child: ColoredBox(
        key: const Key('chart-panel-settings-page'),
        color: TradeColors.panelSurface,
        child: Column(children: [
          SizedBox(height: 70 * unit, child: Row(children: [
            IconButton(
              key: const Key('panel-back'),
              onPressed: widget.onCancel,
              icon: const Icon(Icons.chevron_right, color: TradeColors.panelInk),
              iconSize: (44 * unit).clamp(24, 30),
            ),
            SizedBox(width: 23 * unit),
            Text('لوحة', key: const Key('panel-title'),
              style: TextStyle(fontSize: (37 * unit).clamp(22, 27),
                color: TradeColors.panelInk, fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(
              key: const Key('panel-close'),
              onPressed: widget.onCancel,
              icon: const Icon(Icons.close, color: TradeColors.panelInk),
              iconSize: (41 * unit).clamp(23, 28),
            ),
            SizedBox(width: 23 * unit),
          ])),
          Expanded(child: Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            thickness: (5 * unit).clamp(2.5, 4.0),
            radius: const Radius.circular(4),
            child: SingleChildScrollView(
              key: const Key('panel-settings-scroll'),
              controller: _scroll,
              physics: const ClampingScrollPhysics(),
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  start: 37 * unit, end: 38 * unit),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  SizedBox(height: 87 * unit),
                  _sectionTitle('أنماط الرسم البياني الأساسية', unit),
                  SizedBox(height: 30 * unit),
                  _row('الخلفية', unit, textSize, _picker(
                    value: 'ثابت', unit: unit,
                    items: const ['ثابت'],
                    onSelect: (_) {},
                    key: const Key('panel-background-mode'),
                  )),
                  SizedBox(height: 16 * unit),
                  _row('', unit, textSize, _colorWell(
                    key: const Key('panel-background-color'),
                    color: Colors.white, onTap: null, unit: unit)),
                  SizedBox(height: 22 * unit),
                  _row('خطوط الشبكة الرأسية', unit, textSize, Row(
                    mainAxisSize: MainAxisSize.min, children: [
                      _colorWell(
                        key: const Key('panel-vertical-grid-color'),
                        color: Colors.transparent, onTap: null, unit: unit,
                        withLine: true),
                    ]), check: _draft.verticalGridVisible,
                    onCheck: (value) => setState(() => _draft =
                      _draft.copyWith(verticalGridVisible: value))),
                  SizedBox(height: 18 * unit),
                  _row('خطوط الشبكة الأفقية', unit, textSize, _colorWell(
                    key: const Key('panel-horizontal-grid-color'),
                    color: Colors.transparent, onTap: null, unit: unit,
                    withLine: true),
                    check: _draft.horizontalGridVisible,
                    onCheck: (value) => setState(() => _draft =
                      _draft.copyWith(horizontalGridVisible: value))),
                  SizedBox(height: 18 * unit),
                  _row('مؤشر التقاطع', unit, textSize, _colorWell(
                    key: const Key('panel-crosshair-sample'),
                    color: TradeColors.panelCheckerDark,
                    onTap: null, unit: unit, dashed: true)),
                  SizedBox(height: 20 * unit),
                  _row('علامة مائية', unit, textSize, _picker(
                    value: 'وضع إعادة التشغيل', unit: unit,
                    items: const ['وضع إعادة التشغيل'], onSelect: (_) {},
                    key: const Key('panel-watermark-mode'))),
                  SizedBox(height: 15 * unit),
                  _row('', unit, textSize, _colorWell(
                    key: const Key('panel-watermark-color'),
                    color: Colors.transparent, onTap: null, unit: unit)),
                  SizedBox(height: 70 * unit),
                  _sectionTitle('المقاييس', unit),
                  SizedBox(height: 25 * unit),
                  _row('النص', unit, textSize, Row(
                    mainAxisSize: MainAxisSize.min, children: [
                    _colorWell(key: const Key('panel-text-color'),
                      color: Color(_draft.axisTextColor), unit: unit,
                      onTap: () => setState(() => _draft = _draft.copyWith(
                        axisTextColor: _draft.axisTextColor == 0xFF000000
                          ? 0xFF555555 : 0xFF000000))),
                    SizedBox(width: 15 * unit),
                    _picker(value: '${_draft.axisTextSize}', unit: unit,
                      width: 190 * unit,
                      items: const ['10', '11', '12', '13', '14', '16', '18', '20', '24'],
                      onSelect: (value) => setState(() => _draft =
                          _draft.copyWith(axisTextSize: int.parse(value))),
                      key: const Key('panel-text-size')),
                  ])),
                  SizedBox(height: 19 * unit),
                  _row('الخطوط', unit, textSize, _colorWell(
                    key: const Key('panel-scale-lines'), unit: unit,
                    color: Color(_draft.scaleLineColor),
                    onTap: () => setState(() => _draft = _draft.copyWith(
                      scaleLineColor: _draft.scaleLineColor == 0x00000000
                          ? 0xFFAAAAAA : 0x00000000)))),
                  SizedBox(height: 54 * unit),
                  _sectionTitle('أزرار', unit),
                  SizedBox(height: 24 * unit),
                  _row('تنقل', unit, textSize, _visibilityPicker(
                    key: const Key('panel-navigation-visibility'),
                    unit: unit, selected: _draft.navigationButtons,
                    onChanged: (v) => setState(() => _draft =
                      _draft.copyWith(navigationButtons: v)))),
                  SizedBox(height: 32 * unit),
                  _row('جزء', unit, textSize, _visibilityPicker(
                    key: const Key('panel-pane-visibility'),
                    unit: unit, selected: _draft.paneButtons,
                    onChanged: (v) => setState(() => _draft =
                      _draft.copyWith(paneButtons: v)))),
                  SizedBox(height: 64 * unit),
                  _sectionTitle('هوامش', unit),
                  SizedBox(height: 4 * unit),
                  _row('الأعلى', unit, textSize, _marginPercentField(
                    controller: _top, unit: unit,
                    key: const Key('panel-margin-top'))),
                  SizedBox(height: 18 * unit),
                  _row('الأسفل', unit, textSize, _marginPercentField(
                    controller: _bottom, unit: unit,
                    key: const Key('panel-margin-bottom'))),
                  SizedBox(height: 31 * unit),
                  _row('يمين', unit, textSize, Row(mainAxisSize: MainAxisSize.min,
                    children: [
                    _numberField(controller: _right, unit: unit,
                      key: const Key('panel-margin-right')),
                    SizedBox(width: 12 * unit),
                    SizedBox(width: 82 * unit,
                      child: Text('الأعمدة\nالبيانية',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: (24 * unit).clamp(14.0, 18.0),
                          color: TradeColors.panelInk))),
                  ])),
                  if (_validationError != null)
                    Padding(padding: const EdgeInsets.only(top: 10),
                      child: Text(_validationError!, textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12,
                          color: TradeColors.negative))),
                  SizedBox(height: 65 * unit),
                ]),
              ),
            ),
          )),
          Container(
            key: const Key('panel-fixed-footer'),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: TradeColors.panelBorder,
                width: .5))),
            padding: EdgeInsets.symmetric(
              horizontal: 38 * unit, vertical: 34 * unit),
            child: Row(children: [
              _footerButton('•••', unit: unit, referenceWidth: 110,
                key: const Key('panel-more'),
                outline: TradeColors.panelBorder,
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (context) => SafeArea(child: ListTile(
                    title: const Text('إعدادات اللوحة'),
                    subtitle: const Text('لا توجد إجراءات إضافية محددة.'),
                    trailing: const Icon(Icons.more_horiz),
                    onTap: () => Navigator.pop(context),
                  )),
                )),
              const Spacer(),
              _footerButton('إلغاء', unit: unit, referenceWidth: 94,
                key: const Key('panel-cancel'),
                outline: TradeColors.panelInk, onTap: widget.onCancel),
              SizedBox(width: 23 * unit),
              _footerButton('موافق', unit: unit, referenceWidth: 115,
                key: const Key('panel-apply'), filled: true, onTap: _apply),
            ]),
          ),
        ]),
      ),
    );
    });
  }

  Widget _sectionTitle(String title, double unit) => Text(title,
    textAlign: TextAlign.right,
    style: TextStyle(color: TradeColors.panelMuted,
      fontSize: (22 * unit).clamp(12.5, 16.0)));

  Widget _row(String label, double unit, double textSize, Widget control, {
    bool? check, ValueChanged<bool>? onCheck,
  }) => SizedBox(height: (67 * unit).clamp(44.0, 55.0),
    child: Row(children: [
      if (check != null) ...[
        GestureDetector(
          key: Key('panel-grid-${label == 'خطوط الشبكة الرأسية' ? 'vertical' : 'horizontal'}'),
          onTap: () => onCheck?.call(!check),
          child: Container(width: 33 * unit, height: 33 * unit,
            decoration: BoxDecoration(border: Border.all(
              color: TradeColors.panelInk, width: 1.1),
              borderRadius: BorderRadius.circular(5 * unit)),
            child: check ? const Icon(Icons.check, size: 18) : null),
        ),
        SizedBox(width: 12 * unit),
      ],
      Expanded(child: Text(label, maxLines: 2,
        textAlign: TextAlign.right,
        style: TextStyle(fontSize: textSize,
          color: TradeColors.panelInk))),
      SizedBox(width: 12 * unit),
      // A long RTL label and its control must coexist on narrow phones and
      // large accessibility text scales without horizontal overflow.
      Flexible(fit: FlexFit.loose, child: FittedBox(
        alignment: Alignment.centerLeft,
        fit: BoxFit.scaleDown,
        child: control,
      )),
    ]));

  Widget _visibilityPicker({required Key key, required double unit,
    required ChartButtonVisibility selected,
    required ValueChanged<ChartButtonVisibility> onChanged}) =>
    _picker(key: key, value: selected.label, unit: unit,
      items: ChartButtonVisibility.values.map((e) => e.label).toList(),
      onSelect: (value) => onChanged(ChartButtonVisibility.values
        .firstWhere((e) => e.label == value)));

  Widget _picker({required String value, required double unit,
    required List<String> items, required ValueChanged<String> onSelect,
    required Key key, double? width}) => PopupMenuButton<String>(
      key: key,
      initialValue: value,
      onSelected: onSelect,
      enabled: items.length > 1,
      itemBuilder: (context) => [
        for (final item in items)
          PopupMenuItem<String>(value: item, child: Text(item,
            textDirection: TextDirection.rtl)),
      ],
      child: Container(
        width: width ?? (286 * unit).clamp(143.0, 230.0),
        height: (63 * unit).clamp(38.0, 49.0),
        padding: EdgeInsets.symmetric(horizontal: 14 * unit),
        decoration: BoxDecoration(color: TradeColors.panelSurface,
          border: Border.all(color: TradeColors.panelBorder),
          borderRadius: BorderRadius.circular(13 * unit)),
        child: Row(children: [
          Expanded(child: Text(value,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: TradeColors.panelInk,
              fontSize: (27 * unit).clamp(14.0, 18.0)))),
          const Icon(Icons.keyboard_arrow_down,
            color: TradeColors.panelMuted, size: 23),
        ]),
      ),
    );

  Widget _marginPercentField({required TextEditingController controller,
    required double unit, required Key key}) =>
    Row(mainAxisSize: MainAxisSize.min, children: [
      _numberField(controller: controller, unit: unit, key: key),
      SizedBox(width: 17 * unit),
      Text('%', textDirection: TextDirection.ltr,
        style: TextStyle(color: TradeColors.panelInk,
          fontSize: (25 * unit).clamp(14.0, 19.0))),
    ]);

  Widget _numberField({required TextEditingController controller,
    required double unit, required Key key}) =>
    SizedBox(width: (190 * unit).clamp(110.0, 150.0),
      height: (63 * unit).clamp(38.0, 49.0),
      child: TextField(
        key: key,
        controller: controller,
        onChanged: (_) { if (_validationError != null) {
          setState(() => _validationError = null);
        } },
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.right,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(3)],
        style: const TextStyle(color: TradeColors.panelInk, fontSize: 17),
        decoration: InputDecoration(
          filled: true, fillColor: TradeColors.panelSurface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: TradeColors.panelBorder)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: TradeColors.panelBorder)),
        ),
      ),
    );

  Widget _colorWell({required Key key, required double unit,
    required Color color, required VoidCallback? onTap,
    bool withLine = false, bool dashed = false}) => GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        width: (64 * unit).clamp(36.0, 46.0),
        height: (64 * unit).clamp(36.0, 46.0),
        padding: EdgeInsets.all(7 * unit),
        decoration: BoxDecoration(color: TradeColors.panelSurface,
          border: Border.all(color: TradeColors.panelBorder),
          borderRadius: BorderRadius.circular(10 * unit)),
        child: ClipRRect(borderRadius: BorderRadius.circular(5 * unit),
          child: CustomPaint(painter: _CheckerPainter(
            color: color, dashed: dashed, withLine: withLine))),
      ),
    );

  Widget _footerButton(String label, {required Key key,
    required double unit, required VoidCallback onTap,
    double referenceWidth = 110,
    Color? outline, bool filled = false}) => Semantics(
      button: true, label: label,
      child: GestureDetector(key: key,
        behavior: HitTestBehavior.opaque, onTap: onTap,
        child: Container(
          width: referenceWidth * unit,
          padding: EdgeInsets.symmetric(horizontal: 8 * unit),
          height: (64 * unit).clamp(38.0, 48.0),
          decoration: BoxDecoration(
            color: filled ? TradeColors.panelAccept : TradeColors.panelSurface,
            border: Border.all(color: outline ?? TradeColors.panelAccept),
            borderRadius: BorderRadius.circular(13 * unit)),
          alignment: Alignment.center,
          child: FittedBox(fit: BoxFit.scaleDown, child:
            Text(label, style: TextStyle(
              color: filled ? Colors.white : TradeColors.panelInk,
              fontSize: (26 * unit).clamp(15.0, 19.0)))),
        )),
    );
}

class _CheckerPainter extends CustomPainter {
  const _CheckerPainter({required this.color,
    this.withLine = false, this.dashed = false});
  final Color color;
  final bool withLine;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size,
      Paint()..color = TradeColors.panelCheckerLight);
    final step = size.width / 4;
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 4; col++) {
        if ((row + col).isEven) {
          canvas.drawRect(Rect.fromLTWH(col * step, row * step,
            step, step), Paint()..color = TradeColors.panelCheckerDark);
        }
      }
    }
    if (color.a > 0) canvas.drawRect(Offset.zero & size, Paint()..color = color);
    if (withLine || dashed) {
      final pen = Paint()
        ..color = (dashed ? TradeColors.panelSurface : TradeColors.panelMuted)
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += dashed ? 8 : size.width) {
        canvas.drawLine(Offset(x, size.height / 2),
          Offset(dashed ? (x + 4).clamp(0, size.width) : size.width,
            size.height / 2), pen);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerPainter old) =>
    old.color != color || old.dashed != dashed || old.withLine != withLine;
}
