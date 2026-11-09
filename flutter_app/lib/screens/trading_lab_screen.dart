import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/market_api.dart';
import '../data/market_controller.dart';
import '../data/tradelab_data.dart';
import '../paper/paper_journal_controller.dart';
import '../paper/paper_ledger.dart';
import '../paper/paper_risk_engine.dart';
import '../paper/paper_trade_service.dart';
import '../replay/replay_lab_bridge.dart';
import '../replay/replay_research_workspace.dart';
import '../theme/tradelab_theme.dart';
import '../widgets/trade_components.dart';

/// Read-only risk workspace. The chart and all Replay controls stay mounted
/// in their original tab; calculations never place live or paper orders.
class TradingLabScreen extends StatefulWidget {
  const TradingLabScreen({
    required this.controller,
    required this.journal,
    required this.replayBridge,
    required this.onOpenChart,
    super.key,
  });

  final MarketController controller;
  final PaperJournalController journal;
  final ReplayLabBridge replayBridge;
  final VoidCallback onOpenChart;

  @override
  State<TradingLabScreen> createState() => _TradingLabScreenState();
}

class _TradingLabScreenState extends State<TradingLabScreen> {
  int _tab = 0;
  ReplayLabSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    widget.journal.addListener(_onJournalChanged);
    widget.replayBridge.addListener(_onLabReopened);
  }

  @override
  void didUpdateWidget(covariant TradingLabScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.journal != oldWidget.journal) {
      oldWidget.journal.removeListener(_onJournalChanged);
      widget.journal.addListener(_onJournalChanged);
      _snapshot = null;
    }
    if (widget.replayBridge != oldWidget.replayBridge) {
      oldWidget.replayBridge.removeListener(_onLabReopened);
      widget.replayBridge.addListener(_onLabReopened);
    }
  }

  void _onLabReopened() {
    if (_tab == 2 && mounted) _captureReplay();
  }

  void _onJournalChanged() {
    if (!mounted) return;
    if (_snapshot != null && _snapshot!.accountKey != widget.journal.accountKey) {
      _snapshot = null; // Never display another account's Replay snapshot.
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.journal.removeListener(_onJournalChanged);
    widget.replayBridge.removeListener(_onLabReopened);
    super.dispose();
  }

  void _captureReplay() {
    final snapshot = widget.replayBridge.capture();
    setState(() => _snapshot = snapshot != null &&
        snapshot.accountKey == widget.journal.accountKey ? snapshot : null);
  }

  void _chooseTab(int next) {
    if (next == 2) _captureReplay();
    setState(() => _tab = next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(children: [
      Container(
        width: double.infinity,
        color: colors.surface,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.science_outlined, color: TradeColors.blue, size: 25),
            const SizedBox(width: 10),
            Expanded(child: Text('مختبر التداول',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800))),
            const TradeStatusChip(label: 'تجريبي · محلي'),
          ]),
          const SizedBox(height: 5),
          Text('إدارة المخاطر وتحليل جلسات Replay دون تغيير الشارت',
            style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 14),
          SingleChildScrollView(scrollDirection: Axis.horizontal,
            child: Row(children: [
              _tabChip('المخاطر', Icons.shield_outlined, 0),
              _tabChip('حجم الصفقة', Icons.calculate_outlined, 1),
              _tabChip('تحليل Replay', Icons.analytics_outlined, 2),
            ])),
        ]),
      ),
      // Keep form inputs and the last frozen analysis while switching sections.
      Expanded(child: IndexedStack(index: _tab, children: [
        _riskOverview(),
        PaperRiskCalculator(controller: widget.controller,
          journal: widget.journal),
        _replayWorkspace(),
      ])),
    ]);
  }

  Widget _tabChip(String label, IconData icon, int index) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 8),
    child: ChoiceChip(
      key: Key('lab-tab-$index'),
      avatar: Icon(icon, size: 17,
        color: _tab == index ? TradeColors.blue : null),
      label: Text(label), selected: _tab == index,
      onSelected: (_) => _chooseTab(index),
    ),
  );

  Widget _riskOverview() {
    final journal = widget.journal;
    final theme = Theme.of(context);
    if (journal.busy) {
      return const Center(child: CircularProgressIndicator());
    }
    if (journal.error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(journal.error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: journal.refresh,
            icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
        ])));
    }
    final entries = journal.entries;
    late final LedgerReport report;
    try {
      report = calculateLedgerReport(entries);
    } catch (_) {
      return const TradeEmptyState(icon: Icons.error_outline,
        title: 'تعذر تحليل الدفتر المحلي',
        description: 'تأكد من سلامة القيود في صفحة النتائج. لم تُحذف أي بيانات.');
    }
    final open = entries.where((e) => e.kind == LedgerKind.openTrade);
    final committed = open.fold<double>(0, (sum, e) =>
      sum + e.quantity! * e.entryPrice!);
    final protected = open.where((e) => e.stopLoss != null).toList();
    final openRisk = protected.fold<double>(0, (sum, e) =>
      sum + (e.entryPrice! - e.stopLoss!).abs() * e.quantity!);
    final unprotected = open.length - protected.length;
    final now = DateTime.now().toUtc();
    final nowMs = now.millisecondsSinceEpoch;
    final dayStart = DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch;
    final todayPnl = entries.where((e) => e.kind == LedgerKind.closedTrade &&
        e.timestampMs >= dayStart && e.timestampMs <= nowMs)
        .fold<double>(0, (sum, e) => sum + e.realizedPnl);
    final money = (double n) => '${n.toStringAsFixed(2)} USD';
    return ListView(key: const Key('lab-risk-overview'),
      padding: const EdgeInsets.all(16), children: [
        const TradeSectionTitle('ملخص المخاطرة الحالي'),
        if (entries.isEmpty) const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('الدفتر فارغ. أضف رصيدًا أو سجل صفقات من صفحة النتائج '
              'لتظهر حسابات المخاطرة الفعلية.')),
        GridView.count(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10,
          childAspectRatio: 1.45,
          children: [
            _metric('الرصيد المسجل', money(report.closingBalance),
              Icons.account_balance_wallet_outlined),
            _metric('الرصيد الحر*', money(math.max(0, report.closingBalance - committed)),
              Icons.savings_outlined),
            _metric('مخاطرة المراكز*', money(openRisk), Icons.shield_outlined),
            _metric('نتيجة اليوم UTC', money(todayPnl), Icons.today_outlined),
          ],
        ),
        const SizedBox(height: 18),
        if (unprotected > 0) ...[
          TradeSurface(child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: TradeColors.negative),
            const SizedBox(width: 10),
            Expanded(child: Text('هناك $unprotected مركز مفتوح بلا وقف خسارة مسجل. '
                'إجمالي المخاطرة المعروض لا يشملها.')),
          ])),
          const SizedBox(height: 12),
        ],
        TradeSurface(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TradeSectionTitle('تخطيط صفقتك التالية'),
            const Text('أدخل وقف الخسارة والهدف وحدّ الخسارة الذي تختاره؛ '
              'سيحسب المختبر كمية الأصل الممكنة باستخدام عرض سعر حقيقي.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('lab-open-calculator'),
              onPressed: () => _chooseTab(1),
              icon: const Icon(Icons.calculate_outlined),
              label: const Text('فتح حاسبة المخاطر')),
          ],
        )),
        const SizedBox(height: 14),
        Text('* الرصيد الحر محسوب دون رافعة أو هامش، ومخاطرة المراكز '
            'من مستويات وقف مسجلة فقط. لا توجد متابعة تلقائية لتنفيذ الوقف أو '
            'لتغير الربح غير المحقق. جميع البيانات من الدفتر المحلي، '
            'وليست رصيد حساب cTrader.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant)),
      ]);
  }

  Widget _metric(String title, String value, IconData icon) => TradeSurface(
    padding: const EdgeInsets.all(12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(title, maxLines: 2,
          style: Theme.of(context).textTheme.labelMedium)),
        Icon(icon, size: 19, color: TradeColors.blue),
      ]),
      const Spacer(),
      FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart,
        child: Text(value, textDirection: TextDirection.ltr,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800))),
    ]),
  );

  Widget _replayWorkspace() {
    final snapshot = _snapshot;
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          Expanded(child: Text(snapshot == null
              ? 'لا توجد لقطة Replay صالحة' :
                'جلسة مجمدة · ${snapshot.symbol} · ${snapshot.timeframe}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700))),
          OutlinedButton.icon(
            key: const Key('lab-refresh-replay'),
            onPressed: _captureReplay,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('التقاط')),
        ])),
      Expanded(child: snapshot == null
        ? Center(child: Padding(padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.history_toggle_off, size: 42,
                color: TradeColors.blue),
              const SizedBox(height: 12),
              const Text('ابدأ Replay من الشارت',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 8),
              const Text('اختر 30 شمعة تاريخية مغلقة على الأقل من cTrader '
                  'أو Binance، ثم عد إلى المختبر. لا تُستخدم شموع المعاينة '
                  'أو شموع المدى المحوّلة.', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: widget.onOpenChart,
                icon: const Icon(Icons.candlestick_chart_outlined),
                label: const Text('العودة للشارت')),
            ])))
        : ReplayResearchWorkspace(snapshot: snapshot,
            onOpenChart: widget.onOpenChart,
          )),
    ]);
  }
}

