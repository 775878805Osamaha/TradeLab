import 'package:flutter/material.dart';

import '../data/tradelab_data.dart';
import 'paper_ledger.dart';
import 'paper_risk_engine.dart';
import 'paper_trade_service.dart';

class PaperOrderSheet extends StatefulWidget {
  const PaperOrderSheet({required this.symbol, required this.service, super.key});

  final TradeSymbol symbol;
  final PaperTradeService service;

  @override
  State<PaperOrderSheet> createState() => _PaperOrderSheetState();
}

class _PaperOrderSheetState extends State<PaperOrderSheet> {
  late Future<PreparedPaperQuote> _quote = widget.service.prepare(widget.symbol);
  final _units = TextEditingController(text: '1');
  final _stopLoss = TextEditingController();
  final _takeProfit = TextEditingController();
  final _riskUsd = TextEditingController();
  final _dailyLimitUsd = TextEditingController();
  PaperSide _side = PaperSide.buy;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _units.dispose();
    _stopLoss.dispose();
    _takeProfit.dispose();
    _riskUsd.dispose();
    _dailyLimitUsd.dispose();
    super.dispose();
  }

  double? _parse(TextEditingController field) =>
      double.tryParse(field.text.trim().replaceAll(',', '.'));

  ({double stop, double target, PaperRiskLimits limits}) _riskInputs() {
    final stop = _parse(_stopLoss);
    final target = _parse(_takeProfit);
    final maxLoss = _parse(_riskUsd);
    final dailyText = _dailyLimitUsd.text.trim();
    final dailyLimit = dailyText.isEmpty ? null : _parse(_dailyLimitUsd);
    if (stop == null || target == null || maxLoss == null ||
        (dailyText.isNotEmpty && dailyLimit == null)) {
      throw const FormatException('أدخل وقف الخسارة والهدف وأقصى خسارة للصفقة بالدولار.');
    }
    return (stop: stop, target: target,
      limits: PaperRiskLimits(maxLossPerTradeUsd: maxLoss,
        maxDailyLossUsd: dailyLimit));
  }

  void _suggestUnits(PreparedPaperQuote prepared) {
    try {
      final fields = _riskInputs();
      final assessment = widget.service.assessRisk(symbol: widget.symbol,
        side: _side, stopLoss: fields.stop, takeProfit: fields.target,
        limits: fields.limits, prepared: prepared);
      if (!assessment.allowed) throw StateError(assessment.reasons.join(' '));
      setState(() {
        _units.text = assessment.maxUnits.toString();
        _error = null;
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  Future<void> _submit(PreparedPaperQuote prepared) async {
    if (_saving) return;
    final units = _parse(_units);
    if (units == null || !units.isFinite || units <= 0) {
      setState(() => _error = 'أدخل كمية موجبة بوحدات الأصل، وليست لوت.');
      return;
    }
    late final ({double stop, double target, PaperRiskLimits limits}) fields;
    late final PaperRiskAssessment assessment;
    try {
      fields = _riskInputs();
      assessment = widget.service.assessRisk(symbol: widget.symbol,
        side: _side, stopLoss: fields.stop, takeProfit: fields.target,
        limits: fields.limits, prepared: prepared, units: units);
      if (!assessment.allowed) throw StateError(assessment.reasons.join(' '));
    } catch (error) {
      setState(() => _error = error.toString());
      return;
    }
    final quotedPrice = prepared.quote.executionPrice(buy: _side == PaperSide.buy);
    final accepted = await showDialog<bool>(context: context, builder: (dialogContext) =>
      AlertDialog(
        title: const Text('تأكيد صفقة تجريبية'),
        content: Text('${_side == PaperSide.buy ? 'شراء' : 'بيع'} '
            '${widget.symbol.code} · $units وحدة عند سعر $quotedPrice\n'
            'وقف: ${fields.stop} · هدف: ${fields.target}\n'
            'مخاطرة محسوبة: ${assessment.riskUsd.toStringAsFixed(2)} USD'
            ' · عائد/مخاطرة: ${assessment.rewardRisk.toStringAsFixed(2)}\n'
            'هذا تسجيل افتراضي حسب عرض السعر الحالي، وليس تنفيذًا لدى الوسيط. '
            'مستويات الوقف والهدف مرجعية فقط ولا تُنفذ تلقائيًا. '
            'السبريد محسوب، لكن الانزلاق والعمولات والرافعة غير مُحاكاة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('فتح تجريبي')),
        ],
      ));
    if (accepted != true || !mounted) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.service.openRiskManaged(symbol: widget.symbol, side: _side,
        units: units, prepared: prepared,
        stopLoss: fields.stop, takeProfit: fields.target, limits: fields.limits);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('حُفظ المركز التجريبي في دفتر الهاتف.')));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 16,
          MediaQuery.viewInsetsOf(context).bottom + 18),
      child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('تداول تجريبي · ${widget.symbol.code}',
            style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 7),
          const Text('يُستخدم السعر الحقيقي للعرض فقط. لا يتم إرسال أي أوامر إلى cTrader أو Binance.',
            style: TextStyle(fontSize: 12)),
          const SizedBox(height: 14),
          FutureBuilder<PreparedPaperQuote>(future: _quote,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: Padding(padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator()));
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return Column(children: [
                  Text('تعذر جلب BID/ASK حديث: ${snapshot.error ?? 'لا توجد بيانات'}',
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  TextButton.icon(onPressed: () => setState(() => _quote =
                      widget.service.prepare(widget.symbol)),
                    icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
                ]);
              }
              final prepared = snapshot.data!;
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text('BID: ${prepared.quote.bid}',
                    textDirection: TextDirection.ltr, textAlign: TextAlign.center)),
                  Expanded(child: Text('ASK: ${prepared.quote.ask}',
                    textDirection: TextDirection.ltr, textAlign: TextAlign.center)),
                ]),
                const SizedBox(height: 10),
                Wrap(spacing: 8, children: [
                  ChoiceChip(label: const Text('شراء'), selected: _side == PaperSide.buy,
                    onSelected: (_) => setState(() => _side = PaperSide.buy)),
                  ChoiceChip(label: const Text('بيع'), selected: _side == PaperSide.sell,
                    onSelected: (_) => setState(() => _side = PaperSide.sell)),
                ]),
                const SizedBox(height: 10),
                TextField(controller: _units,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(), labelText: 'الكمية بوحدات الأصل (ليست لوت)')),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: _stopLoss,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(border: OutlineInputBorder(),
                      labelText: 'وقف الخسارة SL'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _takeProfit,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(border: OutlineInputBorder(),
                      labelText: 'الهدف TP'))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: _riskUsd,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(border: OutlineInputBorder(),
                      labelText: 'أقصى خسارة للصفقة USD'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _dailyLimitUsd,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(border: OutlineInputBorder(),
                      labelText: 'حد الخسارة اليومي UTC (اختياري)'))),
                ]),
                Align(alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _saving ? null : () => _suggestUnits(prepared),
                    icon: const Icon(Icons.calculate_outlined),
                    label: const Text('احسب الكمية حسب الرصيد والمخاطرة'))),
                const SizedBox(height: 12),
                if (_error != null) Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
                FilledButton.icon(onPressed: _saving ? null : () => _submit(prepared),
                  icon: const Icon(Icons.add_chart), label: const Text('فتح صفقة تجريبية')),
              ]);
            }),
        ])),
    ),
  );
}
