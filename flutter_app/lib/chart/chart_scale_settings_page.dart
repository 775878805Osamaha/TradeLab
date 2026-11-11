import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tradelab_theme.dart';
import 'chart_scale_settings.dart';

/// The price/time scale tab as a native Flutter form. Only the middle content
/// scrolls; edits are isolated until «موافق» commits the immutable draft.
class ChartScaleSettingsPage extends StatefulWidget {
  const ChartScaleSettingsPage({
    required this.initial,
    required this.onApply,
    required this.onCancel,
    super.key,
  });

  final ChartScaleSettings initial;
  final ValueChanged<ChartScaleSettings> onApply;
  final VoidCallback onCancel;

  @override
  State<ChartScaleSettingsPage> createState() => _ChartScaleSettingsPageState();
}

class _ChartScaleSettingsPageState extends State<ChartScaleSettingsPage> {
  late ChartScaleSettings _draft = widget.initial;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _chooseColor(int current, ValueChanged<int> onColor) async {
    const colors = <int>[
      0xFF22A68F, 0xFFF24B60, 0xFF84CDC4, 0xFFF1A1AC,
      0xFFF49EA8, 0xFF88A3F8, 0xFFAAAAAA,
      0xFF222222, 0xFFFFFFFF,
    ];
    final chosen = await showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('لون الملصق أو الخط', textDirection: TextDirection.rtl,
            style: TextStyle(fontSize: 18)),
          const SizedBox(height: 18),
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final value in colors)
              GestureDetector(
                onTap: () => Navigator.pop(sheetContext, value),
                child: Semantics(label: 'لون ${value.toRadixString(16)}',
                  selected: current == value, button: true,
                  child: Container(width: 46, height: 46,
                    decoration: BoxDecoration(color: Color(value),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: current == value
                          ? TradeColors.panelInk : TradeColors.panelBorder,
                        width: current == value ? 2 : 1))),
              )),
          ]),
          const SizedBox(height: 8),
        ]),
      )),
    );
    if (chosen != null && mounted) setState(() => onColor(chosen));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, layout) {
    final u = layout.maxWidth / 691;
    final labelSize = (26 * u).clamp(13.5, 19.0);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onCancel();
      },
      child: ColoredBox(color: TradeColors.panelSurface,
        key: const Key('chart-scale-settings-page'),
        child: Column(children: [
          SizedBox(height: 70 * u, child: Row(children: [
            IconButton(key: const Key('scale-back'),
              onPressed: widget.onCancel,
              icon: const Icon(Icons.chevron_right, color: TradeColors.panelInk),
              iconSize: (44 * u).clamp(24.0, 30.0)),
            SizedBox(width: 23 * u),
            Text('المقاييس والخطوط', key: const Key('scale-title'),
              style: TextStyle(color: TradeColors.panelInk,
                fontWeight: FontWeight.w700,
                fontSize: (35 * u).clamp(20.0, 27.0))),
            const Spacer(),
            IconButton(key: const Key('scale-close'),
              onPressed: widget.onCancel,
              icon: const Icon(Icons.close, color: TradeColors.panelInk),
              iconSize: (41 * u).clamp(23.0, 29.0)),
            SizedBox(width: 23 * u),
          ])),
          Expanded(child: Scrollbar(
            controller: _scroll, thumbVisibility: true,
            thickness: (5 * u).clamp(2.5, 4.0),
            radius: const Radius.circular(4),
            child: SingleChildScrollView(
              key: const Key('scale-settings-scroll'),
              controller: _scroll,
              physics: const ClampingScrollPhysics(),
              child: Padding(
                padding: EdgeInsetsDirectional.only(start: 37 * u, end: 38 * u),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 69 * u),
                    _title('مقياس الأسعار', u),
                    SizedBox(height: 28 * u),
                    _row('العملة والوحدة', _dropdown(
                      key: const Key('scale-currency-unit'),
                      u: u, value: _draft.currencyUnit.label,
                      options: ChartScaleVisibility.values.map((e) => e.label).toList(),
                      onSelected: (v) => setState(() => _draft = _draft.copyWith(
                        currencyUnit: ChartScaleVisibility.values.firstWhere((e) => e.label == v)))), u, labelSize),
                    SizedBox(height: 32 * u),
                    _row('أوضاع المقياس (A و L)', _dropdown(
                      key: const Key('scale-buttons'),
                      u: u, value: _draft.scaleButtons.label,
                      options: ChartScaleVisibility.values.map((e) => e.label).toList(),
                      onSelected: (v) => setState(() => _draft = _draft.copyWith(
                        scaleButtons: ChartScaleVisibility.values.firstWhere((e) => e.label == v)))), u, labelSize),
                    SizedBox(height: 32 * u),
                    _row('قفل نسبة السعر للعمود البياني', _disabledNumber(u),
                      u, labelSize, check: _draft.lockPriceToBar,
                      onCheck: (v) => setState(() => _draft = _draft.copyWith(lockPriceToBar: v))),
                    SizedBox(height: 56 * u),
                    _row('وضع المقاييس', _dropdown(
                      key: const Key('scale-mode'), u: u,
                      value: _draft.scaleMode,
                      options: const ['تلقائي'], onSelected: (_) {}), u, labelSize),
                    SizedBox(height: 64 * u),
                    _title('ملصقات وخطوط الأسعار', u),
                    SizedBox(height: 31 * u),
                    _checkRow('بدون ملصقات متداخلة',
                      _draft.avoidOverlappingLabels,
                      (v) => setState(() => _draft = _draft.copyWith(
                        avoidOverlappingLabels: v)), u, labelSize),
                    SizedBox(height: 31 * u),
                    _checkRow('زر زائد', _draft.plusButton,
                      (v) => setState(() => _draft = _draft.copyWith(plusButton: v)),
                      u, labelSize, help: true),
                    SizedBox(height: 31 * u),
                    _checkRow('العد التنازلي لإغلاق العمود البياني',
                      _draft.countdown,
                      (v) => setState(() => _draft = _draft.copyWith(countdown: v)),
                      u, labelSize),
                    SizedBox(height: 30 * u),
                    _row('رمز', _labelMode(
                      key: const Key('scale-symbol-label'),
                      u: u, value: _draft.symbolLabel,
                      onChanged: (v) => setState(() => _draft = _draft.copyWith(
                        symbolLabel: v))), u, labelSize),
                    SizedBox(height: 14 * u),
                    _controlOnly(_lineWell(u, color: _draft.symbolLabelColor,
                      secondColor: _draft.symbolNegativeColor,
                      enabled: _draft.symbolLabel != ChartPriceLabelMode.hidden,
                      key: const Key('scale-symbol-colors'),
                      onTap: () => _chooseColor(_draft.symbolLabelColor,
                        (v) => _draft = _draft.copyWith(symbolLabelColor: v))), u),
                    SizedBox(height: 24 * u),
                    _controlOnly(_dropdown(
                      key: const Key('scale-label-placement'), u: u,
                      value: _draft.symbolLabelPlacement,
                      options: const ['القيمة حسب المقياس'],
                      onSelected: (_) {}), u),
                    SizedBox(height: 30 * u),
                    _row('إغلاق اليوم السابق', _labelMode(
                      key: const Key('scale-previous-close'),
                      u: u, value: _draft.previousClose,
                      onChanged: (v) => setState(() => _draft = _draft.copyWith(
                        previousClose: v))), u, labelSize),
                    SizedBox(height: 15 * u),
                    _controlOnly(_lineWell(u, color: _draft.previousCloseColor,
                      enabled: _draft.previousClose != ChartPriceLabelMode.hidden,
                      key: const Key('scale-previous-close-color'),
                      onTap: () => _chooseColor(_draft.previousCloseColor,
                        (v) => _draft = _draft.copyWith(previousCloseColor: v))), u),
                    SizedBox(height: 31 * u),
                    _row('المؤشرات والبيانات المالية', _labelMode(
                      key: const Key('scale-indicators'),
                      u: u, value: _draft.indicatorLabels,
                      onChanged: (v) => setState(() => _draft = _draft.copyWith(
                        indicatorLabels: v))), u, labelSize),
                    SizedBox(height: 31 * u),
                    _row('أعلى وأدنى', _labelMode(
                      key: const Key('scale-high-low'),
                      u: u, value: _draft.highLow,
                      onChanged: (v) => setState(() => _draft = _draft.copyWith(
                        highLow: v))), u, labelSize),
                    SizedBox(height: 15 * u),
                    _controlOnly(_lineWell(u, color: _draft.highColor,
                      secondColor: _draft.lowColor,
                      enabled: _draft.highLow != ChartPriceLabelMode.hidden,
                      key: const Key('scale-high-low-colors'),
                      onTap: () => _chooseColor(_draft.highColor,
                        (v) => _draft = _draft.copyWith(highColor: v))), u),
                    SizedBox(height: 31 * u),
                    _row('سعر البيع والشراء', _labelMode(
                      key: const Key('scale-bid-ask'),
                      u: u, value: _draft.bidAsk,
                      onChanged: (v) => setState(() => _draft = _draft.copyWith(
                        bidAsk: v))), u, labelSize),
                    SizedBox(height: 15 * u),
                    _controlOnly(Row(mainAxisSize: MainAxisSize.min, children: [
                      _colorWell(u, color: _draft.bidColor,
                        enabled: _draft.bidAsk != ChartPriceLabelMode.hidden,
                        key: const Key('scale-bid-color'),
                        onTap: () => _chooseColor(_draft.bidColor,
                          (v) => _draft = _draft.copyWith(bidColor: v))),
                      SizedBox(width: 16 * u),
                      _colorWell(u, color: _draft.askColor,
                        enabled: _draft.bidAsk != ChartPriceLabelMode.hidden,
                        key: const Key('scale-ask-color'),
                        onTap: () => _chooseColor(_draft.askColor,
                          (v) => _draft = _draft.copyWith(askColor: v))),
                    ]), u),
                    SizedBox(height: 62 * u),
                    _title('مقياس الوقت', u),
                    SizedBox(height: 55 * u),
                    _checkRow('يوم الأسبوع على الملصقات',
                      _draft.weekdayOnLabels,
                      (v) => setState(() => _draft = _draft.copyWith(
                        weekdayOnLabels: v)), u, labelSize,
                      key: const Key('scale-weekday')),
                    SizedBox(height: 112 * u),
                  ],
                ),
              ),
            ),
          )),
          Container(key: const Key('scale-fixed-footer'),
            decoration: const BoxDecoration(border: Border(top:
              BorderSide(color: TradeColors.panelBorder, width: .5))),
            padding: EdgeInsets.symmetric(horizontal: 38 * u,
              vertical: 34 * u),
            child: Row(children: [
              _footer('•••', u: u, width: 110,
                key: const Key('scale-more'),
                outline: TradeColors.panelBorder,
                onTap: () => showModalBottomSheet<void>(context: context,
                  builder: (sheetContext) => SafeArea(child: ListTile(
                    title: const Text('المقاييس والخطوط'),
                    subtitle: const Text('إعدادات الملصقات ومحوري السعر والوقت.'),
                    onTap: () => Navigator.pop(sheetContext))))),
              const Spacer(),
              _footer('إلغاء', u: u, width: 94,
                key: const Key('scale-cancel'),
                outline: TradeColors.panelInk, onTap: widget.onCancel),
              SizedBox(width: 23 * u),
              _footer('موافق', u: u, width: 115,
                key: const Key('scale-apply'), filled: true,
                onTap: () => widget.onApply(_draft)),
            ]),
          ),
        ]),
      ),
    );
  });

  Widget _title(String text, double u) => Text(text,
    textAlign: TextAlign.right,
    style: TextStyle(fontSize: (22 * u).clamp(12.5, 16.0),
      color: TradeColors.panelMuted));

  Widget _check(bool checked, double u) => Container(
    width: 33 * u, height: 33 * u,
    decoration: BoxDecoration(
      color: checked ? TradeColors.panelAccept : Colors.white,
      border: Border.all(color: TradeColors.panelAccept, width: 1.3),
      borderRadius: BorderRadius.circular(5 * u)),
    child: checked ? Icon(Icons.check, color: Colors.white,
      size: math.max(14, 26 * u)) : null);

  Widget _checkRow(String label, bool checked, ValueChanged<bool> onChange,
    double u, double font, {Key? key, bool help = false}) =>
      GestureDetector(key: key, behavior: HitTestBehavior.opaque,
        onTap: () => onChange(!checked),
        child: Semantics(label: label, checked: checked,
          child: SizedBox(height: 64 * u, child: Row(children: [
            _check(checked, u),
            SizedBox(width: 12 * u),
            Expanded(child: Text(label, textAlign: TextAlign.right,
              maxLines: 2, style: TextStyle(fontSize: font,
                color: TradeColors.panelInk))),
            if (help) Icon(Icons.help, color: TradeColors.panelMuted,
              size: 26 * u),
          ]))),
      );

  Widget _row(String label, Widget control, double u, double font,
    {bool? check, ValueChanged<bool>? onCheck}) => SizedBox(
      height: 64 * u,
      child: Row(children: [
        if (check != null) ...[
          GestureDetector(key: const Key('scale-lock'),
            onTap: () => onCheck?.call(!check),
            child: _check(check, u)),
          SizedBox(width: 12 * u),
        ],
        Expanded(child: Text(label, textAlign: TextAlign.right,
          maxLines: 2, style: TextStyle(fontSize: font,
            color: TradeColors.panelInk))),
        SizedBox(width: 14 * u),
        Flexible(fit: FlexFit.loose, child: FittedBox(
          fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
          child: control)),
      ]));

  Widget _controlOnly(Widget control, double u) => Row(children: [
    const Spacer(),
    control,
  ]);

  Widget _disabledNumber(double u) => Container(
    width: 286 * u, height: 63 * u,
    alignment: Alignment.centerRight,
    padding: EdgeInsets.symmetric(horizontal: 14 * u),
    decoration: BoxDecoration(color: const Color(0xFFF1F1F1),
      border: Border.all(color: TradeColors.panelBorder),
      borderRadius: BorderRadius.circular(12 * u)),
    // No fictitious price-to-bar ratio before a verified viewport is known.
    child: Text('—', textDirection: TextDirection.ltr,
      style: TextStyle(color: Colors.grey, fontSize: (27 * u).clamp(14, 18))));

  Widget _labelMode({required Key key, required double u,
    required ChartPriceLabelMode value,
    required ValueChanged<ChartPriceLabelMode> onChanged}) =>
      _dropdown(key: key, u: u, value: value.label,
        options: ChartPriceLabelMode.values.map((e) => e.label).toList(),
        onSelected: (label) => onChanged(ChartPriceLabelMode.values
          .firstWhere((e) => e.label == label)));

  Widget _dropdown({required Key key, required double u,
    required String value, required List<String> options,
    required ValueChanged<String> onSelected}) => PopupMenuButton<String>(
      key: key, enabled: options.length > 1,
      initialValue: value, onSelected: onSelected,
      itemBuilder: (_) => [for (final option in options)
        PopupMenuItem(value: option, child: Text(option,
          textDirection: TextDirection.rtl))],
      child: Container(width: 286 * u,
        height: 63 * u,
        decoration: BoxDecoration(color: Colors.white,
          border: Border.all(color: TradeColors.panelBorder),
          borderRadius: BorderRadius.circular(13 * u)),
        padding: EdgeInsets.symmetric(horizontal: 14 * u),
        child: Row(children: [
          Expanded(child: Text(value, textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis, maxLines: 1,
            style: TextStyle(color: TradeColors.panelInk,
              fontSize: (27 * u).clamp(14.0, 18.0)))),
          const Icon(Icons.keyboard_arrow_down,
            color: TradeColors.panelMuted, size: 23),
        ])));

  Widget _lineWell(double u, {required Key key, required int color,
    int? secondColor, required bool enabled, required VoidCallback onTap}) =>
      GestureDetector(key: key, onTap: enabled ? onTap : null,
        child: Container(width: 144 * u, height: 64 * u,
          decoration: BoxDecoration(
            color: enabled ? Colors.white : const Color(0xFFF2F2F2),
            border: Border.all(color: TradeColors.panelBorder),
            borderRadius: BorderRadius.circular(10 * u)),
          padding: EdgeInsets.all(6 * u),
          child: CustomPaint(painter: _ScaleLinePreview(
            lineColor: Color(color), secondColor: secondColor == null
              ? null : Color(secondColor), disabled: !enabled))));

  Widget _colorWell(double u, {required Key key, required int color,
    required bool enabled, required VoidCallback onTap}) =>
      GestureDetector(key: key, onTap: enabled ? onTap : null,
        child: Container(width: 64 * u, height: 64 * u,
          padding: EdgeInsets.all(7 * u),
          decoration: BoxDecoration(color: enabled ? Colors.white
            : const Color(0xFFF2F2F2),
            border: Border.all(color: TradeColors.panelBorder),
            borderRadius: BorderRadius.circular(10 * u)),
          child: DecoratedBox(decoration: BoxDecoration(
            color: Color(color), borderRadius: BorderRadius.circular(5 * u)))));

  Widget _footer(String text, {required Key key, required double u,
    required double width, required VoidCallback onTap,
    Color? outline, bool filled = false}) => Semantics(button: true,
      label: text,
      child: GestureDetector(key: key,
        behavior: HitTestBehavior.opaque, onTap: onTap,
        child: Container(width: width * u,
          height: (64 * u).clamp(38.0, 48.0),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? TradeColors.panelAccept : Colors.white,
            border: Border.all(color: outline ?? TradeColors.panelAccept),
            borderRadius: BorderRadius.circular(13 * u)),
          child: Text(text, style: TextStyle(
            fontSize: (26 * u).clamp(15.0, 19.0),
            color: filled ? Colors.white : TradeColors.panelInk)))));
}

