import 'package:flutter/material.dart';

import 'chart_indicator_library.dart';

/// Native, scrollable indicator discovery screen for TradeLab Android.
/// It does not pretend that arbitrary TradingView Pine strategies execute.
/// Only real source-derived overlays have an Add/Remove control.
class ChartIndicatorLibrarySheet extends StatefulWidget {
  const ChartIndicatorLibrarySheet({
    required this.initial,
    required this.onChange,
    this.initialTab = 0,
    super.key,
  });

  final ChartIndicatorLibraryState initial;
  final ValueChanged<ChartIndicatorLibraryState> onChange;
  final int initialTab;

  @override
  State<ChartIndicatorLibrarySheet> createState() =>
      _ChartIndicatorLibrarySheetState();
}

class _ChartIndicatorLibrarySheetState
    extends State<ChartIndicatorLibrarySheet> {
  late ChartIndicatorLibraryState _library = widget.initial;
  final TextEditingController _search = TextEditingController();
  late int _tab = widget.initialTab.clamp(0, 3).toInt();
  static const _tabNames = [
    'المضمنة',
    'مؤشراتي',
    'المفضلة',
    'المضافة',
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _change(ChartIndicatorLibraryState state) {
    if (identical(state, _library)) return;
    setState(() => _library = state);
    widget.onChange(state);
  }

  bool _matches(String name) {
    final query = _search.text.trim().toLowerCase();
    return query.isEmpty || name.toLowerCase().contains(query);
  }

  void _toggle(ChartIndicatorDefinition indicator) {
    final next = _library.toggleActive(indicator.id);
    if (identical(next, _library)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('يمكن إضافة 8 مؤشرات ولوحتين مستقلتين كحد أقصى')));
      return;
    }
    _change(next);
  }

  Future<void> _addPineSource() async {
    // The editor owns its TextEditingControllers until the Navigator has
    // fully disposed the dialog route. Disposing them immediately after
    // showDialog returns races Flutter's dismissal/focus animation.
    final input = await showDialog<({String name, String source})>(
      context: context,
      builder: (_) => const _ChartPineSourceEditorDialog(),
    );
    if (input == null || !mounted) return;
    var id = 'script-' +
        DateTime.now().microsecondsSinceEpoch.toString();
    while (_library.scripts.any((item) => item.id == id)) {
      id = id + '-1';
    }
    final script = ChartSavedIndicatorScript(
        id: id, name: input.name, source: input.source);
    final updated = _library.saveScript(script);
    if (identical(updated, _library)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('وصلت إلى الحد المسموح (25 نصًا) '
            'أو تعذر حفظ هذا النص')));
      return;
    }
    _change(updated);
    _search.clear();
    if (script.supportedIndicator() == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تم حفظ الكود. هذه الصيغة تتطلب محرك Pine '
            'ولم تُضف إلى الشارت بعد.')));
    }
  }

  Future<void> _editSavedPine(ChartSavedIndicatorScript script) async {
    final updated = await showDialog<({String name, String source})>(
      context: context,
      builder: (_) => _ChartPineSourceEditorDialog(
        originalName: script.name, originalSource: script.source),
    );
    if (updated == null || !mounted) return;
    final next = _library.updateScript(
      id: script.id, name: updated.name, source: updated.source);
    if (identical(next, _library)) return;
    _change(next);
    final revised = next.scripts.firstWhere((item) => item.id == script.id);
    if (revised.supportedIndicator() == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تم حفظ النص دون تشغيل: ' +
            (revised.compileError ?? 'صيغة غير مدعومة'))));
    }
  }

  Future<void> _editStudyLength(ChartIndicatorDefinition item) async {
    if (item.custom || item.kind == ChartIndicatorKind.macd) return;
    var inputLength = item.period.toString();
    final length = await showDialog<int>(context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('indicator-settings-dialog'),
        title: Text('إعدادات ' + item.title),
        content: TextFormField(
          key: const Key('indicator-length-input'),
          initialValue: inputLength,
          keyboardType: TextInputType.number,
          onChanged: (value) => inputLength = value,
          decoration: const InputDecoration(
            labelText: 'الطول (1–500)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء')),
          FilledButton(
            key: const Key('indicator-length-save'),
            onPressed: () =>
                Navigator.pop(dialogContext, int.tryParse(inputLength)),
            child: const Text('تطبيق'),
          ),
        ],
      ),
    );
    if (!mounted || length == null) return;
    final updated = _library.setPeriod(item.id, length);
    if (identical(updated, _library)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('الطول غير صالح لهذا المؤشر')));
    } else {
      _change(updated);
    }
  }

  Widget _indicatorRow(ChartIndicatorDefinition item) {
    final enabled = _library.activeIds.contains(item.id);
    final favorite = _library.favoriteIds.contains(item.id);
    return ListTile(
      key: Key('indicator-row-' + item.id),
      title: Text(item.title, textDirection: TextDirection.ltr,
        textAlign: TextAlign.right),
      subtitle: Text(item.custom
          ? 'من مؤشراتي · ' + item.kind.name.toUpperCase()
          : item.separatePane
              ? 'لوحة مستقلة · محسوب من شموع الشارت'
              : item.kind == ChartIndicatorKind.bollinger
                  ? 'ثلاثة خطوط · الوسط وحدّا الانحراف المعياري'
                  : 'مؤشر حقيقي · طول ' + item.period.toString()),
      leading: IconButton(
        key: Key('indicator-favorite-' + item.id),
        tooltip: favorite ? 'إزالة من المفضلة' : 'إضافة إلى المفضلة',
        icon: Icon(favorite ? Icons.star : Icons.star_border,
          color: favorite ? Colors.amber.shade700 : null),
        onPressed: () => _change(_library.toggleFavorite(item.id)),
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (!item.custom && item.kind != ChartIndicatorKind.macd)
          IconButton(
            key: Key('indicator-settings-' + item.id),
            tooltip: 'تعديل طول المؤشر',
            onPressed: () => _editStudyLength(item),
            icon: const Icon(Icons.tune_outlined, size: 20),
          ),
        Icon(enabled ? Icons.check_circle : Icons.add_circle_outline,
          color: enabled ? Colors.green : null),
      ]),
      onTap: () => _toggle(item),
    );
  }

  Widget _scriptRow(ChartSavedIndicatorScript script) {
    final supported = script.supportedIndicator();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (supported != null)
        _indicatorRow(supported)
      else
        ListTile(
          key: Key('indicator-unsupported-' + script.id),
          title: Text(script.name),
          subtitle: Text('يتطلب دعم Pine Script للتشغيل · ' +
              (script.compileError ?? 'صيغة غير مدعومة'),
              maxLines: 3, overflow: TextOverflow.ellipsis),
          leading: const Icon(Icons.code_outlined),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          TextButton.icon(
            key: Key('indicator-edit-' + script.id),
            onPressed: () => _editSavedPine(script),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('تعديل'),
          ),
          const SizedBox(width: 6),
          TextButton.icon(
            key: Key('indicator-delete-' + script.id),
            onPressed: () => _change(_library.deleteScript(script.id)),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('حذف'),
          ),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final all = _library.supported;
    final children = <Widget>[];
    switch (_tab) {
      case 0:
        // Display the effective configured definitions, not the static
        // preset constants. A changed period must update the row immediately
        // and remain searchable under its new visible name.
        children.addAll(_library.supported
            .where((item) => !item.custom && _matches(item.title))
            .map(_indicatorRow));
        break;
      case 1:
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: FilledButton.icon(
            key: const Key('indicator-import-pine'),
            onPressed: _addPineSource,
            icon: const Icon(Icons.add),
            label: const Text('إضافة مؤشر من كود Pine'),
          ),
        ));
        children.addAll(_library.scripts
            .where((item) => _matches(item.name))
            .map(_scriptRow));
        if (_library.scripts.isEmpty) {
          children.add(const ListTile(
            title: Text('لم تحفظ مؤشرات خاصة بعد'),
            subtitle: Text('أضف كودك الخاص من الزر أعلاه'),
          ));
        }
        break;
      case 2:
        children.addAll(all.where((item) =>
            _library.favoriteIds.contains(item.id) &&
            _matches(item.title)).map(_indicatorRow));
        for (final script in _library.scripts.where((item) =>
            scriptIsUnsupported(item) &&
            _library.favoriteIds.contains(item.id) &&
            _matches(item.name))) {
          children.add(_scriptRow(script));
        }
        break;
      case 3:
        children.addAll(_library.active
            .where((item) => _matches(item.title))
            .map(_indicatorRow));
        break;
    }
    if (children.isEmpty) {
      children.add(const ListTile(title: Text('لا توجد مؤشرات مطابقة')));
    }

    final theme = Theme.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: theme.colorScheme.surface,
        child: SafeArea(
          top: false,
          child: Column(children: [
            Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(children: [
                const Expanded(
                  child: Text('المؤشرات',
                    key: Key('indicator-library-title'),
                    style: TextStyle(fontSize: 22,
                        fontWeight: FontWeight.w800)),
                ),
                Text(_library.active.length.toString() + ' مضافة',
                  key: const Key('indicator-active-count')),
                IconButton(
                  key: const Key('indicator-library-close'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  tooltip: 'إغلاق',
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                key: const Key('indicator-library-search'),
                controller: _search,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  hintText: 'ابحث عن مؤشر / Search indicators',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(height: 48, child: SingleChildScrollView(
              key: const Key('indicator-library-tabs'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                for (var i = 0; i < _tabNames.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ChoiceChip(
                      key: Key('indicator-tab-' + i.toString()),
                      label: Text(_tabNames[i]),
                      selected: _tab == i,
                      onSelected: (_) => setState(() => _tab = i),
                    ),
                  ),
              ]),
            )),
            Expanded(child: ListView(
              key: const Key('indicator-library-results'),
              children: children,
            )),
          ]),
        ),
      ),
    );
  }

  bool scriptIsUnsupported(ChartSavedIndicatorScript script) =>
      script.supportedSmaPeriod == null;
}


