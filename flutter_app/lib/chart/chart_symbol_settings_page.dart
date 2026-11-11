import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tradelab_theme.dart';
import 'chart_symbol_settings.dart';

/// PROMPT 14: reference-matched symbol editor with a fixed TradeLab footer.
/// Changes remain drafts until confirmation; returning without confirming
/// leaves chart paint, viewport, history cache and Replay untouched.
class ChartSymbolSettingsPage extends StatefulWidget {
  const ChartSymbolSettingsPage({
    required this.initial,
    required this.onApply,
    required this.onCancel,
    super.key,
  });

  final ChartSymbolSettings initial;
  final ValueChanged<ChartSymbolSettings> onApply;
  final VoidCallback onCancel;

  @override
  State<ChartSymbolSettingsPage> createState() => _ChartSymbolSettingsPageState();
}

class _ChartSymbolSettingsPageState extends State<ChartSymbolSettingsPage> {
  late ChartSymbolSettings _draft = widget.initial;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _chooseColor(int original, ValueChanged<int> onChosen) async {
    const palette = <int>[
      0xFFF23645, 0xFF089981, 0xFF22A68F, 0xFFF24B60,
      0xFF111111, 0xFFFFFFFF, 0xFFF49EA8, 0xFF88A3F8,
      0xFFEF9A2D, 0xFF2962FF, 0xFF868686, 0xFF673AB7,
    ];
    final hex = TextEditingController(
      text: original.toRadixString(16).substring(2).toUpperCase());
    int? value;
    try {
      value = await showModalBottomSheet<int>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(child: Padding(
          padding: EdgeInsets.only(left: 24, right: 24, top: 24,
            bottom: math.max(24, MediaQuery.viewInsetsOf(sheetContext).bottom)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('اختيار لون الشمعة', textDirection: TextDirection.rtl,
              style: TextStyle(fontSize: 18)),
            const SizedBox(height: 20),
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (final color in palette)
                GestureDetector(
                  key: Key('symbol-palette-${color.toRadixString(16)}'),
                  onTap: () => Navigator.pop(sheetContext, color),
                  child: Semantics(button: true,
                    label: 'اللون ${color.toRadixString(16)}',
                    selected: color == original,
                    child: Container(width: 44, height: 44,
                      decoration: BoxDecoration(color: Color(color),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: color == original
                          ? TradeColors.panelInk : TradeColors.panelBorder,
                          width: color == original ? 2 : 1))))),
            ]),
            const SizedBox(height: 22),
            TextField(controller: hex, textDirection: TextDirection.ltr,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'HEX', prefixText: '#', border: OutlineInputBorder()),
              keyboardType: TextInputType.text),
            TextButton(onPressed: () {
              final rgb = int.tryParse(hex.text.trim().replaceAll('#', ''),
                radix: 16);
              if (hex.text.trim().replaceAll('#', '').length == 6 &&
                  rgb != null) {
                Navigator.pop(sheetContext, 0xFF000000 | rgb);
              }
            }, child: const Text('تطبيق اللون')),
          ]),
        )),
      );
    } finally {
      hex.dispose();
    }
    if (value != null && mounted) setState(() => onChosen(value!));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, layout) {
    final u = layout.maxWidth / 691;
    final labelSize = (26 * u).clamp(13.5, 19.0);
    return PopScope(canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onCancel();
      },
      child: ColoredBox(key: const Key('chart-symbol-settings-page'),
        color: TradeColors.panelSurface,
        child: Column(children: [
          SizedBox(height: 70 * u, child: Row(children: [
            IconButton(key: const Key('symbol-back'),
              onPressed: widget.onCancel,
              icon: const Icon(Icons.chevron_right, color: TradeColors.panelInk),
              iconSize: (44 * u).clamp(24.0, 30.0)),
            SizedBox(width: 23 * u),
            Expanded(child: Text('رمز', key: const Key('symbol-title'),
              textAlign: TextAlign.right,
              style: TextStyle(color: TradeColors.panelInk,
                fontWeight: FontWeight.w700,
                fontSize: (35 * u).clamp(20.0, 27.0)))),
            IconButton(key: const Key('symbol-close'),
              onPressed: widget.onCancel,
              icon: const Icon(Icons.close, color: TradeColors.panelInk),
              iconSize: (41 * u).clamp(23.0, 29.0)),
            SizedBox(width: 23 * u),
          ])),
          Expanded(child: Scrollbar(controller: _scroll,
            thumbVisibility: true, thickness: (5 * u).clamp(2.5, 4.0),
            radius: const Radius.circular(4),
            child: SingleChildScrollView(
              key: const Key('symbol-settings-scroll'), controller: _scroll,
              physics: const ClampingScrollPhysics(),
              child: Padding(
                padding: EdgeInsetsDirectional.only(start: 38 * u, end: 38 * u),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 80 * u),
                    _section('شموع', u),
                    SizedBox(height: 48 * u),
                    _checkedRow('تلوين الأعمدة طبقًا للإغلاق السابق',
                      _draft.colorByPreviousClose, u, labelSize,
                      key: const Key('symbol-prev-close-toggle'),
                      onChanged: (v) => setState(() => _draft =
                        _draft.copyWith(colorByPreviousClose: v))),
                    SizedBox(height: 54 * u),
                    _colorRow('الجزء الرئيسي', _draft.bodyVisible,
                      bear: _draft.bodyBear, bull: _draft.bodyBull,
                      u: u, font: labelSize,
                      toggleKey: const Key('symbol-body-toggle'),
                      bearKey: const Key('symbol-body-bear'),
                      bullKey: const Key('symbol-body-bull'),
                      onCheck: (v) => setState(() =>
                        _draft = _draft.copyWith(bodyVisible: v)),
                      onBear: () => _chooseColor(_draft.bodyBear,
                        (v) => _draft = _draft.copyWith(bodyBear: v)),
                      onBull: () => _chooseColor(_draft.bodyBull,
                        (v) => _draft = _draft.copyWith(bodyBull: v))),
                    SizedBox(height: 32 * u),
                    _colorRow('إطارات', _draft.borderVisible,
                      bear: _draft.borderBear, bull: _draft.borderBull,
                      u: u, font: labelSize,
                      toggleKey: const Key('symbol-border-toggle'),
                      bearKey: const Key('symbol-border-bear'),
                      bullKey: const Key('symbol-border-bull'),
                      onCheck: (v) => setState(() =>
                        _draft = _draft.copyWith(borderVisible: v)),
                      onBear: () => _chooseColor(_draft.borderBear,
                        (v) => _draft = _draft.copyWith(borderBear: v)),
                      onBull: () => _chooseColor(_draft.borderBull,
                        (v) => _draft = _draft.copyWith(borderBull: v))),
                    SizedBox(height: 32 * u),
                    _colorRow('ظل الشمعة', _draft.wickVisible,
                      bear: _draft.wickBear, bull: _draft.wickBull,
                      u: u, font: labelSize,
                      toggleKey: const Key('symbol-wick-toggle'),
                      bearKey: const Key('symbol-wick-bear'),
                      bullKey: const Key('symbol-wick-bull'),
                      onCheck: (v) => setState(() =>
                        _draft = _draft.copyWith(wickVisible: v)),
                      onBear: () => _chooseColor(_draft.wickBear,
                        (v) => _draft = _draft.copyWith(wickBear: v)),
                      onBull: () => _chooseColor(_draft.wickBull,
                        (v) => _draft = _draft.copyWith(wickBull: v))),
                    SizedBox(height: 65 * u),
                    _section('تعديل البيانات', u),
                    SizedBox(height: 36 * u),
                    _settingRow('الدقة', _dropdown(u: u,
                      key: const Key('symbol-precision'),
                      value: _draft.precisionDigits?.toString() ?? 'افتراضي',
                      items: const ['افتراضي', '0', '1', '2', '3', '4', '5', '6', '7', '8'],
                      onSelected: (value) => setState(() => _draft =
                        _draft.withPrecision(value == 'افتراضي'
                          ? null : int.parse(value)))), u, labelSize),
                    SizedBox(height: 32 * u),
                    _settingRow('توقيت', _dropdown(u: u,
                      key: const Key('symbol-timezone'),
                      value: _draft.timeZone.labelAt(DateTime.now().toUtc()),
                      items: ChartTimeZone.values.map(
                        (zone) => zone.labelAt(DateTime.now().toUtc())).toList(),
                      onSelected: (value) => setState(() => _draft =
                        _draft.copyWith(timeZone: ChartTimeZone.values.firstWhere(
                          (zone) => zone.labelAt(DateTime.now().toUtc()) == value)))),
                      bidi: true), u, labelSize),
                    SizedBox(height: 38 * u),
                  ]),
              ),
            ),
          )),
          Container(key: const Key('symbol-fixed-footer'),
            decoration: const BoxDecoration(border: Border(top:
              BorderSide(color: TradeColors.panelBorder, width: .5))),
            padding: EdgeInsets.symmetric(horizontal: 38 * u,
              vertical: 34 * u),
            child: Row(children: [
              _footer('•••', u: u, width: 110,
                key: const Key('symbol-more'),
                outline: TradeColors.panelBorder,
                onTap: () => showModalBottomSheet<void>(context: context,
                  builder: (ctx) => SafeArea(child: ListTile(
                    title: const Text('إعدادات الرمز',
                      textDirection: TextDirection.rtl),
                    onTap: () => Navigator.pop(ctx))))),
              const Spacer(),
              _footer('إلغاء', u: u, width: 94,
                key: const Key('symbol-cancel'),
                outline: TradeColors.panelInk, onTap: widget.onCancel),
              SizedBox(width: 23 * u),
              _footer('موافق', u: u, width: 115,
                key: const Key('symbol-apply'), filled: true,
                onTap: () => widget.onApply(_draft)),
            ]),
          ),
        ]),
      ),
    );
  });

  Widget _section(String label, double u) => Text(label,
    textAlign: TextAlign.right,
    style: TextStyle(fontSize: (22 * u).clamp(12.5, 16),
      color: TradeColors.panelMuted));

  Widget _checkbox(bool enabled, double u) => Container(
    height: 34 * u, width: 34 * u,
    decoration: BoxDecoration(
      color: enabled ? TradeColors.panelAccept : Colors.white,
      borderRadius: BorderRadius.circular(5 * u),
      border: Border.all(color: TradeColors.panelAccept, width: 1.2)),
    child: enabled ? Icon(Icons.check, color: Colors.white,
      size: math.max(14, 26 * u)) : null);

  Widget _checkedRow(String label, bool current, double u, double font, {
    required Key key, required ValueChanged<bool> onChanged,
  }) => GestureDetector(key: key, behavior: HitTestBehavior.opaque,
    onTap: () => onChanged(!current),
    child: Semantics(label: label, checked: current,
      child: SizedBox(height: 38 * u, child: Row(children: [
        _checkbox(current, u),
        SizedBox(width: 15 * u),
        Expanded(child: Text(label, textAlign: TextAlign.right,
          maxLines: 2, style: TextStyle(fontSize: font,
            color: TradeColors.panelInk))),
      ]))));

  Widget _colorRow(String label, bool selected, {
    required int bear, required int bull,
    required double u, required double font,
    required Key toggleKey, required Key bearKey, required Key bullKey,
    required ValueChanged<bool> onCheck,
    required VoidCallback onBear, required VoidCallback onBull,
  }) => SizedBox(height: 64 * u, child: Row(children: [
    GestureDetector(key: toggleKey, behavior: HitTestBehavior.opaque,
      onTap: () => onCheck(!selected),
      child: Semantics(label: label, checked: selected,
        child: _checkbox(selected, u))),
    SizedBox(width: 15 * u),
    Expanded(child: Text(label, textAlign: TextAlign.right,
      maxLines: 2, style: TextStyle(fontSize: font,
        color: TradeColors.panelInk))),
    SizedBox(width: 145 * u,
      child: Row(textDirection: TextDirection.ltr, children: [
        _colorWell(key: bearKey, color: bear,
          u: u, enabled: selected, onTap: onBear),
        SizedBox(width: 17 * u),
        _colorWell(key: bullKey, color: bull,
          u: u, enabled: selected, onTap: onBull),
      ])),
    SizedBox(width: 143 * u),
  ]));

  Widget _colorWell({required Key key, required int color,
    required double u, required bool enabled, required VoidCallback onTap}) =>
      GestureDetector(key: key, onTap: enabled ? onTap : null,
        child: Semantics(button: enabled, label: 'تغيير لون الشمعة',
          child: Container(width: 64 * u, height: 64 * u,
            padding: EdgeInsets.all(8 * u),
            decoration: BoxDecoration(color: Colors.white,
              border: Border.all(color: TradeColors.panelBorder),
              borderRadius: BorderRadius.circular(12 * u)),
            child: DecoratedBox(decoration: BoxDecoration(
              color: Color(color).withValues(alpha: enabled ? 1 : .4),
              borderRadius: BorderRadius.circular(6 * u))))));

  Widget _settingRow(String label, Widget control, double u, double font) =>
      SizedBox(height: 64 * u, child: Row(children: [
        Expanded(child: Text(label, textAlign: TextAlign.right,
          style: TextStyle(fontSize: font, color: TradeColors.panelInk))),
        SizedBox(width: 18 * u),
        control,
      ]));

  Widget _dropdown({required Key key, required double u,
    required String value, required List<String> items,
    required ValueChanged<String> onSelected, bool bidi = false}) =>
      PopupMenuButton<String>(key: key, initialValue: value,
        onSelected: onSelected,
        itemBuilder: (_) => [for (final text in items)
          PopupMenuItem(value: text, child: Text(text,
            textDirection: TextDirection.rtl))],
        child: Container(width: 287 * u, height: 64 * u,
          decoration: BoxDecoration(color: Colors.white,
            border: Border.all(color: TradeColors.panelBorder),
            borderRadius: BorderRadius.circular(13 * u)),
          padding: EdgeInsets.symmetric(horizontal: 14 * u),
          child: Row(children: [
            Expanded(child: bidi
              ? Text(value, textAlign: TextAlign.right,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: TradeColors.panelInk,
                    fontSize: (27 * u).clamp(14, 18)))
              : Text(value, textAlign: TextAlign.right,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: TradeColors.panelInk,
                    fontSize: (27 * u).clamp(14, 18)))),
            const Icon(Icons.keyboard_arrow_down,
              size: 23, color: TradeColors.panelMuted),
          ])));

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
