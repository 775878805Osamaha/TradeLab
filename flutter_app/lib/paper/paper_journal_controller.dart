import 'package:flutter/foundation.dart';

import 'paper_journal_store.dart';
import 'paper_ledger.dart';

class PaperJournalController extends ChangeNotifier {
  PaperJournalController({required PaperJournalStore store}) : _store = store;

  final PaperJournalStore _store;
  String _accountKey = 'local:guest';
  String get accountKey => _accountKey;
  List<LedgerEntry> entries = const [];
  bool _loading = false;
  bool _writing = false;
  /// True for a pending SQLite read OR write, including a post-write refresh.
  bool get busy => _loading || _writing;
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
    _loading = true;
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
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Locks journal writes from their first synchronous step through the
  /// committed local readback. A second tap cannot insert two identical
  /// practice positions or race a close/delete against the first write.
  ///
  /// An account switch is allowed while SQLite finishes its already-started
  /// operation. The operation remains scoped to the ORIGINAL account, and
  /// must not refresh an unrelated account after the write completes.
  Future<void> _writeForAccount(
      String scope, Future<void> Function() action) async {
    if (busy || scope != _accountKey) {
      throw StateError('الدفتر غير جاهز أو تغيّر الحساب.');
    }
    _writing = true;
    notifyListeners();
    try {
      await action();
      if (_accountKey == scope) {
        await refresh();
      }
    } finally {
      _writing = false;
      notifyListeners();
    }
  }

  Future<void> add(LedgerEntry entry) async {
    entry.validate();
    await _writeForAccount(entry.accountKey, () => _store.add(entry));
  }

  Future<void> delete(int id) async {
    if (id <= 0) throw const FormatException('معرّف القيد غير صالح.');
    final scope = _accountKey;
    await _writeForAccount(scope, () => _store.delete(scope, id));
  }

  Future<void> closeTrade(LedgerEntry position,
      {required double exitPrice, required int timestampMs}) async {
    if (position.accountKey != _accountKey ||
        position.kind != LedgerKind.openTrade) {
      throw StateError('المركز ليس مفتوحًا في الدفتر الحالي.');
    }
    if (timestampMs < position.timestampMs || exitPrice <= 0 ||
        !exitPrice.isFinite) {
      throw const FormatException('سعر الخروج أو تاريخه غير صالح.');
    }
    final scope = position.accountKey;
    await _writeForAccount(scope, () => _store.closeTrade(scope, position.id,
        exitPrice: exitPrice, timestampMs: timestampMs));
  }

  @override
  void dispose() {
    _revision++;
    // Database closure can complete after the widget has left the tree.
    _store.close().catchError((Object _) {});
    super.dispose();
  }
}
