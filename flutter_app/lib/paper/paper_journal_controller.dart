import 'package:flutter/foundation.dart';

import 'paper_journal_store.dart';
import 'paper_ledger.dart';

class PaperJournalController extends ChangeNotifier {
  PaperJournalController({required PaperJournalStore store}) : _store = store;

  final PaperJournalStore _store;
  String _accountKey = 'local:guest';
  String get accountKey => _accountKey;
  List<LedgerEntry> entries = const [];
  bool busy = false;
  String? error;
  int _revision = 0;

  Future<void> useAccount(String? accountId) async {
    final key = accountId == null ? 'local:guest' : 'ctrader:$accountId';
    if (key == _accountKey && _revision > 0) return;
    _accountKey = key;
    await refresh();
  }

  Future<void> refresh() async {
    final revision = ++_revision;
    final key = _accountKey;
    busy = true;
    error = null;
    entries = const [];
    notifyListeners();
    try {
      final records = await _store.list(key);
      if (revision == _revision) entries = records;
    } catch (_) {
      if (revision == _revision) error = 'تعذر فتح دفتر التداول المحلي. لم تُنشأ بيانات وهمية.';
    } finally {
      if (revision == _revision) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> add(LedgerEntry entry) async {
    if (busy || entry.accountKey != _accountKey) {
      throw StateError('الدفتر غير جاهز أو تغيّر الحساب.');
    }
    entry.validate();
    await _store.add(entry);
    await refresh();
  }

  Future<void> delete(int id) async {
    if (busy) throw StateError('انتظر حتى يكتمل تحميل الدفتر.');
    await _store.delete(_accountKey, id);
    await refresh();
  }

  Future<void> closeTrade(LedgerEntry position,
      {required double exitPrice, required int timestampMs}) async {
    if (busy || position.accountKey != _accountKey ||
        position.kind != LedgerKind.openTrade) {
      throw StateError('المركز ليس مفتوحًا في الدفتر الحالي.');
    }
    if (timestampMs < position.timestampMs || exitPrice <= 0 ||
        !exitPrice.isFinite) {
      throw const FormatException('سعر الخروج أو تاريخه غير صالح.');
    }
    await _store.closeTrade(_accountKey, position.id,
      exitPrice: exitPrice, timestampMs: timestampMs);
    await refresh();
  }

  @override
  void dispose() {
    _revision++;
    // Database closure can complete after the widget has left the tree.
    _store.close().catchError((Object _) {});
    super.dispose();
  }
}
