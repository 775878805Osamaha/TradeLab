import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/market_controller.dart';
import '../paper/add_paper_entry_sheet.dart';
import '../paper/paper_journal_controller.dart';
import '../paper/paper_ledger.dart';
import '../paper/paper_trade_service.dart';
import '../data/tradelab_data.dart';
import '../theme/tradelab_theme.dart';
import '../widgets/trade_components.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({required this.controller, this.journal, super.key});

  final MarketController controller;
  final PaperJournalController? journal;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  String _period = 'إجمالي';
  int _page = 0;
  DateTimeRange? _customRange;
  int? _selectedCurvePoint;
  final Set<int> _closingIds = {};

  static const _pages = [
    'نظرة عامة', 'المنحنيات البيانية', 'يوميات الصفقات',
    'إحصائيات الصفقات', 'النتائج اليومية',
  ];
  static const _periods = [
    'إجمالي', 'الكل', 'سنة', '6 أشهر', '3 أشهر', 'شهر', 'أسبوع', 'مخصص',
  ];
  static const _stats = [
    ('نسبة الفوز', Icons.donut_small),
    ('إجمالي الصفقات', Icons.swap_horiz),
    ('معامل الربح', Icons.functions),
    ('أقصى تراجع', Icons.trending_down),
    ('التوقع الرياضي', Icons.calculate_outlined),
    ('أطول سلسلة أرباح', Icons.trending_up),
    ('أطول سلسلة خسائر', Icons.south_east),
    ('متوسط مدة الصفقة', Icons.timer_outlined),
    ('معامل شارب', Icons.insights_outlined),
  ];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onAccountChange);
    widget.journal?.addListener(_onAccountChange);
  }

  @override
  void didUpdateWidget(covariant ResultsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onAccountChange);
      widget.controller.addListener(_onAccountChange);
    }
    if (oldWidget.journal != widget.journal) {
      oldWidget.journal?.removeListener(_onAccountChange);
      widget.journal?.addListener(_onAccountChange);
    }
  }

  void _onAccountChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onAccountChange);
    widget.journal?.removeListener(_onAccountChange);
    super.dispose();
  }

  LedgerReport _report() {
    final now = DateTime.now().toUtc();
    final start = switch (_period) {
      'أسبوع' => now.subtract(const Duration(days: 7)),
      'شهر' => now.subtract(const Duration(days: 30)),
      '3 أشهر' => now.subtract(const Duration(days: 90)),
      '6 أشهر' => now.subtract(const Duration(days: 182)),
      'سنة' => now.subtract(const Duration(days: 365)),
      'مخصص' when _customRange != null => _customRange!.start.toUtc(),
      _ => null,
    };
    final end = _period == 'مخصص' && _customRange != null
        ? DateTime(_customRange!.end.year, _customRange!.end.month,
            _customRange!.end.day, 23, 59, 59, 999).toUtc().millisecondsSinceEpoch
        : null;
    return calculateLedgerReport(widget.journal?.entries ?? const [],
        startMs: start?.millisecondsSinceEpoch, endMs: end);
  }

  String _money(double amount, {bool signed = false}) =>
      '${signed && amount > 0 ? '+' : ''}${amount.toStringAsFixed(2)} USD';

  String _day(int value) {
    final date = DateTime.fromMillisecondsSinceEpoch(value).toLocal();
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final journal = widget.journal;
    final report = _report();
    return Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        color: colors.surface,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('النتائج والتحليلات',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ))),
            TradeStatusChip(
              label: widget.controller.ctraderConnected
                  ? 'cTrader متصل'
                  : 'لا يوجد سجل تداول',
              connected: widget.controller.ctraderConnected,
            ),
          ]),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (var i = 0; i < _pages.length; i++)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    label: Text(_pages[i]),
                    selected: _page == i,
                    onSelected: (_) => setState(() => _page = i),
                  ),
                ),
            ]),
          ),
        ]),
      ),
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final period in _periods)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 7),
                child: FilterChip(
                  label: Text(period),
                  selected: _period == period,
                  onSelected: (_) => period == 'مخصص'
                      ? _selectCustomPeriod()
                      : setState(() { _period = period; _selectedCurvePoint = null; }),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        TradeSurface(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.lock_outline, color: TradeColors.blue, size: 20),
              const SizedBox(width: 8),
              const Expanded(child: Text('دفتر التداول التجريبي المحلي',
                style: TextStyle(fontWeight: FontWeight.w800))),
              if (journal != null)
                FilledButton.tonalIcon(
                  key: const Key('add-ledger-entry'),
                  onPressed: journal.busy || journal.error != null ? null :
                      () => showModalBottomSheet<void>(context: context,
                        isScrollControlled: true, showDragHandle: true,
                        builder: (_) => AddPaperEntrySheet(journal: journal)),
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text('قيد جديد'),
                ),
            ]),
            const SizedBox(height: 6),
            Text(journal == null
              ? 'حساب cTrader متصل لقراءة أسعار السوق. نتائج التداول التجريبي تحتاج إلى نقل سجل Room من تطبيق Android القديم أو تسجيل الصفقات في قاعدة Flutter مستقلة. لن نعرض أرصدة أو أرباحًا مفترضة.'
              : 'بيانات محفوظة على هذا الهاتف فقط، منفصلة عن Room وcTrader. أضف صفقة مغلقة أو إيداعًا أو سحبًا من سجلاتك. لا تُرسل أوامر إلى الوسيط.',
              style: Theme.of(context).textTheme.bodySmall),
            if (journal?.busy == true) const LinearProgressIndicator(),
            if (journal?.error != null)
              Text(journal!.error!, style: TextStyle(color: colors.error)),
          ],
        )),
        const SizedBox(height: 14),
        if (_page == 0) ...[
          _openPositions(),
          const SizedBox(height: 16),
          const TradeSectionTitle('ملخص الحساب'),
          _summary(report),
          const SizedBox(height: 20),
          _curve(report),
          const SizedBox(height: 20),
          _statistics(report),
          const SizedBox(height: 20),
          _recentTrades(report),
          const SizedBox(height: 20),
          _cashMovements(report),
        ] else if (_page == 1) ...[
          _curve(report),
        ] else if (_page == 2) ...[
          _openPositions(),
          const SizedBox(height: 16),
          _recentTrades(report, all: true),
        ] else if (_page == 3) ...[
          _statistics(report),
          const SizedBox(height: 12),
          _emptyMessage('شارب غير محسوب دون عوائد دورية موثقة. التراجع للربح المحقق فقط.'),
        ] else ...[
          _dailyResults(report),
        ],
      ])),
    ]);
  }

  Widget _summary(LedgerReport report) => GridView.count(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.35,
        children: [
          _metric('صافي الربح', Icons.trending_up, TradeColors.positive,
            report.trades.isEmpty ? null : _money(report.netProfit, signed: true)),
          _metric('إجمالي الإيداعات', Icons.south_west, TradeColors.blue,
            report.entries.isEmpty ? null : _money(report.deposits)),
          _metric('الرصيد الابتدائي', Icons.account_balance_wallet_outlined, TradeColors.blue,
            widget.journal?.entries.isEmpty != false ? null : _money(report.openingBalance)),
          _metric('الرصيد النهائي', Icons.account_balance_outlined, TradeColors.gold,
            widget.journal?.entries.isEmpty != false ? null : _money(report.closingBalance)),
        ],
      );

  Widget _metric(String title, IconData icon, Color color, String? value) => TradeSurface(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, maxLines: 1,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
            Icon(icon, color: color, size: 19),
          ]),
          const Spacer(),
          FittedBox(fit: BoxFit.scaleDown,
            child: Text(value ?? '—', textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
          Text(value == null ? 'لا توجد بيانات' : 'سجل محلي محقق',
              style: TextStyle(fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      );

  Widget _curve(LedgerReport report) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const TradeSectionTitle('منحنى الرصيد المحقق (دون صفقات مفتوحة)'),
        TradeSurface(child: SizedBox(
          height: 240,
          child: report.balanceSeries.isEmpty ? const TradeEmptyState(
            icon: Icons.show_chart,
            title: 'في انتظار سجل التداول',
            description: 'لا يتم رسم أرباح افتراضية مكان بياناتك الحقيقية.',
          ) : LayoutBuilder(builder: (context, constraints) {
            final points = report.balanceSeries;
            final chosen = _selectedCurvePoint?.clamp(0, points.length - 1).toInt();
            void choose(double x) => setState(() => _selectedCurvePoint =
                ((x / math.max(1, constraints.maxWidth)) * (points.length - 1))
                    .round().clamp(0, points.length - 1).toInt());
            return GestureDetector(
              onTapDown: (details) => choose(details.localPosition.dx),
              onHorizontalDragUpdate: (details) => choose(details.localPosition.dx),
              child: Stack(children: [
                Positioned.fill(child: CustomPaint(
                  painter: _BalanceCurvePainter(points, chosen))),
                if (chosen != null) Positioned(top: 2, left: 4,
                  child: Text('${_day(points[chosen].$1)} · ${_money(points[chosen].$2)}',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700))),
              ]),
            );
          }),
        )),
      ]);

  Widget _statistics(LedgerReport report) {
    final duration = report.averageTradeMinutes;
    final values = <String>[
      report.winRate == null ? '—' : '${report.winRate!.toStringAsFixed(1)}%',
      '${report.tradeCount}',
      report.profitFactor == null ? '—' : report.profitFactor!.isInfinite
          ? '∞' : report.profitFactor!.toStringAsFixed(2),
      report.trades.isEmpty ? '—' : _money(report.maxDrawdown),
      report.expectancy == null ? '—' : _money(report.expectancy!, signed: true),
      report.trades.isEmpty ? '—' : '${report.bestWinStreak}',
      report.trades.isEmpty ? '—' : '${report.worstLossStreak}',
      duration == null ? '—' : duration >= 60
          ? '${(duration / 60).toStringAsFixed(1)} س' : '${duration.toStringAsFixed(0)} د',
      '—',
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const TradeSectionTitle('إحصائيات الصفقات'),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _stats.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8,
            childAspectRatio: .97,
          ),
          itemBuilder: (context, index) => TradeSurface(
            padding: const EdgeInsets.all(8),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(_stats[index].$2, size: 19, color: TradeColors.blue),
              const SizedBox(height: 7),
              FittedBox(fit: BoxFit.scaleDown,
                child: Text(values[index], textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              const SizedBox(height: 3),
              Text(_stats[index].$1, maxLines: 2, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, height: 1.2)),
            ]),
          ),
        ),
      ]);
  }

  Widget _recentTrades(LedgerReport report, {bool all = false}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        const TradeSectionTitle('آخر الصفقات المغلقة'),
        if (report.trades.isEmpty)
          const TradeSurface(child: SizedBox(height: 190,
            child: TradeEmptyState(icon: Icons.receipt_long_outlined,
              title: 'لا توجد صفقات',
              description: 'سجّل صفقة مغلقة محليًا لتظهر هنا.')))
        else for (final entry in report.trades.reversed
            .take(all ? report.trades.length : 5))
          Padding(padding: const EdgeInsets.only(bottom: 8),
            child: TradeSurface(child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${entry.symbol} · ${entry.side == PaperSide.buy ? 'شراء' : 'بيع'}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('${_day(entry.timestampMs)} · ${entry.quantity} وحدة',
                    style: Theme.of(context).textTheme.bodySmall),
                  Text('${entry.entryPrice} → ${entry.exitPrice}',
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context).textTheme.bodySmall),
                ])),
              Text(_money(entry.realizedPnl, signed: true),
                textDirection: TextDirection.ltr,
                style: TextStyle(fontWeight: FontWeight.w800,
                  color: entry.realizedPnl >= 0
                      ? TradeColors.positive : TradeColors.negative)),
              if (widget.journal != null) IconButton(
                tooltip: 'حذف القيد', icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDelete(entry)),
            ]))),
      ]);

  Widget _openPositions() {
    final positions = widget.journal?.entries.where((entry) =>
        entry.kind == LedgerKind.openTrade).toList().reversed.toList() ?? const <LedgerEntry>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const TradeSectionTitle('المراكز التجريبية المفتوحة'),
      if (positions.isEmpty)
        _emptyMessage('لا توجد مراكز مفتوحة. يمكنك فتح صفقة تجريبية من الشارت.'),
      for (final position in positions)
        Padding(padding: const EdgeInsets.only(bottom: 8),
          child: TradeSurface(child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${position.symbol} · ${position.side == PaperSide.buy ? 'شراء' : 'بيع'}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('${position.quantity} وحدة · دخول ${position.entryPrice}',
                  style: Theme.of(context).textTheme.bodySmall),
                Text('مفتوحة منذ ${_day(position.openedAtMs ?? position.timestampMs)}',
                  style: Theme.of(context).textTheme.bodySmall),
              ])),
            FilledButton.tonal(
              onPressed: _closingIds.contains(position.id) || widget.journal?.busy == true
                  ? null : () => _closePosition(position),
              child: Text(_closingIds.contains(position.id) ? 'انتظر' : 'إغلاق تجريبي'),
            ),
          ]))),
        ),
    ]);
  }

  Future<void> _closePosition(LedgerEntry position) async {
    final journal = widget.journal;
    if (journal == null || _closingIds.contains(position.id)) return;
    setState(() => _closingIds.add(position.id));
    try {
      final symbol = tradeSymbols.firstWhere((item) => item.code == position.symbol);
      final service = PaperTradeService(
        quotes: LivePaperQuoteProvider(widget.controller), journal: journal);
      final quote = await service.prepare(symbol);
      if (!mounted) return;
      final exit = quote.quote.executionPrice(buy: position.side == PaperSide.sell);
      final direction = position.side == PaperSide.buy ? 1 : -1;
      final estimatedPnl = (exit - position.entryPrice!) * position.quantity! * direction;
      final accepted = await showDialog<bool>(context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تأكيد إغلاق تجريبي'),
          content: Text('${position.symbol} · خروج عند $exit\n'
            'الربح/الخسارة المحققة نظريًا: ${_money(estimatedPnl, signed: true)}\n'
            'سيُحفظ إغلاق محلي فقط، دون أمر للوسيط أو رسوم إضافية.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('إغلاق الصفقة')),
          ],
        ));
      if (accepted != true) return;
      await service.close(position: position, prepared: quote);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حُفظ إغلاق الصفقة التجريبية في الدفتر.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إغلاق الصفقة: $error')));
    } finally {
      if (mounted) setState(() => _closingIds.remove(position.id));
    }
  }

  Widget _cashMovements(LedgerReport report) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      const TradeSectionTitle('الحركات النقدية'),
      if (!report.entries.any((e) => e.kind != LedgerKind.closedTrade))
        _emptyMessage('لم تُسجّل إيداعات أو سحوبات في هذه الفترة.'),
      for (final entry in report.entries.where((e) =>
          e.kind != LedgerKind.closedTrade).toList().reversed.take(5))
        Padding(padding: const EdgeInsets.only(bottom: 8),
          child: TradeSurface(child: Row(children: [
            Icon(entry.kind == LedgerKind.deposit ? Icons.south_west : Icons.north_east,
              color: TradeColors.blue),
            const SizedBox(width: 8),
            Expanded(child: Text('${entry.kind == LedgerKind.deposit ? 'إيداع' : 'سحب'} · ${_day(entry.timestampMs)}')),
            Text(_money(entry.amount!), textDirection: TextDirection.ltr),
            if (widget.journal != null) IconButton(
              tooltip: 'حذف القيد', icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(entry)),
          ]))),
    ],
  );

  Widget _dailyResults(LedgerReport report) {
    final days = report.dailyPnl.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const TradeSectionTitle('صافي النتائج اليومية'),
      if (days.isEmpty)
        const TradeSurface(child: SizedBox(height: 200,
          child: TradeEmptyState(icon: Icons.calendar_month_outlined,
            title: 'لا توجد نتائج يومية بعد',
            description: 'تظهر النتائج حسب تاريخ إغلاق الصفقات المسجلة.')))
      else for (final day in days)
        Padding(padding: const EdgeInsets.only(bottom: 8),
          child: TradeSurface(child: Row(children: [
            Expanded(child: Text('${day.key.year}/${day.key.month}/${day.key.day}')),
            Text(_money(day.value, signed: true), textDirection: TextDirection.ltr,
              style: TextStyle(fontWeight: FontWeight.w800,
                color: day.value >= 0
                    ? TradeColors.positive : TradeColors.negative)),
          ]))),
    ]);
  }

  Future<void> _confirmDelete(LedgerEntry entry) async {
    final journal = widget.journal;
    if (journal == null) return;
    final agreed = await showDialog<bool>(context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف القيد؟'),
        content: const Text('سيُحذف القيد المحلي نهائيًا ولا يمكن استعادته تلقائيًا.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف')),
        ],
      ));
    if (agreed != true || !mounted) return;
    try { await journal.delete(entry.id); }
    catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حذف القيد من قاعدة البيانات.')));
    }
  }

  Widget _emptyMessage(String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(value, textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall),
      );

  Future<void> _selectCustomPeriod() async {
    final now = DateTime.now();
    final dates = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDateRange: _customRange,
    );
    if (dates != null && mounted) setState(() {
      _customRange = dates;
      _period = 'مخصص';
      _selectedCurvePoint = null;
    });
  }
}

