import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/ctrader_session_token_write_queue.dart';

void main() {
  test('a late old token write cannot overtake newer OAuth re-link', () async {
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final completed = <String?>[];
    var activeWrites = 0;
    var maxConcurrent = 0;
    final store = CTraderSessionTokenWriteQueue((token) async {
      activeWrites++;
      if (activeWrites > maxConcurrent) maxConcurrent = activeWrites;
      if (token == 'old-rotation') {
        firstStarted.complete();
        await releaseFirst.future;
      }
      completed.add(token);
      activeWrites--;
    });

    final old = store.persist('old-rotation');
    await firstStarted.future;
    final newlyAuthorized = store.persist('new-oauth-grant');
    expect(activeWrites, 1);
    expect(completed, isEmpty,
        reason: 'New grant must not race an in-flight secure write');
    releaseFirst.complete();
    await Future.wait([old, newlyAuthorized]);
    expect(maxConcurrent, 1);
    expect(completed, ['old-rotation', 'new-oauth-grant']);
    expect(completed.last, 'new-oauth-grant');
  });

  test('logout deletion always happens after a pending token rotation', () async {
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final persisted = <String?>[];
    String? activeToken;
    final store = CTraderSessionTokenWriteQueue((token) async {
      if (token == 'slow-rotation') {
        firstStarted.complete();
        await releaseFirst.future;
      }
      activeToken = token;
      persisted.add(token);
    });
    final rotating = store.persist('slow-rotation');
    await firstStarted.future;
    final logout = store.persist(null);
    releaseFirst.complete();
    await Future.wait([rotating, logout]);
    expect(persisted, ['slow-rotation', null]);
    expect(activeToken, isNull,
        reason: 'A delayed rotation must not restore logout credentials');
  });

  test('failed secure write does not prevent later logout or re-login',
      () async {
    final committed = <String?>[];
    final store = CTraderSessionTokenWriteQueue((token) async {
      if (token == 'rejected-write') {
        throw StateError('secure storage unavailable');
      }
      committed.add(token);
    });
    final rejected = expectLater(store.persist('rejected-write'),
        throwsStateError);
    final cleared = store.persist(null);
    final reauthorized = store.persist('recovered-authorization');
    await rejected;
    await Future.wait([cleared, reauthorized]);
    expect(committed, [null, 'recovered-authorization']);
  });
}
