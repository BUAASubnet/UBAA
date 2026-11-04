import 'dart:async';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'backend.dart';
import 'package:ubaa_platform/shared_accounts.dart';
import 'recovery.dart';

/// 当前消费者已核实的本机身份与许可。代次由组合根维护。
final class RecoveryScope {
  const RecoveryScope({
    required this.accountAlias,
    required this.expectedUsername,
    required int accountGeneration,
    required this.routeGeneration,
    required this.backendGeneration,
    required this.credentialGeneration,
    required this.routePolicy,
    required this.allowAutomaticLogin,
    required bool Function() isCurrent,
    PersistentRecoveryScope? persistent,
  }) : _accountGeneration = accountGeneration,
       _isCurrent = isCurrent,
       _persistent = persistent;

  /// 只能从安全索引捕获身份和许可，调用者不能用裸 alias 构造持久作用域。
  static Future<RecoveryScope> capture({
    required SecureLocalAccountStore accounts,
    LocalAccountSnapshot? snapshot,
    required int routeGeneration,
    required int backendGeneration,
    required int credentialGeneration,
    required RoutePolicy routePolicy,
    required bool allowAutomaticLogin,
    required bool Function() isCurrent,
  }) async {
    snapshot ??= await accounts.capture();
    if (!isCurrent() ||
        snapshot == null ||
        !snapshot.state.canRestore ||
        snapshot.state.account == null) {
      throw const RecoveryInterrupted(RecoveryStopReason.superseded);
    }
    final account = snapshot.state.account!;
    return RecoveryScope(
      accountAlias: account.id,
      expectedUsername: account.username,
      accountGeneration: snapshot.state.generation,
      routeGeneration: routeGeneration,
      backendGeneration: backendGeneration,
      credentialGeneration: credentialGeneration,
      routePolicy: routePolicy,
      allowAutomaticLogin: allowAutomaticLogin,
      isCurrent: isCurrent,
      persistent: PersistentRecoveryScope._(accounts, snapshot),
    );
  }

  final PersistentRecoveryScope? _persistent;
  bool get isShared => _persistent != null;
  LocalAccountSnapshot? get sharedSnapshot => _persistent?.snapshot;
  Future<void> validateSharedState() async {
    final persistent = _persistent;
    if (persistent != null &&
        !await persistent.accounts.validate(persistent.snapshot)) {
      throw const RecoveryInterrupted(RecoveryStopReason.superseded);
    }
  }

  Future<void> validatePersistent() async {
    if (!isCurrent ||
        (_persistent != null &&
            !await _persistent.accounts.validate(_persistent.snapshot))) {
      throw const RecoveryInterrupted(RecoveryStopReason.superseded);
    }
    if (!isCurrent)
      throw const RecoveryInterrupted(RecoveryStopReason.superseded);
  }

  Future<T> coordinateRecovery<T>(
    Future<T> Function() action,
    bool Function() active,
  ) async {
    final persistent = _persistent;
    if (persistent == null) return action();
    return persistent.accounts.materials.coordinator.recovery(
      action,
      isCurrent: active,
    );
  }

  /// 仅在恢复操作锁内的客户端重建边界调用。学校写资格不得使用此续接接口。
  Future<bool> adoptRecoverySuccessor() async {
    final persistent = _persistent;
    if (persistent == null) return false;
    final next = await persistent.accounts.recoverySuccessor(
      persistent.snapshot,
    );
    final changed =
        next.state.generation != persistent.snapshot.state.generation;
    persistent.snapshot = next;
    return changed;
  }

  /// 被拒凭据只撤销提交时的快照；旧失败不能取得新快照再撤销许可。
  Future<void> revokeRejectedCredentials() async {
    final persistent = _persistent;
    if (persistent != null) {
      try {
        await persistent.accounts.revokeIfCurrent(persistent.snapshot);
      } on LocalAccountConflict {
        throw const RecoveryInterrupted(RecoveryStopReason.superseded);
      }
    }
  }

  Future<SharedAccountBinding?> sharedBinding() async {
    final persistent = _persistent;
    return persistent == null
        ? null
        : persistent.accounts.bindSnapshot(persistent.snapshot);
  }

  Future<void> publishRecovery() async {
    final persistent = _persistent;
    if (persistent != null)
      persistent.snapshot = await persistent.accounts.refreshIfCurrent(
        persistent.snapshot,
      );
  }

  Future<void> commitDelivery(void Function() deliver) async {
    final persistent = _persistent;
    if (persistent == null) {
      if (isCurrent)
        deliver();
      else
        throw const RecoveryInterrupted(RecoveryStopReason.superseded);
    } else {
      await persistent.accounts.commitIfCurrent(persistent.snapshot, () {
        if (!isCurrent)
          throw const RecoveryInterrupted(RecoveryStopReason.superseded);
        deliver();
      });
    }
  }

  final String accountAlias;
  final String expectedUsername;
  final int _accountGeneration;
  int get accountGeneration =>
      _persistent?.snapshot.state.generation ?? _accountGeneration;
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
    _accountGeneration,
    routeGeneration,
    backendGeneration,
    credentialGeneration,
    routePolicy,
    allowAutomaticLogin,
  );
  Object get credentialKey =>
      (accountAlias, _accountGeneration, credentialGeneration);
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
  const RecoveryResult(
    this.session,
    this.disposition, {
    this.scope,
    this.backend,
  });
  final RecoveryScope? scope;
  final RequiredSessionBackend? backend;
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

/// 持久绑定只由 RecoveryScope.capture 创建，代次变更只用于恢复继任。
final class PersistentRecoveryScope {
  PersistentRecoveryScope._(this.accounts, this.snapshot);
  final SecureLocalAccountStore accounts;
  LocalAccountSnapshot snapshot;
}

/// 完整恢复目标沿用相同的期限、取消和单次控制柄。
abstract interface class ControlledRequiredTargetSessionBackend
    implements ControlledRequiredSessionBackend, RequiredTargetSessionBackend {
  RequiredRecoveryOperation startTargetRecovery(
    RecoveryTarget target,
    Duration limit,
  );
}
