import 'package:flutter/material.dart';

import '../paper/paper_ledger.dart';
import '../theme/tradelab_theme.dart';
import '../widgets/trade_components.dart';
import 'replay_analysis_sheet.dart';
import 'replay_cost_estimate.dart';
import 'replay_lab_bridge.dart';
import 'replay_observed_trade.dart';
import 'replay_session_log_panel.dart';
import 'replay_session_study.dart';
import 'replay_trade_evaluator.dart';

/// Bootstrap scenarios, a single observed next-bar trade, and a session-only
/// chronological study. These never place orders or update the paper journal.
class ReplayResearchWorkspace extends StatefulWidget {
  const ReplayResearchWorkspace({required this.snapshot,
    required this.onOpenChart, super.key});

  final ReplayLabSnapshot snapshot;
  final VoidCallback onOpenChart;

  @override
  State<ReplayResearchWorkspace> createState() => _ReplayResearchWorkspaceState();
}

class _ReplayResearchWorkspaceState extends State<ReplayResearchWorkspace> {
  static const _study = ReplaySessionStudy();
  int _selected = 0;
  int _sessionRevision = 0;
  int _recorderRevision = 0;
  final _signals = <ReplayObservedSignal>[];
  ReplaySessionReport? _cachedReport;
  ReplayLabSnapshot? _cachedSnapshot;
  int _cachedRevision = -1;

  ReplaySessionReport get _sessionReport {
    if (!identical(_cachedSnapshot, widget.snapshot) ||
        _cachedRevision != _sessionRevision || _cachedReport == null) {
      _cachedSnapshot = widget.snapshot;
      _cachedRevision = _sessionRevision;
      _cachedReport = _study.summarize(signals: _signals,
        snapshot: widget.snapshot);
    }
    return _cachedReport!;
  }

  @override
  void didUpdateWidget(covariant ReplayResearchWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.accountKey != widget.snapshot.accountKey ||
        oldWidget.snapshot.symbol != widget.snapshot.symbol ||
        oldWidget.snapshot.timeframe != widget.snapshot.timeframe) {
      // The next snapshot belongs to another research scope; never silently
      // combine user accounts, symbols or candle durations in one report.
      _signals.clear();
      _sessionRevision++;
      _recorderRevision++;
    }
  }

  String? _recordSignal(ReplayObservedSignal signal) {
    try {
      _study.validateNext(existing: _signals, next: signal,
        snapshot: widget.snapshot);
      setState(() {
        _signals.add(signal);
        _sessionRevision++;
      });
      return null;
    } on FormatException catch (error) {
      return error.message.toString();
    }
  }

  void _clearSignals() => setState(() {
    _signals.clear();
    _sessionRevision++;
    _recorderRevision++;
  });

  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(scrollDirection: Axis.horizontal,
        child: Row(children: [
        ChoiceChip(
          key: const Key('lab-replay-scenario-tab'),
          label: const Text('محاكاة الاحتمالات'),
          selected: _selected == 0,
          onSelected: (_) => setState(() => _selected = 0),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          key: const Key('lab-replay-observed-tab'),
          label: const Text('متابعة إشارة'),
          selected: _selected == 1,
          onSelected: (_) => setState(() => _selected = 1),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          key: const Key('lab-replay-session-tab'),
          label: const Text('سجل الجلسة'),
          selected: _selected == 2,
          onSelected: (_) => setState(() => _selected = 2),
        ),
      ]))),
    Expanded(child: IndexedStack(index: _selected, children: [
      widget.snapshot.bars.length < 30
        ? const TradeEmptyState(icon: Icons.history_outlined,
            title: 'يلزم 30 شمعة مغلقة',
            description: 'حرّك Replay إلى الأمام لتحميل عينة كافية '
              'لمحاكاة الاحتمالات. متابعة الإشارة متاحة الآن.')
        : ReplayAnalysisSheet(
            key: ValueKey('replay-scenarios-${widget.snapshot.accountKey}-'
              '${widget.snapshot.symbol}-${widget.snapshot.timeframe}-'
              '${widget.snapshot.bars.length}-'
              '${widget.snapshot.bars.last.timestamp}'),
            bars: widget.snapshot.bars,
            symbol: widget.snapshot.symbol,
            timeframe: widget.snapshot.timeframe),
      ReplayObservedTradePanel(key: ValueKey('recorder-$_recorderRevision'),
        snapshot: widget.snapshot, onOpenChart: widget.onOpenChart,
        onRecordSignal: _recordSignal),
      ReplaySessionLogPanel(
        report: _sessionReport,
        onOpenRecorder: () => setState(() => _selected = 1),
        onClear: _clearSignals),
    ])),
  ]);
}