class PaperRiskCalculator extends StatefulWidget {
  const PaperRiskCalculator({required this.controller,
    required this.journal, super.key});

  final MarketController controller;
  final PaperJournalController journal;

  @override
  State<PaperRiskCalculator> createState() => _PaperRiskCalculatorState();
}

class _PaperRiskCalculatorState extends State<PaperRiskCalculator> {
  final _stop = TextEditingController();
  final _target = TextEditingController();
  final _maxLoss = TextEditingController();
  final _dailyLoss = TextEditingController();
  final _openRiskLimit = TextEditingController();
  final _notionalLimit = TextEditingController();
  final _maxTradesPerDay = TextEditingController();
  final _minRewardRisk = TextEditingController();
  final _reserve = TextEditingController(text: '0');
  String _code = 'XAUUSD';
  PaperSide _side = PaperSide.buy;
  PaperRiskAssessment? _result;
  PreparedPaperQuote? _quote;
  String? _error;
  bool _working = false;
  int _generation = 0;

  Iterable<TextEditingController> get _fields => [
    _stop, _target, _maxLoss, _dailyLoss, _openRiskLimit,
    _notionalLimit, _maxTradesPerDay, _minRewardRisk, _reserve,
  ];

  @override
  void initState() {
    super.initState();
    for (final field in _fields) {
      field.addListener(_invalidate);
    }
    widget.journal.addListener(_invalidate);
  }