class _ScaleLinePreview extends CustomPainter {
  const _ScaleLinePreview({required this.lineColor,
    required this.disabled, this.secondColor});
  final Color lineColor;
  final Color? secondColor;
  final bool disabled;

  @override
  void paint(Canvas canvas, Size size) {
    final sampleWidth = size.height * .91;
    final lineY = size.height / 2;
    final linePaint = Paint()
      ..color = (disabled ? const Color(0xFFAAAAAA)
        : const Color(0xFF222222))
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(5, lineY),
      Offset(size.width - sampleWidth - 16, lineY), linePaint);
    final sample = Rect.fromLTWH(size.width - sampleWidth - 2, 1,
      sampleWidth, size.height - 2);
    final first = disabled ? lineColor.withValues(alpha: .78) : lineColor;
    canvas.drawRRect(RRect.fromRectAndRadius(sample, const Radius.circular(5)),
      Paint()..color = first);
    if (secondColor != null) {
      final triangle = Path()..moveTo(sample.right, sample.top)
        ..lineTo(sample.right, sample.bottom)
        ..lineTo(sample.left, sample.bottom)..close();
      canvas.drawPath(triangle,
        Paint()..color = disabled ? secondColor!.withValues(alpha: .72)
          : secondColor!);
    }
  }

  @override
  bool shouldRepaint(covariant _ScaleLinePreview old) =>
      old.lineColor != lineColor || old.secondColor != secondColor ||
      old.disabled != disabled;
}