/// Renders only committed cash flows and closed trades, not mark-to-market equity.
class _BalanceCurvePainter extends CustomPainter {
  const _BalanceCurvePainter(this.points, this.selectedIndex);
  final List<(int, double)> points;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.isEmpty) return;
    const margin = 12.0;
    const top = 33.0;
    final bottom = size.height - 20;
    final values = points.map((p) => p.$2);
    final minimum = values.reduce(math.min);
    final maximum = values.reduce(math.max);
    final padding = math.max((maximum - minimum) * .12, 1.0);
    final low = minimum - padding;
    final span = maximum + padding - low;
    final width = math.max(1.0, size.width - margin * 2);
    final height = math.max(1.0, bottom - top);
    Offset point(int i) => Offset(
      margin + width * i / math.max(1, points.length - 1),
      bottom - (points[i].$2 - low) / span * height,
    );
    final line = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < points.length; i++) {
      final p = point(i);
      line.lineTo(p.dx, p.dy);
    }
    final fill = Path.from(line)
      ..lineTo(point(points.length - 1).dx, bottom)
      ..lineTo(point(0).dx, bottom)..close();
    canvas.drawPath(fill, Paint()
      ..color = TradeColors.positive.withValues(alpha: .12));
    canvas.drawPath(line, Paint()
      ..color = TradeColors.positive
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round);
    if (selectedIndex != null && selectedIndex! < points.length) {
      final p = point(selectedIndex!);
      canvas.drawLine(Offset(p.dx, top), Offset(p.dx, bottom), Paint()
        ..color = TradeColors.blue.withValues(alpha: .6));
      canvas.drawCircle(p, 4.5, Paint()..color = TradeColors.blue);
    }
  }

  @override
  bool shouldRepaint(covariant _BalanceCurvePainter previous) =>
      previous.points != points || previous.selectedIndex != selectedIndex;
}
