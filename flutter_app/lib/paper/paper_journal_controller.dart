import 'dart:async';

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
  bool _disposed = false;
  final Set<Future<void>> _pendingOperations = <Future<void>>{};

  Future<void> _track(Future<void> operation) {
    _pendingOperations.add(operation);
    operation.then<void>((_) {
      _pendingOperations.remove(operation);
    }, onError: (Object _, StackTrace __) {
      _pendingOperations.remove(operation);
    });
    return operation;
  }

  Future<void> useAccount(String? accountId) async {
    if (_disposed) return;
    final key = accountId == null ? 'local:guest' : 'ctrader:$accountId';
    if (key == _accountKey && _revision > 0) return;
    _accountKey = key;
    await refresh();
  }

  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    return _track(_refreshCurrentAccount());
  }

  Future<void> _refreshCurrentAccount() async {
    final revision = ++_revision;
    final key = _accountKey;
    _loading = true;
    error = null;
    entries = const [];
    notifyListeners();
    try {
      final records = await _store.list(key);
      if (!_disposed && revision == _revision) entries = records;
    } catch (_) {
      if (!_disposed && revision == _revision) {
        error = 'تعذر فتح دفتر التداول المحلي. لم تُنشأ بيانات وهمية.';
      }
    } finally {
      if (!_disposed && revision == _revision) {
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
      String scope, Future<void> Function() action) {
    if (_disposed || busy || scope != _accountKey) {
      throw StateError('الدفتر غير جاهز أو تغيّر الحساب.');
    }
    _writing = true;
    notifyListeners();
    return _track(_commit(scope, action));
  }

  Future<void> _commit(
      String scope, Future<void> Function() action) async {
    try {
      try {
        await action();
      } finally {
        // SQLite can commit a row and then lose the acknowledgement. Even
        // if action throws, reload the account's actual database state so a
        // retry cannot be prompted by an incorrectly empty screen.
        if (!_disposed && _accountKey == scope) {
          await refresh();
        }
      }
    } finally {
      _writing = false;
      if (!_disposed) notifyListeners();
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

  Future<void> _closeWhenIdle(List<Future<void>> operations) async {
    for (final operation in operations) {
      try {
        await operation;
      } catch (_) {
        // Failed writes must still finish before the database is closed.
      }
    }
    try {
      await _store.close();
    } catch (_) {
      // A database might never have opened in widget-test hosts.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    // Closing the widget must not interrupt a pending SQLite commit/read.
    // No listener notifications are sent after ChangeNotifier disposal.
    unawaited(_closeWhenIdle(List<Future<void>>.of(_pendingOperations)));
    super.dispose();
  }
}