  @override
  void dispose() {
    widget.journal.removeListener(_invalidate);
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  void _invalidate() {
    _generation++;
    if (mounted && (_result != null || _quote != null || _error != null)) {
      setState(() { _result = null; _quote = null; _error = null; });
    }
  }

  double _required(TextEditingController field) {
    final result = double.tryParse(field.text.trim().replaceAll(',', '.'));
    if (result == null || !result.isFinite || result <= 0) {
      throw const FormatException('أدخل وقفًا وهدفًا وحدًا موجبًا لخسارة الصفقة.');
    }
    return result;
  }

  double? _optional(TextEditingController field) {
    if (field.text.trim().isEmpty) return null;
    return _required(field);
  }

  int? _optionalPositiveInteger(TextEditingController field) {
    if (field.text.trim().isEmpty) return null;
    final value = int.tryParse(field.text.trim());
    if (value == null || value <= 0) {
      throw const FormatException('عدد الصفقات اليومي يجب أن يكون عددًا صحيحًا موجبًا.');
    }
    return value;
  }

  Future<void> _calculate() async {
    if (_working || widget.journal.busy || widget.journal.error != null) return;
    final request = ++_generation;
    try {
      final stop = _required(_stop);
      final target = _required(_target);
      final maxLoss = _required(_maxLoss);
      final dailyLoss = _optional(_dailyLoss);
      final openRisk = _optional(_openRiskLimit);
      final notionalLimit = _optional(_notionalLimit);
      final maxTradesPerDay = _optionalPositiveInteger(_maxTradesPerDay);
      final minRewardRisk = _optional(_minRewardRisk);
      final reserveText = _reserve.text.trim();
      final reserve = reserveText.isEmpty ? 0.0 :
          double.tryParse(reserveText.replaceAll(',', '.'));
      if (reserve == null || !reserve.isFinite || reserve < 0) {
        throw const FormatException('الاحتياطي النقدي يجب ألا يكون سالبًا.');
      }
      final symbol = tradeSymbols.firstWhere((s) => s.code == _code);
      final side = _side;
      final service = PaperTradeService(
        quotes: LivePaperQuoteProvider(widget.controller),
        journal: widget.journal);
      setState(() { _working = true; _result = null; _quote = null; _error = null; });
      final quote = await service.prepare(symbol);
      if (!mounted || request != _generation) return;
      final result = service.assessRisk(
        symbol: symbol, side: side, stopLoss: stop, takeProfit: target,
        prepared: quote,
        limits: PaperRiskLimits(maxLossPerTradeUsd: maxLoss,
          maxDailyLossUsd: dailyLoss, maxOpenRiskUsd: openRisk,
          maxPositionNotionalUsd: notionalLimit,
          maxTradesPerDay: maxTradesPerDay, minRewardRisk: minRewardRisk,
          cashReserveUsd: reserve));
      setState(() { _result = result; _quote = quote;
        _error = result.allowed ? null : result.reasons.join(' '); });
    } catch (error) {
      if (mounted && request == _generation) {
        setState(() => _error = switch (error) {
          FormatException e => e.message.toString(),
          MarketDataException e => e.message,
          StateError e => e.message.toString(),
          _ => 'تعذر إكمال الحساب. تأكد من الرصيد والمصدر ثم أعد المحاولة.',
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(key: const Key('lab-risk-calculator'),
      padding: const EdgeInsets.all(16), children: [
        const TradeSectionTitle('احسب حجم الصفقة'),
        const Text('تعتمد الحاسبة على دفتر الحساب المحلي وعرض BID/ASK '
          'مباشر من المصدر الفعلي، وليس على سعر افتراضي.'),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          key: const Key('lab-risk-symbol'),
          initialValue: _code,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'الرمز'),
          items: [for (final symbol in tradeSymbols)
            if (LedgerEntry.usdQuotedSymbols.contains(symbol.code))
              DropdownMenuItem(value: symbol.code,
                child: Text('${symbol.code} · ${symbol.title}',
                  maxLines: 1, overflow: TextOverflow.ellipsis))],
          onChanged: (value) {
            if (value == null) return;
            _invalidate();
            setState(() => _code = value);
          },
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 10, children: [
          ChoiceChip(label: const Text('شراء'), selected: _side == PaperSide.buy,
            onSelected: (_) { _invalidate(); setState(() => _side = PaperSide.buy); }),
          ChoiceChip(label: const Text('بيع'), selected: _side == PaperSide.sell,
            onSelected: (_) { _invalidate(); setState(() => _side = PaperSide.sell); }),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _field(_stop, 'وقف الخسارة SL',
            key: const Key('lab-stop-loss'))),
          const SizedBox(width: 8),
          Expanded(child: _field(_target, 'الهدف TP',
            key: const Key('lab-take-profit'))),
        ]),
        const SizedBox(height: 10),
        _field(_maxLoss, 'أقصى خسارة للصفقة (USD)',
          key: const Key('lab-max-loss')),
        const SizedBox(height: 10),
        ExpansionTile(title: const Text('حدود إضافية (اختيارية)'),
          tilePadding: EdgeInsets.zero,
          children: [
            _field(_dailyLoss, 'حد الخسارة اليومي (UTC / USD)'),
            const SizedBox(height: 10),
            _field(_openRiskLimit, 'الحد الإجمالي للمراكز المفتوحة (USD)'),
            const SizedBox(height: 10),
            _field(_notionalLimit, 'أقصى قيمة اسمية لجميع المراكز (USD)',
              key: const Key('lab-max-notional')),
            const SizedBox(height: 10),
            _field(_maxTradesPerDay, 'أقصى عدد صفقات في اليوم (UTC)',
              key: const Key('lab-max-trades'), integer: true),
            const SizedBox(height: 10),
            _field(_minRewardRisk, 'الحد الأدنى للعائد / المخاطرة',
              key: const Key('lab-min-reward-risk')),
            const SizedBox(height: 10),
            _field(_reserve, 'احتياطي لا يُستخدم (USD)'),
          ]),
        const SizedBox(height: 14),
        FilledButton.icon(
          key: const Key('lab-calculate-risk'),
          onPressed: _working || widget.journal.busy ||
              widget.journal.error != null ? null : _calculate,
          icon: _working ? const SizedBox(width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2)) :
            const Icon(Icons.calculate_outlined),
          label: Text(_working ? 'جاري التحقق من السعر...' : 'حساب الكمية حسب الحدود')),
        if (widget.journal.error != null) Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(widget.journal.error!, style: TextStyle(color: colors.error))),
        if (_error != null) Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(_error!, style: TextStyle(color: colors.error))),
        if (_result != null && _result!.allowed && _quote != null) ...[
          const SizedBox(height: 14),
          TradeSurface(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              const TradeSectionTitle('نتيجة الحساب'),
              _resultRow('الكمية القصوى بوحدات الأصل',
                _result!.maxUnits.toStringAsFixed(6)),
              _resultRow('الخسارة المخططة',
                '${_result!.riskUsd.toStringAsFixed(2)} USD'),
              _resultRow('القيمة الاسمية دون رافعة',
                '${_result!.notionalUsd.toStringAsFixed(2)} USD'),
              _resultRow('العائد / المخاطرة',
                _result!.rewardRisk.toStringAsFixed(2)),
              _resultRow('سعر الدخول BID/ASK',
                _quote!.quote.executionPrice(buy: _side == PaperSide.buy)
                  .toString()),
            ])),
        ],
        const SizedBox(height: 14),
        Text('حد الخسارة اليومي يحجز أيضًا المخاطرة المسجلة للمراكز '
          'المفتوحة منذ أيام سابقة. حساب توضيحي قابل للتغير مع السعر والرصيد. الكمية '
          'بوحدات الأصل وليست لوت cTrader؛ لا توجد محاكاة للرافعة أو '
          'الهامش أو عمولات الوسيط. لا يرسل هذا القسم أوامر ولا يحفظ '
          'حدودًا دائمة. استخدم نافذة الصفقة لإعادة التحقق قبل التسجيل.',
          style: Theme.of(context).textTheme.bodySmall),
      ]);
  }

  Widget _field(TextEditingController field, String label,
    {Key? key, bool integer = false}) => TextField(
    key: key, controller: field, textDirection: TextDirection.ltr,
    keyboardType: TextInputType.numberWithOptions(decimal: !integer),
    decoration: InputDecoration(labelText: label),
  );

  Widget _resultRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Expanded(child: Text(label)),
      const SizedBox(width: 8),
      Flexible(child: Text(value, textDirection: TextDirection.ltr,
        style: const TextStyle(fontWeight: FontWeight.w800))),
    ]));
}
