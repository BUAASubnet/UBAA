part of '../../app_controller.dart';

extension AppControllerLockDisplay on AppController {
  Future<CgyyLockDisplaySession> openLockDisplay() async {
    _lockDisplay?.cancel();
    final request = ++_lockDisplayGeneration;
    final backend = _backend;
    final epoch = _lifecycleEpoch;
    bool current() =>
        !_disposed &&
        _appForeground &&
        !_interactiveEngaged &&
        _phase == AppPhase.home &&
        _user != null &&
        _writeTransitions == 0 &&
        _sessionRecoveryStatus != SessionRecoveryStatus.needsLogin &&
        (!_usesLocalRecovery ||
            _sessionRecoveryStatus == SessionRecoveryStatus.ready) &&
        request == _lockDisplayGeneration &&
        epoch == _lifecycleEpoch &&
        identical(backend, _backend);
    if (!current() || backend is! CgyyLockDisplayBackend) {
      throw const BackendException(UbaaErrorCode.authenticationRequired);
    }
    final session = await (backend as CgyyLockDisplayBackend).openLockDisplay();
    if (!current()) {
      session.cancel();
      throw const BackendException(UbaaErrorCode.authenticationRequired);
    }
    return _lockDisplay = _GuardedLockDisplaySession(session, current);
  }
}

class _GuardedLockDisplaySession implements CgyyLockDisplaySession {
  _GuardedLockDisplaySession(this.inner, this.isCurrent);
  final CgyyLockDisplaySession inner;
  final bool Function() isCurrent;
  bool _closed = false;
  CgyyLockDisplay? _last;
  @override
  Stream<void> get cancelled => inner.cancelled;
  void validate() {
    if (!isCurrent()) cancel();
  }

  @override
  Future<CgyyLockDisplay> read() async {
    validate();
    if (_closed)
      throw const BackendException(UbaaErrorCode.authenticationRequired);
    final value = await inner.read();
    validate();
    if (_closed) {
      value.release();
      throw const BackendException(UbaaErrorCode.authenticationRequired);
    }
    _last?.release();
    return _last = value;
  }

  @override
  void cancel() {
    if (_closed) return;
    _closed = true;
    _last?.release();
    _last = null;
    inner.cancel();
  }
}
