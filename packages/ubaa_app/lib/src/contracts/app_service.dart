import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/telemetry.dart';

/// 应用服务能力独立于学校读写；本地状态和队列由 Core 持有。
abstract interface class AppServiceBackend {
  Future<AppServiceView> appServiceState();
  Future<AppServiceView> agreeAppService();
  Future<AppServiceView> enterBasicAppService();
  Future<AppServiceView> setAppServiceTelemetry(bool enabled);
  Future<AppServiceEraseOutcome> eraseAppService();
  Future<void> uploadAppService({required bool force});
  Future<void> recordAppService(TelemetryRecord record);
}

/// 仅在登录、恢复或匹配的离线资料确认账号后调用。
abstract interface class ConfirmedAppServiceAccountBackend {
  void confirmAppServiceAccount();
  void clearAppServiceAccount();
}
