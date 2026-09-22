part of '../../app_controller.dart';

final class _ProfileRequest {
  _ProfileRequest(this.backend, this.accountId, this.epoch, this.policy);
  final UbaaBackend backend;
  final String accountId;
  final int epoch;
  final RoutePolicy policy;
  final completion = Completer<void>();
}

extension _AppControllerProfile on AppController {
  bool _profileCurrent(
    UbaaBackend backend,
    String accountId,
    int epoch,
    RoutePolicy policy,
  ) =>
      !_disposed &&
      !_isSigningOut &&
      identical(backend, _backend) &&
      epoch == _lifecycleEpoch &&
      _localAccount?.id == accountId &&
      _loginForm.routePolicy == policy &&
      (_phase == AppPhase.home || _phase == AppPhase.loggingIn);

  bool get _hasFreshProfile =>
      _profileDisplayEpoch == _lifecycleEpoch &&
      _profileDisplay != null &&
      _profileDisplay?.profileEvidence?.origin != DataOrigin.persisted;

  Future<void> _restoreCachedProfile(
    UbaaBackend backend,
    LocalAccount account,
    int epoch,
  ) async {
    if (backend is! ProfileCacheBackend) return;
    final policy = _loginForm.routePolicy;
    try {
      final read = await (backend as ProfileCacheBackend).readCachedProfile(
        policy,
      );
      if (!_profileCurrent(backend, account.id, epoch, policy)) return;
      final value = read.profile;
      if (value != null && value.accountId == account.id && !_hasFreshProfile) {
        final display = value.toDisplay();
        _profileDisplay = _profileFailureEpoch == epoch
            ? profileDisplay(
                display,
                display.profileEvidence,
                display.profileRoute,
                notice: '资料暂未更新，保留上次内容',
              )
            : display;
        _profileDisplayEpoch = epoch;
      }
      if (read.error != null && !_hasFreshProfile) _profileFailure(read.error!);
      _notify();
    } on Object catch (error) {
      if (_profileCurrent(backend, account.id, epoch, policy) &&
          !_hasFreshProfile) {
        _profileFailure(error);
        _notify();
      }
    }
  }

  Future<void> _queueProfileRefresh({bool force = false}) {
    final backend = _backend, account = _localAccount;
    if (backend is! ProfileCacheBackend ||
        account == null ||
        _phase != AppPhase.home ||
        _disposed ||
        _isSigningOut ||
        _sessionRecoveryStatus != SessionRecoveryStatus.ready)
      return Future<void>.value();
    final policy = _loginForm.routePolicy, epoch = _lifecycleEpoch;
    final active = _profileRequest;
    if (active != null &&
        identical(active.backend, backend) &&
        active.epoch == epoch &&
        active.policy == policy &&
        active.accountId == account.id)
      return active.completion.future;
    if (!force &&
        _profileRefreshedEpoch == epoch &&
        _profileRefreshedPolicy == policy &&
        _profileRefreshedAt != null &&
        DateTime.now().difference(_profileRefreshedAt!) <
            const Duration(minutes: 5))
      return Future<void>.value();
    final request = _ProfileRequest(backend, account.id, epoch, policy);
    _profileRequest = request;
    unawaited(
      _runProfileRefresh(request, account).whenComplete(() {
        if (identical(_profileRequest, request)) _profileRequest = null;
        request.completion.complete();
      }),
    );
    return request.completion.future;
  }

  Future<void> _runProfileRefresh(
    _ProfileRequest request,
    LocalAccount account,
  ) async {
    bool current() => _profileCurrent(
      request.backend,
      account.id,
      request.epoch,
      request.policy,
    );
    try {
      await _offlineOpenFuture;
      if (!current()) return;
      final result = await _readScheduler.run(
        ReadPriority.background,
        current,
        () => (request.backend as ProfileCacheBackend).refreshProfile(
          account: account,
        ),
      );
      if (!current()) return;
      if (result.evidence.accountId != account.id ||
          (result.profile.username != account.username &&
              result.profile.schoolId != account.username)) {
        await _rejectMismatchedAccount();
        return;
      }
      if (result.evidence.origin != DataOrigin.online ||
          !result.evidence.complete)
        throw const BackendException(UbaaErrorCode.upstreamChanged);
      _profileFailureEpoch = -1;
      _profileDisplay = result.evidence.savedForOffline
          ? result.toDisplay()
          : profileDisplay(
              result.profile,
              result.evidence,
              result.route,
              notice: '本次资料未能保存，仍可查看在线内容',
            );
      _profileDisplayEpoch = request.epoch;
      _profileRefreshedAt = DateTime.now();
      _profileRefreshedEpoch = request.epoch;
      _profileRefreshedPolicy = request.policy;
      _notify();
    } on ReadCancelled {
      /* 退出、路线和实例变化丢弃旧任务。 */
    } on Object catch (error) {
      if (current()) {
        if (error is BackendException && error.accountMismatch) {
          await _rejectMismatchedAccount();
          return;
        }
        _profileFailure(error);
        _notify();
      }
    }
  }

  void _profileFailure(Object error) {
    _recordFailure(error, DiagnosticOperation.read);
    _profileFailureEpoch = _lifecycleEpoch;
    final shown = _profileDisplay ?? _user;
    if (shown != null)
      _profileDisplay = profileDisplay(
        shown,
        shown.profileEvidence,
        shown.profileRoute,
        notice: '资料暂未更新，保留上次内容',
        accountScope: _localAccount?.id,
      );
  }
}
