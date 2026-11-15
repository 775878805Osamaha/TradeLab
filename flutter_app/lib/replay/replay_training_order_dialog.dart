import 'package:flutter/material.dart';

import 'replay_training_session.dart';

/// The dialog owns its controllers until the route is actually disposed.
/// This avoids disposing TextEditingController during the reverse animation.
typedef ReplayPracticeOrder = ({
  ReplaySide side,
  double quantity,
  double? stopLoss,
  double? takeProfit,
});

class ReplayTrainingOrderDialog extends StatefulWidget {
  const ReplayTrainingOrderDialog({required this.entryPrice, super.key});

  final double entryPrice;

  @override
  State<ReplayTrainingOrderDialog> createState() =>
      _ReplayTrainingOrderDialogState();
}

class _ReplayTrainingOrderDialogState extends State<ReplayTrainingOrderDialog> {
  final _quantity = TextEditingController(text: '1');
  final _stop = TextEditingController();
  final _target = TextEditingController();
  ReplaySide _side = ReplaySide.buy;
  String? _error;

  static double? _parsePrice(String raw) =>
      double.tryParse(raw.trim().replaceAll(',', '.'));

  @override
  void dispose() {
    _quantity.dispose();
    _stop.dispose();
    _target.dispose();
    super.dispose();
  }

  void _confirm() {
    final price = widget.entryPrice;
    final q = _parsePrice(_quantity.text);
    final stopText = _stop.text.trim();
    final targetText = _target.text.trim();
    final sl = stopText.isEmpty ? null : _parsePrice(stopText);
    final tp = targetText.isEmpty ? null : _parsePrice(targetText);

    if (!price.isFinite || price <= 0 ||
        q == null || !q.isFinite || q <= 0 || q > 1000000 ||
        (stopText.isNotEmpty && (sl == null || !sl.isFinite || sl <= 0)) ||
        (targetText.isNotEmpty && (tp == null || !tp.isFinite || tp <= 0))) {
      setState(() => _error = 'أدخل كمية وأسعارًا موجبة وصحيحة.');
      return;
    }
    final invalidStop = sl != null && (_side == ReplaySide.buy
        ? sl >= price : sl <= price);
    final invalidTarget = tp != null && (_side == ReplaySide.buy
        ? tp <= price : tp >= price);
    if (invalidStop || invalidTarget) {
      setState(() => _error =
          'يجب أن يكون الوقف في جهة الخسارة والهدف في جهة الربح.');
      return;
    }
    Navigator.pop<ReplayPracticeOrder>(
      context,
      (side: _side, quantity: q, stopLoss: sl, takeProfit: tp),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('صفقة تدريب داخل Replay'),
    content: SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('تدريب محلي فقط، لا يُرسل أمرًا إلى وسيط أو دفتر التداول.'),
        Text('سعر آخر شمعة مكشوفة: ${widget.entryPrice.toStringAsFixed(5)}'),
        DropdownButton<ReplaySide>(
          key: const Key('replay-trade-side'),
          value: _side,
          items: const [
            DropdownMenuItem(value: ReplaySide.buy, child: Text('شراء')),
            DropdownMenuItem(value: ReplaySide.sell, child: Text('بيع')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _side = value);
          },
        ),
        TextField(
          key: const Key('replay-trade-quantity'),
          controller: _quantity,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'الكمية التدريبية'),
        ),
        TextField(
          key: const Key('replay-trade-stop'),
          controller: _stop,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'وقف الخسارة (اختياري)'),
        ),
        TextField(
          key: const Key('replay-trade-target'),
          controller: _target,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'الهدف (اختياري)'),
        ),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
      ]),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        key: const Key('replay-trade-confirm'),
        onPressed: _confirm,
        child: const Text('فتح صفقة تدريب'),
      ),
    ],
  );
}
