import 'package:flutter/material.dart';

import '../paper/paper_ledger.dart';
import '../theme/tradelab_theme.dart';
import '../widgets/trade_components.dart';
import 'replay_session_study.dart';
import 'replay_trade_evaluator.dart';

/// Purely local analysis of signals recorded in the current Replay session.
class ReplaySessionLogPanel extends StatelessWidget {
  const ReplaySessionLogPanel({required this.report,
    required this.onOpenRecorder, required this.onClear, super.key});

  final ReplaySessionReport report;
  final VoidCallback onOpenRecorder;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (report.rows.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.bookmarks_outlined, size: 40, color: TradeColors.blue),
          const SizedBox(height: 10),
          Text('لا توجد إشارات مسجلة في هذه الجلسة',
            style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text('سجّل إشارة من قسم «متابعة إشارة» ثم قدّم Replay '
            'لرؤية نتيجة افتراضية مبنية على الشموع الظاهرة فقط.',
            textAlign: TextAlign.center),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: onOpenRecorder,
            icon: const Icon(Icons.add_chart), label: const Text('تسجيل إشارة')),
        ])));
    }
    return ListView(key: const Key('replay-session-log'),
      padding: const EdgeInsets.all(16), children: [
        Row(children: [
          const Expanded(child: TradeSectionTitle('سجل الجلسة التدريبية')),
          OutlinedButton.icon(key: const Key('replay-session-clear'),
            onPressed: () => _confirmClear(context),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('مسح السجل')),
        ]),
        const SizedBox(height: 8),
        TradeSurface(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            _summary('الإشارات / المحسومة',
              '${report.rows.length} / ${report.finished}'),
            _summary('النجاح الإجمالي (R موجب)', report.winRate == null
              ? '—' : '${report.winRate!.toStringAsFixed(1)}%'),
            _summary('مجموع R الإجمالي المحقق',
              report.totalGrossR.toStringAsFixed(2)),
            _summary('مجموع R الصافي التقديري', report.totalNetR == null
              ? 'غير محسوب لكل الصفقات' : report.totalNetR!.toStringAsFixed(2)),
            _summary('أقصى تراجع في مجموع R الإجمالي',
              report.maxDrawdownR.toStringAsFixed(2)),
            _summary('معلّقة / مفتوحة / غير متاحة',
              '${report.pending} / ${report.open} / ${report.unavailable}'),
          ])),
        const SizedBox(height: 14),
        for (var i = 0; i < report.rows.length; i++) ...[
          _signalRow(context, report.rows[i], i),
          const SizedBox(height: 9),
        ],
        const SizedBox(height: 10),
        const Text('هذه إحصاءات وصفية لإشارات مسجلة يدويًا أثناء Replay، '
          'وليست اختبارًا خارج العينة أو سجل تنفيذ. مجموع R ليس رصيدًا '
          'بالدولار ولا منحنى رأس مال، ولا يُحتسب الصافي إلا إذا وُضعت '
          'تكلفة تقديرية لكل صفقة محسومة. الإشارات غير المتاحة تُستبعد '
          'من الإحصاءات؛ لا توجد أي أوامر أو حفظ في دفتر التداول.'),
      ]);
  }

  Widget _summary(String title, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Expanded(child: Text(title)),
      const SizedBox(width: 8),
      Flexible(child: Text(value, textDirection: TextDirection.ltr,
        style: const TextStyle(fontWeight: FontWeight.w700))),
    ]));

  Widget _signalRow(BuildContext context, ReplaySessionRow row, int index) {
    final outcome = row.result.outcome;
    final isBuy = row.signal.side == PaperSide.buy;
    final status = outcome == null
      ? 'غير متاحة' : switch (outcome.status) {
        ReplayTradeStatus.pending => 'بانتظار الدخول',
        ReplayTradeStatus.open => 'مفتوحة افتراضيًا',
        ReplayTradeStatus.stopped => 'وقف افتراضي',
        ReplayTradeStatus.targeted => 'هدف افتراضي',
      };
    return TradeSurface(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${index + 1}. ${isBuy ? 'شراء' : 'بيع'} '
              '· $status', style: const TextStyle(fontWeight: FontWeight.w800))),
          Text(isBuy ? 'BUY' : 'SELL',
            style: TextStyle(color: isBuy ? TradeColors.positive : TradeColors.negative)),
        ]),
        const SizedBox(height: 4),
        Text(DateTime.fromMillisecondsSinceEpoch(row.signal.signalTimestamp,
            isUtc: true).toIso8601String(),
          style: Theme.of(context).textTheme.labelSmall),
        if (outcome?.rMultiple != null)
          _summary(outcome!.status == ReplayTradeStatus.open
              ? 'R إجمالي غير محقق' : 'R الإجمالي',
            outcome.rMultiple!.toStringAsFixed(2)),
        if (outcome?.netRMultiple != null)
          _summary(outcome!.status == ReplayTradeStatus.open
              ? 'R صافي تقديري غير محقق' : 'R الصافي التقديري',
            outcome.netRMultiple!.toStringAsFixed(2)),
        if (row.result.reason != null)
          Text(row.result.reason!,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ]));
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(context: context,
      builder: (_) => AlertDialog(
        title: const Text('مسح سجل Replay؟'),
        content: const Text('سيُحذف سجل الإشارات التدريبية من هذه الجلسة '
          'فقط. لن تتغير الشموع أو صفقات الدفتر المحلي.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('مسح الإشارات')),
        ],
      ));
    if (confirmed == true && context.mounted) onClear();
  }
}
