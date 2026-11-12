import 'package:ubaa_domain/ubaa_domain.dart';
import '../../contracts/session_recovery.dart';
import 'types.dart';

/// 一次恢复的结果；界面状态只在结果交付时发布。
sealed class ControllerRecoveryResult {
  const ControllerRecoveryResult();
  SessionRecoveryStatus get status;
  UiError? get error;
  bool get transientFailure;

  /// 单功能暂不可用保留已就绪的主会话，重试收尾复用相同投影。
  ({SessionRecoveryStatus status, UiError? error}) forSession({
    required bool targetOnly,
  }) => targetOnly && status == SessionRecoveryStatus.unavailable
      ? (status: SessionRecoveryStatus.ready, error: null)
      : (status: status, error: error);
}

final class ControllerRecoveredSession extends ControllerRecoveryResult {
  const ControllerRecoveredSession(this.profile, this.deliveryScope);
  final UserSummary profile;
  final RecoveryScope? deliveryScope;
  @override
  SessionRecoveryStatus get status => SessionRecoveryStatus.ready;
  @override
  UiError? get error => null;
  @override
  bool get transientFailure => false;
}

final class ControllerRecoveryStopped extends ControllerRecoveryResult {
  const ControllerRecoveryStopped(
    this.status, {
    this.error,
    this.transientFailure = false,
  });
  @override
  final SessionRecoveryStatus status;
  @override
  final UiError? error;
  @override
  final bool transientFailure;
}

/// 恢复结果转交人工验证；交付后由交互认证持有新的状态。
final class ControllerRecoveryVerification extends ControllerRecoveryResult {
  const ControllerRecoveryVerification(this.input, this.route);
  final LoginInput input;
  final ConnectionMode route;
  @override
  SessionRecoveryStatus get status => SessionRecoveryStatus.needsLogin;
  @override
  UiError? get error => null;
  @override
  bool get transientFailure => false;
}
