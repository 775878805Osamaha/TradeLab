import 'package:flutter/material.dart';

import '../data/tradelab_data.dart';
import 'paper_ledger.dart';
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
  PaperSide _side = PaperSide.buy;
  bool _saving = false;
  String? _error;

  @override
  void dispose() { _units.dispose(); super.dispose(); }

  Future<void> _submit(PreparedPaperQuote prepared) async {
    if (_saving) return;
    final units = double.tryParse(_units.text.trim().replaceAll(',', '.'));
    if (units == null || !units.isFinite || units <= 0) {
      setState(() => _error = 'أدخل كمية موجبة بوحدات الأصل، وليست لوت.');
      return;
    }
    final quotedPrice = prepared.quote.executionPrice(buy: _side == PaperSide.buy);
    final accepted = await showDialog<bool>(context: context, builder: (dialogContext) =>
      AlertDialog(
        title: const Text('تأكيد صفقة تجريبية'),
        content: Text('${_side == PaperSide.buy ? 'شراء' : 'بيع'} '
            '${widget.symbol.code} · $units وحدة عند سعر $quotedPrice\n'
            'هذا تسجيل افتراضي حسب عرض السعر الحالي، وليس تنفيذًا لدى الوسيط. '
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
      await widget.service.open(symbol: widget.symbol, side: _side,
        units: units, prepared: prepared);
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
