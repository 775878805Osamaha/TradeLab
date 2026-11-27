/// Persists cTrader authorization and selected-account preferences in strict
/// operation order per secure-storage key. A slow write for account A or an
/// OAuth token rotation must not finish AFTER the user switches to B or logs
/// out, making a stale value the saved account on app restart.
///
/// Awaiting every earlier operation before the subsequent overwrite or
/// delete makes the LAST deliberate action authoritative. No credentials,
/// account numbers or writes are logged from this helper.
class CTraderSerializedSecureValueWriteQueue {
  CTraderSerializedSecureValueWriteQueue(this._write);

  final Future<void> Function(String? value) _write;
  Future<void> _last = Future<void>.value();

  Future<void> persist(String? value) {
    // A failed earlier platform write MUST NOT prevent the next logout from
    // deleting the obsolete token, or block a user-initiated OAuth recovery.
    final next = _last.then<void>(
      (_) => _write(value),
      onError: (Object _, StackTrace __) => _write(value),
    );
    _last = next;
    return next;
  }
}

 
/// Retain the explicit token type used by existing caller/tests. Selected
/// broker preferences use the same tested serialization policy via the
/// generic class above, but store a different secure-storage key.
class CTraderSessionTokenWriteQueue
    extends CTraderSerializedSecureValueWriteQueue {
  CTraderSessionTokenWriteQueue(
      Future<void> Function(String? token) write) : super(write);
}
