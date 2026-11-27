import 'dart:developer' as developer;
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

/// The caller serializes opens using MarketCandleStore._opening.
/// No concurrent external process/isolate writers are supported.
abstract final class MarketCandleMigrationBackup {
  static const retainedAfterSuccess = 3;
  static String directoryFor(String filename) =>
      path.join(path.dirname(filename), path.basename(filename) + '.migration-backups');
  static Future<String> _hash(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  static Future<void> _requireQuiescent(String filename) async {
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final sidecar = File(filename + suffix);
      if (await sidecar.exists() && await sidecar.length() != 0) {
        throw StateError('Nonempty SQLite sidecar: $suffix; refusing unsafe copy');
      }
    }
  }

  static Future<int> _inspectAndClose(String filename, int target) async {
    // No version: may recover a hot journal, but cannot run a migration.
    final db = await openDatabase(filename, singleInstance: false);
    try {
      final version = await db.getVersion();
      if (version < 1 || version > target) {
        throw StateError('Unexpected archive schema version $version');
      }
      if (version < target) {
        final mode = (await db.rawQuery('PRAGMA journal_mode')).single.values.single;
        if (mode.toString().toLowerCase() == 'wal') {
          final row = (await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)')).single;
          if ((row['busy'] as num?) != 0) {
            throw StateError('SQLite WAL checkpoint did not finish');
          }
        }
        final check = await db.rawQuery('PRAGMA quick_check');
        if (check.length != 1 || check.single.values.single != 'ok') {
          throw StateError('SQLite pre-upgrade integrity check failed');
        }
      }
      return version;
    } finally { await db.close(); }
  }

  static Future<File> _copyVerified(File source, String target, String expected) async {
    final temp = File(target + '.partial');
    if (await temp.exists() || await File(target).exists()) {
      throw StateError('Backup destination already exists');
    }
    try {
      await source.copy(temp.path);
      final handle = await temp.open(mode: FileMode.append);
      try { await handle.flush(); } finally { await handle.close(); }
      if (await _hash(temp) != expected || await _hash(source) != expected) {
        throw StateError('SQLite backup byte verification failed');
      }
      return await temp.rename(target);
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  static Future<void> _restore(File backup, String filename, String expected) async {
    // sqflite closes a failed open before propagating its error.
    // Never delete WAL/journal to force recovery.
    await _requireQuiescent(filename);
    if (await _hash(backup) != expected) {
      throw StateError('Migration backup failed SHA-256 verification');
    }
    final staging = filename + '.migration-restore-' +
        DateTime.now().microsecondsSinceEpoch.toString();
    final copy = await _copyVerified(backup, staging, expected);
    try {
      await _requireQuiescent(filename);
      // Same-filesystem replacement on Android/Linux; original backup retained.
      await copy.rename(filename);
      if (await _hash(File(filename)) != expected) {
        throw StateError('Restored archive SHA-256 differs');
      }
    } finally {
      if (await copy.exists()) await copy.delete();
    }
  }

  static Future<void> _prune(String directory) async {
    final pattern = RegExp(r'^v\d+-to-v\d+-\d+\.sqlite$');
    final files = <File>[];
    await for (final item in Directory(directory).list(followLinks: false)) {
      if (item is File && pattern.hasMatch(path.basename(item.path))) files.add(item);
    }
    int time(File f) => int.parse(path.basename(f.path).split('-').last.split('.').first);
    files.sort((a,b)=>time(b).compareTo(time(a)));
    for (final old in files.skip(retainedAfterSuccess)) { await old.delete(); }
  }

  static Future<Database> open({
    required String filename,
    required int targetVersion,
    required Future<Database> Function() openTarget,
  }) async {
    final source = File(filename);
    if (!await source.exists()) return openTarget();
    final version = await _inspectAndClose(filename, targetVersion);
    if (version == targetVersion) return openTarget();
    await _requireQuiescent(filename);
    final directory = directoryFor(filename);
    await Directory(directory).create(recursive: true);
    final expected = await _hash(source);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final backup = await _copyVerified(source,
      path.join(directory, 'v$version-to-v$targetVersion-$stamp.sqlite'), expected);
    await _requireQuiescent(filename);
    if (await _hash(source) != expected) {
      throw StateError('Archive changed after snapshot; refusing migration');
    }
    final Database opened;
    try {
      opened = await openTarget();
    } catch (error, stack) {
      try {
        await _restore(backup, filename, expected);
      } catch (restoreError) {
        throw StateError('SQLite upgrade failed: $error; automatic restore failed: '
            '$restoreError. Verified snapshot retained at ' + backup.path);
      }
      // Never report restored v1 as a successfully opened v2.
      Error.throwWithStackTrace(error, stack);
    }
    // Preserve all snapshots on failure. Cleanup must not invalidate v2.
    try { await _prune(directory); }
    catch (error, stack) {
      developer.log('Backup retention cleanup failed',
        name: 'MarketCandleMigrationBackup', error: error, stackTrace: stack);
    }
    return opened;
  }
}
