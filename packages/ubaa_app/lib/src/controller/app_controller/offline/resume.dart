part of '../../app_controller.dart';

extension _AppControllerDeferredRecovery on AppController {
  Future<void> _deferRecovery() {
    final pending = _deferredRecovery ??= Completer<void>();
    return pending.future;
  }

  bool get _recoveryMustWait =>
      !_appForeground ||
      isLoggingIn ||
      _writeTransitions != 0 ||
      _writeCoordinator.hasPendingOperation;

  void _cancelDeferredRecovery() {
    final pending = _deferredRecovery;
    _deferredRecovery = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  void _drainDeferredRecovery() {
    if (_deferredRecovery == null || _deferredRecoveryScheduled) return;
    if (_disposed || _isSigningOut || _phase == AppPhase.login) {
      _cancelDeferredRecovery();
      return;
    }
    if (_phase != AppPhase.home || _recoveryMustWait) return;
    _deferredRecoveryScheduled = true;
    scheduleMicrotask(() {
      _deferredRecoveryScheduled = false;
      if (_disposed || _isSigningOut || _phase != AppPhase.home) {
        _cancelDeferredRecovery();
        return;
      }
      if (_recoveryMustWait) return;
      final pending = _deferredRecovery;
      if (pending == null) return;
      _deferredRecovery = null;
      unawaited(
        _recoverSession().then(
          (_) {
            if (!pending.isCompleted) pending.complete();
          },
          onError: (Object error, StackTrace stack) {
            if (!pending.isCompleted) pending.completeError(error, stack);
          },
        ),
      );
    });
  }
}
