import 'package:flutter/material.dart';

import 'paper_journal_controller.dart';
import 'paper_ledger.dart';

/// Only user-entered, closed paper trades; never submits a broker order.
class AddPaperEntrySheet extends StatefulWidget {
  const AddPaperEntrySheet({required this.journal, super.key});
  final PaperJournalController journal;

  @override
  State<AddPaperEntrySheet> createState() => _AddPaperEntrySheetState();
}

class _AddPaperEntrySheetState extends State<AddPaperEntrySheet> {
  LedgerKind _kind = LedgerKind.deposit;
  PaperSide _side = PaperSide.buy;
  String _symbol = 'XAUUSD';
  final _amount = TextEditingController();
  final _quantity = TextEditingController();
  final _entry = TextEditingController();
  final _exit = TextEditingController();
  final _fee = TextEditingController(text: '0');
  DateTime _closedAt = DateTime.now();
  DateTime? _openedAt;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    for (final field in [_amount, _quantity, _entry, _exit, _fee]) {
      field.dispose();
    }
    super.dispose();
  }

  double? _number(TextEditingController field) =>
      double.tryParse(field.text.trim().replaceAll(',', '.'));

  Future<DateTime?> _chooseDateTime(DateTime initial) async {
    final date = await showDatePicker(context: context,
      initialDate: initial, firstDate: DateTime(2000), lastDate: DateTime.now());
    if (date == null || !mounted) { return null; }
    final time = await showTimePicker(context: context,
      initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day,
        time.hour, time.minute);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() { _saving = true; _error = null; });
    try {
      final amount = _number(_amount);
      if (_kind == LedgerKind.withdrawal && amount != null &&
          amount > calculateLedgerReport(widget.journal.entries).closingBalance) {
        throw const FormatException('السحب أكبر من الرصيد المحلي المسجل.');
      }
      if (_closedAt.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
        throw const FormatException('لا يمكن تسجيل قيد بتاريخ مستقبلي.');
      }
      final record = LedgerEntry(
        id: 0, accountKey: widget.journal.accountKey,
        kind: _kind, timestampMs: _closedAt.toUtc().millisecondsSinceEpoch,
        amount: _kind == LedgerKind.closedTrade ? null : amount,
        symbol: _kind == LedgerKind.closedTrade ? _symbol : null,
        side: _kind == LedgerKind.closedTrade ? _side : null,
        quantity: _kind == LedgerKind.closedTrade ? _number(_quantity) : null,
        entryPrice: _kind == LedgerKind.closedTrade ? _number(_entry) : null,
        exitPrice: _kind == LedgerKind.closedTrade ? _number(_exit) : null,
        fee: _kind == LedgerKind.closedTrade ? (_number(_fee) ?? double.nan) : 0,
        openedAtMs: _kind == LedgerKind.closedTrade ? _openedAt?.toUtc().millisecondsSinceEpoch : null,
      );
      record.validate();
      await widget.journal.add(record);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error =
          error is FormatException ? error.message :
          'تعذر حفظ القيد. تحقق من دفتر البيانات وحاول مجددًا.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController field, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: field,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textDirection: TextDirection.ltr,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    ),
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16,
          MediaQuery.viewInsetsOf(context).bottom + 18),
      child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('إضافة قيد إلى دفتر التداول التجريبي',
            style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('دفتر محلي على هذا الهاتف فقط. لا يرسل أوامر إلى cTrader أو Binance، ولا يستورد بيانات تطبيق Android القديم.',
            style: TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final item in const [
              (LedgerKind.deposit, 'إيداع'),
              (LedgerKind.withdrawal, 'سحب'),
              (LedgerKind.closedTrade, 'صفقة مغلقة'),
            ])
              ChoiceChip(label: Text(item.$2), selected: _kind == item.$1,
                onSelected: (_) => setState(() => _kind = item.$1)),
          ]),
          const SizedBox(height: 12),
          if (_kind != LedgerKind.closedTrade)
            _field(_amount, 'المبلغ بالدولار USD'),
          if (_kind == LedgerKind.closedTrade) ...[
            DropdownButtonFormField<String>(
              initialValue: _symbol,
              decoration: const InputDecoration(labelText: 'الرمز (تسعير بالدولار)'),
              items: LedgerEntry.usdQuotedSymbols.map((symbol) =>
                  DropdownMenuItem(value: symbol, child: Text(symbol,
                    textDirection: TextDirection.ltr))).toList(),
              onChanged: (value) => setState(() => _symbol = value ?? _symbol),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('شراء'), selected: _side == PaperSide.buy,
                onSelected: (_) => setState(() => _side = PaperSide.buy)),
              ChoiceChip(label: const Text('بيع'), selected: _side == PaperSide.sell,
                onSelected: (_) => setState(() => _side = PaperSide.sell)),
            ]),
            _field(_quantity, 'الكمية بوحدات الأصل (ليست لوت)'),
            _field(_entry, 'سعر الدخول المسجل'),
            _field(_exit, 'سعر الخروج المسجل'),
            _field(_fee, 'إجمالي رسوم الصفقة بالدولار (أدخلها إن وجدت)'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('وقت الدخول (اختياري)'),
              subtitle: Text(_openedAt?.toLocal().toString().substring(0, 16) ??
                  'غير محدد · لن تُحسب مدة الصفقة'),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () async {
                final time = await _chooseDateTime(_openedAt ?? _closedAt);
                if (time != null && mounted) setState(() => _openedAt = time);
              },
            ),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_kind == LedgerKind.closedTrade ? 'وقت إغلاق الصفقة' : 'تاريخ القيد'),
            subtitle: Text(_closedAt.toLocal().toString().substring(0, 16)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: () async {
              final time = await _chooseDateTime(_closedAt);
              if (time != null && mounted) setState(() => _closedAt = time);
            },
          ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving ? const SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
            label: const Text('حفظ القيد المحلي'),
          ),
        ],
      )),
    ),
  );
}
