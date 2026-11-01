import 'dart:async';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'backend.dart';
import 'recovery.dart';

/// 当前消费者已核实的本机身份与许可。代次由组合根维护。
final class RecoveryScope {
  const RecoveryScope({
    required this.accountAlias,
    required this.expectedUsername,
    required this.accountGeneration,
    required this.routeGeneration,
    required this.backendGeneration,
    required this.credentialGeneration,
    required this.routePolicy,
    required this.allowAutomaticLogin,
    required bool Function() isCurrent,
  }) : _isCurrent = isCurrent;
  final String accountAlias;
  final String expectedUsername;
  final int accountGeneration;
  final int routeGeneration;
  final int backendGeneration;
  final int credentialGeneration;
  final RoutePolicy routePolicy;
  final bool allowAutomaticLogin;
  final bool Function() _isCurrent;
  bool get isCurrent => _isCurrent();

  Object get key => (
    accountAlias,
    expectedUsername,
    accountGeneration,
    routeGeneration,
    backendGeneration,
    credentialGeneration,
    routePolicy,
    allowAutomaticLogin,
  );
  Object get credentialKey =>
      (accountAlias, accountGeneration, credentialGeneration);
  bool accepts(UserSummary profile) =>
      profile.username == expectedUsername ||
      profile.schoolId == expectedUsername;
  bool acceptsRoute(ConnectionMode route) => switch (routePolicy) {
    RoutePolicy.auto => true,
    RoutePolicy.direct => route == ConnectionMode.direct,
    RoutePolicy.webvpn => route == ConnectionMode.webvpn,
  };
  @override
  String toString() => 'RecoveryScope([REDACTED])';
}

enum RecoveryDisposition { reused, reauthenticated }

final class RecoveryResult {
  const RecoveryResult(this.session, this.disposition);
  final RecoveredRouteSession session;
  final RecoveryDisposition disposition;
}

enum RecoveryStopReason { cancelled, deadline, superseded, closed }

final class RecoveryInterrupted extends BackendException {
  const RecoveryInterrupted(this.reason)
    : super(
        reason == RecoveryStopReason.deadline
            ? UbaaErrorCode.timeout
            : UbaaErrorCode.operationConflict,
        retryable: false,
      );
  final RecoveryStopReason reason;
}

/// 取消只属于一个消费者，不代表注销共享账号。
final class RecoveryCancellation {
  bool _cancelled = false;
  final _listeners = <void Function()>{};
  bool get isCancelled => _cancelled;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in _listeners.toList()) {
      listener();
    }
    _listeners.clear();
  }

  void Function() listen(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

/// 一个底层操作的管理柄。完成后释放，取消与释放分别表达。
abstract interface class RequiredRecoveryOperation {
  Future<RecoveredRouteSession> get result;
  void cancel();
  void dispose();
}

abstract interface class ControlledRequiredSessionBackend
    implements RequiredSessionBackend {
  RequiredRecoveryOperation startRequiredRecovery(
    FeatureId feature,
    Duration limit,
  );
  RequiredRecoveryOperation startRequiredLogin(
    ConnectionMode route,
    LoginInput input,
    Duration limit,
  );
}

/// 关闭的有界等待结果；尚未返回的材料或同步 I/O 继续由服务保管。
final class RecoveryCloseResult {
  const RecoveryCloseResult(this.pendingOperations);
  final int pendingOperations;
  bool get settled => pendingOperations == 0;
}
