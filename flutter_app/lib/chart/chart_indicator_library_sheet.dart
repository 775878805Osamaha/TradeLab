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
        content: Text('يمكن إضافة 8 مؤشرات متزامنة كحد أقصى')));
      return;
    }
    _change(next);
  }

  Future<void> _addPineSource() async {
    final title = TextEditingController();
    final source = TextEditingController();
    try {
      final requestedSave = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const Key('indicator-pine-editor'),
          title: const Text('حفظ مؤشر Pine خاص'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  key: const Key('indicator-script-title'),
                  controller: title,
                  maxLength: ChartSavedIndicatorScript.maxNameLength,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(
                    labelText: 'اسم المؤشر',
                    hintText: 'مثال: Ahmad HA First Trend V10',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('indicator-script-source'),
                  controller: source,
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
                  'التشغيل المباشر متاح فقط للنوع البسيط '
                  'indicator("Name", overlay=true) مع '
                  'plot(ta.sma(close, N)). '
                  'استراتيجيات Pine المعقدة تُحفظ، ولا تُنفذ أو تُعرض كمؤشر وهمي.',
                  key: Key('indicator-pine-capability'),
                  style: TextStyle(fontSize: 12),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              key: const Key('indicator-script-save'),
              onPressed: () {
                if (title.text.trim().isEmpty || source.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      );
      if (requestedSave != true || !mounted) return;
      final name = title.text.trim();
      final code = source.text.trim();
      var id = 'script-' +
          DateTime.now().microsecondsSinceEpoch.toString();
      while (_library.scripts.any((item) => item.id == id)) {
        id = id + '-1';
      }
      final script = ChartSavedIndicatorScript(
          id: id, name: name, source: code);
      final updated = _library.saveScript(script);
      if (identical(updated, _library)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('وصلت إلى الحد المسموح (25 نصًا) '
              'أو تعذر حفظ هذا النص')));
        return;
      }
      _change(updated);
      _search.clear();
      if (script.supportedSmaPeriod == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم حفظ الكود. هذه الصيغة تتطلب محرك Pine '
              'ولم تُضف إلى الشارت بعد.')));
      }
    } finally {
      title.dispose();
      source.dispose();
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
          ? 'مؤشرك · SMA محسوب من شموع الشارت'
          : 'المتوسط المتحرك البسيط · على الشارت'),
      leading: IconButton(
        key: Key('indicator-favorite-' + item.id),
        tooltip: favorite ? 'إزالة من المفضلة' : 'إضافة إلى المفضلة',
        icon: Icon(favorite ? Icons.star : Icons.star_border,
          color: favorite ? Colors.amber.shade700 : null),
        onPressed: () => _change(_library.toggleFavorite(item.id)),
      ),
      trailing: enabled
          ? const Icon(Icons.check_circle, color: Colors.green)
          : const Icon(Icons.add_circle_outline),
      onTap: () => _toggle(item),
    );
  }

  Widget _scriptRow(ChartSavedIndicatorScript script) {
    final period = script.supportedSmaPeriod;
    if (period != null) {
      return _indicatorRow(ChartIndicatorDefinition(
        script.id, script.name, period, custom: true,
      ));
    }
    return ListTile(
      key: Key('indicator-unsupported-' + script.id),
      title: Text(script.name),
      subtitle: const Text(
          'محفوظ في مؤشراتي · يتطلب دعم Pine Script للتشغيل'),
      leading: const Icon(Icons.code_outlined),
      trailing: IconButton(
        key: Key('indicator-delete-' + script.id),
        tooltip: 'حذف النص المحفوظ',
        onPressed: () => _change(_library.deleteScript(script.id)),
        icon: const Icon(Icons.delete_outline),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = _library.supported;
    final children = <Widget>[];
    switch (_tab) {
      case 0:
        children.addAll(ChartIndicatorDefinition.builtIns
            .where((item) => _matches(item.title))
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
            SizedBox(height: 48, child: ListView(
              key: const Key('indicator-library-tabs'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
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
              ],
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