/// The dialog owns its controller lifetime. It cannot be disposed by the
/// parent on the very frame Navigator.pop begins its exit transition.
class _ChartPineSourceEditorDialog extends StatefulWidget {
  const _ChartPineSourceEditorDialog({
    this.originalName = '',
    this.originalSource = '',
  });

  final String originalName;
  final String originalSource;

  @override
  State<_ChartPineSourceEditorDialog> createState() =>
      _ChartPineSourceEditorDialogState();
}

class _ChartPineSourceEditorDialogState
    extends State<_ChartPineSourceEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _source;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.originalName);
    _source = TextEditingController(text: widget.originalSource);
  }

  @override
  void dispose() {
    _name.dispose();
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('indicator-pine-editor'),
    title: const Text('حفظ مؤشر Pine خاص'),
    content: SizedBox(
      width: double.maxFinite,
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            key: const Key('indicator-script-title'),
            controller: _name,
            maxLength: ChartSavedIndicatorScript.maxNameLength,
            textDirection: TextDirection.rtl,
            decoration: const InputDecoration(
              labelText: 'اسم المؤشر',
              hintText: 'مثال: My Custom Indicator',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('indicator-script-source'),
            controller: _source,
            keyboardType: TextInputType.multiline,
            minLines: 5,
            maxLines: 10,
            maxLength: ChartSavedIndicatorScript.maxSourceLength,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'كود Pine Script',
              border: OutlineInputBorder(),
              hintText: '//@version=6',
            ),
          ),
          const Text(
            'محرك السلاسل يدعم عدة متغيرات وplot حتى 8 خطوط، '
            'وتعبيرات OHLC والحسابات وta.sma/ema/rsi/roc وغيرها. '
            'يدعم overlay=true/false. أوامر Pine غير المدعومة '
            'تُحفظ دون تشغيل، ويظهر سبب الرفض مع رقم السطر.',
            key: Key('indicator-pine-capability'),
            style: TextStyle(fontSize: 12),
          ),
        ]),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        key: const Key('indicator-script-save'),
        onPressed: () {
          final name = _name.text.trim();
          final source = _source.text.trim();
          if (name.isEmpty || source.isEmpty) return;
          Navigator.pop(context, (name: name, source: source));
        },
        child: const Text('حفظ'),
      ),
    ],
  );
}