class ReplayObservedTradePanel extends StatefulWidget {
  const ReplayObservedTradePanel({required this.snapshot,
    required this.onOpenChart, this.onRecordSignal, super.key});

  final ReplayLabSnapshot snapshot;
  final VoidCallback onOpenChart;
  /// Optional parent session ledger; a rejection leaves the signal unrecorded.
  final String? Function(ReplayObservedSignal)? onRecordSignal;

  @override
  State<ReplayObservedTradePanel> createState() => _ReplayObservedTradePanelState();
}

class _ReplayObservedTradePanelState extends State<ReplayObservedTradePanel> {
  final _stop = TextEditingController();
  final _target = TextEditingController();
  final _cost = TextEditingController();
  PaperSide _side = PaperSide.buy;
  ReplayObservedSignal? _signal;
  String? _error;

  @override
  void initState() {
    super.initState();
    _stop.addListener(_invalidate);
    _target.addListener(_invalidate);
    _cost.addListener(_invalidate);
  }

  void _invalidate() {
    if (mounted && (_signal != null || _error != null)) {
      setState(() { _signal = null; _error = null; });
    }
  }

  @override
  void dispose() {
    _stop.dispose();
    _target.dispose();
    _cost.dispose();
    super.dispose();
  }

  void _record() {
    try {
      double? parse(TextEditingController input) =>
          double.tryParse(input.text.trim().replaceAll(',', '.'));
      final stop = parse(_stop);
      final target = parse(_target);
      if (stop == null || target == null) {
        throw const FormatException('أدخل وقف الخسارة والهدف بشكل صحيح.');
      }
      final priceCost = _cost.text.trim().isEmpty ? null :
          double.tryParse(_cost.text.trim().replaceAll(',', '.'));
      if (_cost.text.trim().isNotEmpty && priceCost == null) {
        throw const FormatException('أدخل تكلفة تنفيذ رقمية صالحة.');
      }
      final signal = ReplayObservedSignal.fromSnapshot(
        snapshot: widget.snapshot, side: _side,
        stopLoss: stop, takeProfit: target,
        costEstimate: priceCost == null ? null :
          ReplayCostEstimate(roundTripPriceUnits: priceCost));
      final rejection = widget.onRecordSignal?.call(signal);
      if (rejection != null) throw FormatException(rejection);
      setState(() { _signal = signal; _error = null; });
    } on FormatException catch (error) {
      setState(() { _signal = null; _error = error.message.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final colors = Theme.of(context).colorScheme;
    final signal = _signal;
    final observed = signal == null ? null :
      const ReplayObservedTradeTracker().inspect(
        signal: signal, snapshot: snapshot);
    return ListView(key: const Key('lab-observed-trade'),
      padding: const EdgeInsets.all(16), children: [
        const TradeSectionTitle('تسجيل إشارة تدريبية'),
        const Text('ثبّت إشارة عند آخر شمعة ظاهرة. عند العودة للشارت '
          'وتقديم Replay، سيُحسب دخول افتراضي عند افتتاح الشمعة التالية.'),
        const SizedBox(height: 12),
        TradeSurface(child: Row(children: [
          const Icon(Icons.candlestick_chart_outlined,
            color: TradeColors.blue, size: 21),
          const SizedBox(width: 8),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${snapshot.symbol} · ${snapshot.timeframe}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('${snapshot.bars.length} شمعة ظاهرة · آخر إغلاق '
                '${snapshot.bars.last.candle.close}',
                style: Theme.of(context).textTheme.bodySmall),
            ])),
        ])),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          ChoiceChip(label: const Text('شراء'), selected: _side == PaperSide.buy,
            onSelected: (_) {
              _invalidate(); setState(() => _side = PaperSide.buy);
            }),
          ChoiceChip(label: const Text('بيع'), selected: _side == PaperSide.sell,
            onSelected: (_) {
              _invalidate(); setState(() => _side = PaperSide.sell);
            }),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(key: const Key('lab-observed-stop'),
            controller: _stop, textDirection: TextDirection.ltr,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'وقف SL'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(key: const Key('lab-observed-target'),
            controller: _target, textDirection: TextDirection.ltr,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'هدف TP'))),
        ]),
        const SizedBox(height: 10),
        TextField(key: const Key('lab-observed-round-trip-cost'),
          controller: _cost, textDirection: TextDirection.ltr,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'تكلفة الدخول والخروج لكل وحدة (اختيارية)',
            helperMaxLines: 2,
            helperText: 'بعملة تسعير الرمز؛ تشمل ما تقدّره للسبريد والعمولة والانزلاق')),
        const SizedBox(height: 12),
        FilledButton.icon(key: const Key('lab-record-observed-signal'),
          onPressed: _record,
          icon: const Icon(Icons.flag_outlined),
          label: const Text('تسجيل إشارة عند المؤشر الحالي')),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10),
          child: Text(_error!, style: TextStyle(color: colors.error))),
        if (signal != null) ...[
          const SizedBox(height: 16),
          if (widget.onRecordSignal != null)
            const Text('تمت إضافة الإشارة إلى «سجل الجلسة» المحلي.',
              style: TextStyle(color: TradeColors.positive,
                fontWeight: FontWeight.w600)),
          TradeSurface(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              const TradeSectionTitle('نتيجة Replay حتى الموضع الحالي'),
              Text('وقت الإشارة: ${DateTime.fromMillisecondsSinceEpoch(
                  signal.signalTimestamp, isUtc: true).toIso8601String()} UTC',
                style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 10),
              if (observed?.outcome case final outcome?) ...[
                _status(outcome.status),
                if (outcome.entryPrice != null)
                  _row('دخول الشمعة التالية', outcome.entryPrice!.toString()),
                if (outcome.exitPrice != null)
                  _row('سعر الخروج الافتراضي', outcome.exitPrice!.toString()),
                if (outcome.rMultiple != null)
                  _row(outcome.status == ReplayTradeStatus.open
                      ? 'R إجمالي غير محقق' : 'R الإجمالي',
                      outcome.rMultiple!.toStringAsFixed(2)),
                if (outcome.netRMultiple != null)
                  _row(outcome.status == ReplayTradeStatus.open
                      ? 'R صافي تقديري غير محقق' : 'R الصافي التقديري',
                      outcome.netRMultiple!.toStringAsFixed(2)),
                if (outcome.rMultiple != null && outcome.netRMultiple == null)
                  Text('لم تُدخل تكلفة تنفيذ؛ الصافي غير محسوب.',
                    style: Theme.of(context).textTheme.bodySmall),
                if (outcome.ambiguousBar)
                  const Text('وصل الوقف والهدف داخل الشمعة نفسها؛ '
                    'احتُسب الوقف أولًا احترازًا.',
                    style: TextStyle(color: TradeColors.negative)),
              ] else ...[
                Text(observed?.reason ?? 'لا توجد نتيجة متاحة لهذه الإشارة.',
                  style: TextStyle(color: colors.error)),
              ],
            ])),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: widget.onOpenChart,
            icon: const Icon(Icons.skip_next),
            label: const Text('العودة للشارت وتقديم Replay')),
        ],
        const SizedBox(height: 14),
        Text('هذا اختبار وصفي لصفقة واحدة، وليس تنفيذًا حقيقيًا أو '
          'Backtest خارج العينة. النتيجة من شموع OHLC المغلقة الظاهرة '
          'فقط، وتستخدم افتتاح الشمعة التالية. يُعرض الصافي التقديري '
          'فقط إذا أدخلت تكلفة كاملة لكل وحدة من الأصل؛ لا تُجلب تكاليف '
          'التنفيذ الفعلية من الوسيط أو تفاصيل التنفيذ داخل الشمعة. '
          'إذا لامس الوقف والهدف في شمعة واحدة يُفترض الوقف أولًا.',
          style: Theme.of(context).textTheme.bodySmall),
      ]);
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Expanded(child: Text(label)),
      Text(value, textDirection: TextDirection.ltr,
        style: const TextStyle(fontWeight: FontWeight.w800)),
    ]));

  Widget _status(ReplayTradeStatus status) {
    final (label, color) = switch (status) {
      ReplayTradeStatus.pending => ('بانتظار شمعة الدخول', TradeColors.blue),
      ReplayTradeStatus.open => ('مفتوحة افتراضيًا', TradeColors.blue),
      ReplayTradeStatus.stopped => ('ضرب الوقف افتراضيًا', TradeColors.negative),
      ReplayTradeStatus.targeted => ('وصل الهدف افتراضيًا', TradeColors.positive),
    };
    return Padding(padding: const EdgeInsets.only(bottom: 9),
      child: Row(children: [Icon(Icons.circle, color: color, size: 11),
        const SizedBox(width: 7), Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.w800))]));
  }
}
