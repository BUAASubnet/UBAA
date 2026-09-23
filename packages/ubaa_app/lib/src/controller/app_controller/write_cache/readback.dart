part of '../../app_controller.dart';

final class _WriteReadbackRead {
  _WriteReadbackRead(this.epoch, this.revision);
  final int epoch, revision;
  final completion = Completer<void>();
}

extension _AppControllerWriteReadbacks on AppController {
  bool _readbackCurrent(UbaaBackend backend, String account, int epoch) =>
      !_disposed &&
      !_isSigningOut &&
      _phase == AppPhase.home &&
      epoch == _lifecycleEpoch &&
      identical(_backend, backend) &&
      _localAccount?.id == account;

  Future<void> _loadWriteReadbacks({bool force = false}) {
    final backend = _backend,
        account = _localAccount?.id,
        epoch = _lifecycleEpoch;
    if (backend is! WriteReadbackBackend ||
        account == null ||
        !_readbackCurrent(backend, account, epoch))
      return Future.value();
    if (!force &&
        _writeReadbackLoadedEpoch == epoch &&
        _writeReadbackError == null)
      return Future.value();
    // 提交后的强制重读不能加入提交前的旧读取并丢掉刚保存的提示。
    if (force) _writeReadbackRevision++;
    final pending = _writeReadbackRead;
    if (pending != null &&
        pending.epoch == epoch &&
        pending.revision == _writeReadbackRevision)
      return pending.completion.future;
    final request = _WriteReadbackRead(epoch, _writeReadbackRevision);
    _writeReadbackRead = request;
    unawaited(() async {
      bool current() =>
          _readbackCurrent(backend, account, epoch) &&
          request.revision == _writeReadbackRevision;
      try {
        await _offlineOpenFuture;
        if (!current()) return;
        final values = await (backend as WriteReadbackBackend)
            .readWriteReadbackHints(accountId: account);
        if (!current()) return;
        _writeReadbacks = List.unmodifiable(values);
        _writeReadbackLoadedEpoch = epoch;
        _writeReadbackError = null;
      } on Object catch (error, stackTrace) {
        if (current())
          _writeReadbackError = _recordFailure(
            error,
            DiagnosticOperation.read,
            stackTrace: stackTrace,
          );
      } finally {
        if (identical(_writeReadbackRead, request)) _writeReadbackRead = null;
        request.completion.complete();
        if (current()) _notify();
      }
    }());
    return request.completion.future;
  }

  Future<void> _dismissControllerReadback(String id) async {
    final backend = _backend,
        account = _localAccount?.id,
        epoch = _lifecycleEpoch;
    if (backend is! WriteReadbackBackend ||
        account == null ||
        !_readbackCurrent(backend, account, epoch) ||
        _writeTransitions != 0 ||
        _writeCoordinator.hasPendingOperation ||
        _clearingBusinessCache ||
        !_writeReadbacks.any((hint) => hint.id == id)) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
    await (backend as WriteReadbackBackend).dismissWriteReadbackHint(
      id,
      accountId: account,
    );
    if (!_readbackCurrent(backend, account, epoch)) return;
    _writeReadbackRevision++;
    _writeReadbacks = _writeReadbacks
        .where((hint) => hint.id != id)
        .toList(growable: false);
    _writeReadbackError = null;
    _notify();
  }

  void _clearWriteReadbacks() {
    _writeReadbackRevision++;
    _writeReadbackLoadedEpoch = -1;
    _writeReadbacks = const [];
    _writeReadbackError = null;
    _writeReadbackRead = null;
  }
}
