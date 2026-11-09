import 'package:flutter/material.dart';

import '../data/market_api.dart';
import '../paper/paper_ledger.dart';
import 'replay_cost_estimate.dart';
import 'replay_scenario_analyzer.dart';

class ReplayAnalysisSheet extends StatefulWidget {
  const ReplayAnalysisSheet({required this.bars, required this.symbol,
    required this.timeframe, super.key});

  /// Already truncated by the chart at the Replay cursor. No future bars.
  final List<MarketBar> bars;
  final String symbol;
  final String timeframe;

  @override
  State<ReplayAnalysisSheet> createState() => _ReplayAnalysisSheetState();
}

class _ReplayAnalysisSheetState extends State<ReplayAnalysisSheet> {
  final _stop = TextEditingController();
  final _target = TextEditingController();
  final _horizon = TextEditingController(text: '20');
  final _cost = TextEditingController();
  PaperSide _side = PaperSide.buy;
  ReplayScenarioResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final controller in [_stop, _target, _horizon, _cost]) {
      controller.addListener(_invalidateResult);
    }
  }

  void _invalidateResult() {
    if (mounted && (_result != null || _error != null)) {
      setState(() { _result = null; _error = null; });
    }
  }

  @override
  void dispose() {
    _stop.dispose();
    _target.dispose();
    _horizon.dispose();
    _cost.dispose();
    super.dispose();
  }

  void _run() {
    try {
      double? parse(TextEditingController value) =>
          double.tryParse(value.text.trim().replaceAll(',', '.'));
      final stop = parse(_stop);
      final target = parse(_target);
      final horizon = int.tryParse(_horizon.text.trim());
      final costText = _cost.text.trim();
      final roundTripCost = costText.isEmpty ? null :
          double.tryParse(costText.replaceAll(',', '.'));
      if (stop == null || target == null || horizon == null) {
        throw const FormatException('أدخل وقف الخسارة والهدف وعدد الشموع بشكل صحيح.');
      }
      if (costText.isNotEmpty && roundTripCost == null) {
        throw const FormatException('أدخل تكلفة تنفيذ رقمية صالحة.');
      }
      final result = const ReplayScenarioAnalyzer().simulate(
        sourceBars: widget.bars, visibleThrough: widget.bars.length,
        side: _side, stopLoss: stop,
        takeProfit: target, horizonBars: horizon,
        costEstimate: roundTripCost == null ? null :
          ReplayCostEstimate(roundTripPriceUnits: roundTripCost));
      setState(() { _result = result; _error = null; });
    } on FormatException catch (error) {
      setState(() { _result = null; _error = error.message.toString(); });
    } catch (_) {
      setState(() { _result = null;
        _error = 'تعذر تحليل الشموع الظاهرة؛ تحقق من القيم وبيانات المصدر.'; });
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16,
        MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('تحليل Replay · ${widget.symbol}',
            style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text('${widget.timeframe} · ${widget.bars.length} شمعة ظاهرة مغلقة'
              ' · سعر المرجع ${widget.bars.last.candle.close}',
            style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            ChoiceChip(label: const Text('شراء'), selected: _side == PaperSide.buy,
              onSelected: (_) => setState(() {
                _side = PaperSide.buy; _result = null; _error = null;
              })),
            ChoiceChip(label: const Text('بيع'), selected: _side == PaperSide.sell,
              onSelected: (_) => setState(() {
                _side = PaperSide.sell; _result = null; _error = null;
              })),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _stop,
              textDirection: TextDirection.ltr,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(border: OutlineInputBorder(),
                labelText: 'وقف الخسارة SL'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _target,
              textDirection: TextDirection.ltr,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(border: OutlineInputBorder(),
                labelText: 'الهدف TP'))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: _horizon, textDirection: TextDirection.ltr,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(border: OutlineInputBorder(),
              labelText: 'أفق المحاكاة بالشموع')),
          const SizedBox(height: 10),
          TextField(key: const Key('replay-scenario-round-trip-cost'),
            controller: _cost, textDirection: TextDirection.ltr,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(border: OutlineInputBorder(),
              labelText: 'تكلفة الدخول والخروج لكل وحدة (اختيارية)',
              helperMaxLines: 2,
              helperText: 'بعملة تسعير الرمز؛ تكلفة تقديرية شاملة')),
          const SizedBox(height: 10),
          FilledButton.icon(key: const Key('run-replay-analysis'),
            onPressed: _run, icon: const Icon(Icons.analytics_outlined),
            label: const Text('محاكاة 1000 مسار تاريخي')),
          if (_error != null) Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (_result != null) ...[
            const SizedBox(height: 12),
            Text('الهدف أولًا: ${_result!.targetProbability.toStringAsFixed(1)}%'
                ' · الوقف أولًا: ${_result!.stopProbability.toStringAsFixed(1)}%'),
            Text('دون لمس أي مستوى: ${_result!.neitherProbability.toStringAsFixed(1)}%'),
            Text('متوسط R: ${_result!.meanR.toStringAsFixed(3)}'
                ' · نطاق 5–95%: ${_result!.fifthPercentileR.toStringAsFixed(2)}'
                ' إلى ${_result!.ninetyFifthPercentileR.toStringAsFixed(2)}'),
            if (_result!.netMeanR != null)
              Text('متوسط R الصافي التقديري: '
                  '${_result!.netMeanR!.toStringAsFixed(3)}'
                  ' · نطاق 5–95%: '
                  '${_result!.netFifthPercentileR!.toStringAsFixed(2)}'
                  ' إلى ${_result!.netNinetyFifthPercentileR!.toStringAsFixed(2)}'),
            if (_result!.netMeanR == null)
              Text('لم تُدخل تكلفة تنفيذ؛ الصافي غير محسوب.',
                style: Theme.of(context).textTheme.bodySmall),
            Text('العينة: ${_result!.visibleBars} شمعة فقط · البذرة: ${_result!.seed}',
              style: Theme.of(context).textTheme.labelSmall),
          ],
          const SizedBox(height: 10),
          const Text('محاكاة بحثية من شموع OHLC الأصلية الظاهرة فقط (حتى عند عرض Heikin Ashi)، '
              'وليست تنبؤًا أو نتيجة '
              'Backtest خارج العينة. الأرقام إجمالية ما لم تُدخل تكلفة تقديرية '
              'تشمل السبريد والعمولة والانزلاق لكل وحدة أصل. '
              'لا تُنفَّذ أي صفقة.', style: TextStyle(fontSize: 12)),
        ],
      )),
    ),
  );
}
