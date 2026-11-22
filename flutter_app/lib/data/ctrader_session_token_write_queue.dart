/// Persists cTrader's *current* authorized session in strict operation
/// order. An HTTP token rotation may still be writing to Android secure
/// storage when the user disconnects or finishes a new OAuth flow.
///
/// Awaiting every earlier write before the later delete/re-link prevents an
/// old slow write from reviving a stale credential after logout. No secrets
/// are logged, replayed or exposed in callback errors.
class CTraderSessionTokenWriteQueue {
  CTraderSessionTokenWriteQueue(this._write);

  final Future<void> Function(String? token) _write;
  Future<void> _last = Future<void>.value();

  Future<void> persist(String? token) {
    // A failed earlier platform write MUST NOT prevent the next logout from
    // deleting the obsolete token, or block a user-initiated OAuth recovery.
    final next = _last.then<void>(
      (_) => _write(token),
      onError: (Object _, StackTrace __) => _write(token),
    );
    _last = next;
    return next;
  }
}
