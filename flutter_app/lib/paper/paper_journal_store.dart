import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'paper_ledger.dart';

abstract class PaperJournalStore {
  Future<List<LedgerEntry>> list(String accountKey);
  Future<void> add(LedgerEntry entry);
  Future<void> delete(String accountKey, int id);
  Future<void> close();
}

/// App-private SQLite: not the Kotlin app's Room file and not a broker sync.
class SqlitePaperJournalStore implements PaperJournalStore {
  Future<Database>? _opening;

  Future<Database> get _database => _opening ??= _open();

  Future<Database> _open() async {
    final directory = await getDatabasesPath();
    return openDatabase(path.join(directory, 'tradelab_flutter_paper_v1.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE ledger_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            account_key TEXT NOT NULL,
            kind TEXT NOT NULL,
            timestamp_ms INTEGER NOT NULL,
            amount REAL,
            symbol TEXT,
            side TEXT,
            quantity REAL,
            entry_price REAL,
            exit_price REAL,
            fee REAL NOT NULL DEFAULT 0,
            opened_at_ms INTEGER
          )
        ''');
        await db.execute('CREATE INDEX ledger_account_time '
            'ON ledger_entries(account_key, timestamp_ms, id)');
      });
  }

  @override
  Future<List<LedgerEntry>> list(String accountKey) async {
    final db = await _database;
    final rows = await db.query('ledger_entries',
      where: 'account_key = ?', whereArgs: [accountKey],
      orderBy: 'timestamp_ms ASC, id ASC');
    return rows.map((row) => LedgerEntry(
      id: row['id'] as int,
      accountKey: row['account_key'] as String,
      kind: LedgerKind.values.byName(row['kind'] as String),
      timestampMs: row['timestamp_ms'] as int,
      amount: (row['amount'] as num?)?.toDouble(),
      symbol: row['symbol'] as String?,
      side: row['side'] == null ? null : PaperSide.values.byName(row['side'] as String),
      quantity: (row['quantity'] as num?)?.toDouble(),
      entryPrice: (row['entry_price'] as num?)?.toDouble(),
      exitPrice: (row['exit_price'] as num?)?.toDouble(),
      fee: (row['fee'] as num).toDouble(),
      openedAtMs: row['opened_at_ms'] as int?,
    )).toList(growable: false);
  }

  @override
  Future<void> add(LedgerEntry entry) async {
    entry.validate();
    final db = await _database;
    await db.insert('ledger_entries', {
      'account_key': entry.accountKey,
      'kind': entry.kind.name,
      'timestamp_ms': entry.timestampMs,
      'amount': entry.amount,
      'symbol': entry.symbol,
      'side': entry.side?.name,
      'quantity': entry.quantity,
      'entry_price': entry.entryPrice,
      'exit_price': entry.exitPrice,
      'fee': entry.fee,
      'opened_at_ms': entry.openedAtMs,
    });
  }

  @override
  Future<void> delete(String accountKey, int id) async {
    final db = await _database;
    await db.delete('ledger_entries',
      where: 'account_key = ? AND id = ?', whereArgs: [accountKey, id]);
  }

  @override
  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) {
      try { await (await opening).close(); }
      catch (_) { /* The database may not exist in widget-test hosts. */ }
    }
  }
}
