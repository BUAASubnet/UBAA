/// 当前安装的隐私政策选择。
enum AppServiceConsent { unasked, agreed, reconsentRequired, basic }

/// pending 表示 Core 仍保留删除标记，等待重试。
enum AppServiceEraseStatus { idle, running, pending }

enum AppServiceEraseOutcome { succeeded, pending, unavailable }

/// Core 持久化状态的只读投影。统计开关值与硬关闭分开显示。
final class AppServiceView {
  const AppServiceView({
    required this.available,
    required this.telemetryAllowed,
    required this.consent,
    required this.policyVersion,
    required this.agreedPolicyVersion,
    required this.telemetryEnabled,
    required this.canErase,
    required this.erase,
  });

  const AppServiceView.unavailable(this.policyVersion)
    : available = false,
      telemetryAllowed = false,
      consent = AppServiceConsent.unasked,
      agreedPolicyVersion = null,
      telemetryEnabled = false,
      canErase = false,
      erase = AppServiceEraseStatus.idle;

  final bool available;
  final bool telemetryAllowed;
  final AppServiceConsent consent;
  final int policyVersion;
  final int? agreedPolicyVersion;
  final bool telemetryEnabled;
  final bool canErase;
  final AppServiceEraseStatus erase;

  bool get needsConsentPrompt =>
      available &&
      (consent == AppServiceConsent.unasked ||
          consent == AppServiceConsent.reconsentRequired);

  AppServiceView withEraseStatus(AppServiceEraseStatus status) =>
      AppServiceView(
        available: available,
        telemetryAllowed: telemetryAllowed,
        consent: consent,
        policyVersion: policyVersion,
        agreedPolicyVersion: agreedPolicyVersion,
        telemetryEnabled: telemetryEnabled,
        canErase: canErase,
        erase: status,
      );

  Object get _fields => (
    available,
    telemetryAllowed,
    consent,
    policyVersion,
    agreedPolicyVersion,
    telemetryEnabled,
    canErase,
    erase,
  );

  @override
  bool operator ==(Object other) =>
      other is AppServiceView && _fields == other._fields;

  @override
  int get hashCode => _fields.hashCode;
}
