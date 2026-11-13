import 'dart:async';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../../contracts/backend.dart';
import '../../contracts/routing.dart';
import 'retry.dart' show controllerTemporaryRecoveryFailure;
import '../state/state.dart';
import '../state/types.dart';

/// 换网的固定期限覆盖探测、会话恢复及原查询重读。
mixin ControllerNetworkRecovery on ControllerState {
  bool _networkWakeScheduled = false;
  @override
  void internalHandleNetworkChange({required bool online}) {
    if (internalDisposed || internalIsSigningOut || !internalAppForeground)
      return;
    if (internalBackend is! NetworkChangeBackend) {
      internalNetworkOnline = online;
      if (online && !_networkWakeScheduled) {
        _networkWakeScheduled = true;
        scheduleMicrotask(() {
          _networkWakeScheduled = false;
          if (internalNetworkOnline) internalWakeNetworkRecovery();
        });
      }
      internalNotify();
      return;
    }
    final recover =
        internalNetworkFailure != null ||
        internalSessionRecoveryStatus == SessionRecoveryStatus.ready ||
        internalSessionRecoveryStatus == SessionRecoveryStatus.restoring ||
        controllerTemporaryRecoveryFailure(internalError);
    final revision = ++internalNetworkRevision;
    final old = internalNetworkOperation;
    internalNetworkDeadlineTimer?.cancel();
    final previousReady = internalNetworkReady;
    if (previousReady != null && !previousReady.isCompleted)
      previousReady.complete();
    final ready = internalNetworkReady = Completer<void>();
    internalNetworkOnline = online;
    internalNetworkChecking = true;
    internalNetworkFailure = null;
    const budget = Duration(seconds: 30);
    internalNetworkDeadline = DateTime.now().add(budget);
    try {
      internalNetworkOperation = switch (internalBackend) {
        final NetworkChangeBackend backend => backend.beginNetworkChange(
          online: online,
          budget: budget,
        ),
        _ => null,
      };
      if (internalBackend case final NetworkChangeBackend backend
          when internalLoginForm.routePolicy != RoutePolicy.auto) {
        backend.cancelNetworkReads();
      }
    } on Object catch (error) {
      internalNetworkOperation = null;
      _failNetwork(revision, error);
      return;
    }
    old?.finish();
    _restartNetworkReads(includeWebvpn: !online);
    for (final service in internalRequiredRecoveryServices.values) {
      service.validateScopes();
    }
    if (internalPhase != AppPhase.home) {
      internalNetworkOperation?.finish();
      internalNetworkChecking = false;
      internalNetworkDeadline = null;
      ready.complete();
      internalNotify();
      return;
    }
    internalNetworkDeadlineTimer = Timer(budget, () {
      _failNetwork(
        revision,
        const BackendException(UbaaErrorCode.timeout, retryable: false),
      );
    });
    internalNotify();
    // 同一轮通知只启动最后一个观察；已开始的旧观察也不能覆盖新状态。
    if (online)
      scheduleMicrotask(() {
        if (_networkCurrent(revision))
          unawaited(
            _recoverNetwork(revision, internalNetworkOperation, recover),
          );
      });
  }

  bool _networkCurrent(int revision) =>
      !internalDisposed &&
      !internalIsSigningOut &&
      revision == internalNetworkRevision;

  void _restartNetworkReads({required bool includeWebvpn}) {
    for (final scope in internalReadScopes) {
      if (scope.valid &&
          !scope.writeReadback &&
          (includeWebvpn || scope.route != ConnectionMode.webvpn)) {
        scope.restartRequested = true;
        scope.task?.cancel();
      }
    }
  }

  Future<void> _recoverNetwork(
    int revision,
    NetworkChangeOperation? operation,
    bool recover,
  ) async {
    try {
      final network = internalLoginForm.routePolicy == RoutePolicy.auto
          ? await operation?.inspect()
          : null;
      if (!_networkCurrent(revision) || internalNetworkFailure != null) return;
      if (!recover ||
          internalAutomaticCredentialBlocked ||
          internalSessionRecoveryStatus == SessionRecoveryStatus.needsLogin) {
        internalNetworkChecking = false;
        internalNetworkDeadlineTimer?.cancel();
        internalNetworkDeadlineTimer = null;
        internalNetworkDeadline = null;
        operation?.finish();
        internalNetworkOperation = null;
        if (internalNetworkReady case final ready? when !ready.isCompleted)
          ready.complete();
        return;
      }
      if (network != BackendNetworkState.campus) {
        _restartNetworkReads(includeWebvpn: true);
      }
      await internalRecoverSession(forceConnectionCheck: true);
      if (!_networkCurrent(revision) || internalNetworkFailure != null) return;
      if (internalUsesLocalRecovery &&
          internalSessionRecoveryStatus != SessionRecoveryStatus.ready) {
        throw internalError == null
            ? const BackendException(
                UbaaErrorCode.authenticationRequired,
                retryable: false,
              )
            : BackendException.fromUi(internalError!);
      }
      internalNetworkChecking = false;
      if (internalNetworkReady case final ready? when !ready.isCompleted)
        ready.complete();
      internalWakeNetworkRecovery();
      internalPumpReadTasks();
      await Future<void>.delayed(Duration.zero);
      if (!_networkCurrent(revision)) return;
      final reads = internalReadScopes
          .where((scope) => scope.valid && !scope.writeReadback)
          .map((scope) => scope.completion.future)
          .toList();
      reads.addAll(internalServiceReads.map((read) => read.future));
      final remaining = internalNetworkDeadline!.difference(DateTime.now());
      await Future.wait(
        reads,
      ).timeout(remaining.isNegative ? Duration.zero : remaining);
      if (!_networkCurrent(revision) || internalNetworkFailure != null) return;
      operation?.finish();
      internalNetworkDeadlineTimer?.cancel();
      internalNetworkDeadlineTimer = null;
      internalNetworkDeadline = null;
      internalNetworkOperation = null;
    } on Object catch (error) {
      _failNetwork(revision, error);
    } finally {
      if (_networkCurrent(revision)) internalNotify();
    }
  }

  void _failNetwork(int revision, Object error) {
    if (!_networkCurrent(revision)) return;
    internalNetworkOperation?.cancel();
    internalNetworkOperation = null;
    internalNetworkDeadlineTimer?.cancel();
    internalNetworkDeadlineTimer = null;
    internalNetworkChecking = false;
    internalNetworkFailure = error is BackendException
        ? error
        : const BackendException(UbaaErrorCode.timeout, retryable: false);
    for (final service in internalRequiredRecoveryServices.values) {
      service.validateScopes();
    }
    if (internalNetworkReady case final ready? when !ready.isCompleted)
      ready.complete();
    if (internalPhase == AppPhase.home &&
        internalSessionRecoveryStatus != SessionRecoveryStatus.needsLogin) {
      internalSessionRecoveryStatus = SessionRecoveryStatus.unavailable;
      internalError = internalRecordFailure(
        internalNetworkFailure!,
        DiagnosticOperation.initialization,
      );
    }
    internalPumpReadTasks();
    internalNotify();
  }

  @override
  Future<void> internalAwaitNetworkReady() async {
    while (internalNetworkChecking) {
      final ready = internalNetworkReady;
      if (ready == null) break;
      await ready.future;
    }
    if (internalNetworkFailure case final error?) throw error;
    if (!internalNetworkOnline)
      throw const BackendException(
        UbaaErrorCode.networkError,
        retryable: false,
      );
  }

  @override
  void internalCancelNetworkChange() {
    internalNetworkRevision++;
    internalNetworkOperation?.cancel();
    internalNetworkOperation = null;
    internalNetworkDeadlineTimer?.cancel();
    internalNetworkDeadlineTimer = null;
    internalNetworkChecking = false;
    internalNetworkDeadline = null;
    internalNetworkFailure = null;
    if (internalNetworkReady case final ready? when !ready.isCompleted)
      ready.complete();
  }
}
