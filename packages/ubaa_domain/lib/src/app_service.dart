/// 当前安装的隐私政策选择。
enum AppServiceConsent { unasked, agreed, reconsentRequired, basic }

/// pending 表示 Core 仍保留删除标记，等待重试。
enum AppServiceEraseStatus { idle, running, pending }

enum AppServiceEraseOutcome { succeeded, pending, unavailable }

enum AppUpdateStatus { upToDate, updateAvailable, updateRequired, unknown }

/// 启动配置和共享门控记录在当前安装上的投影。
final class AppUpdateView {
  const AppUpdateView({
    required this.status,
    this.latestVersion,
    this.minSupportedVersion,
    this.url,
    this.releaseNotes,
    required this.gateActive,
    required this.availableDismissed,
  });

  final AppUpdateStatus status;
  final String? latestVersion;
  final String? minSupportedVersion;
  final Uri? url;
  final String? releaseNotes;
  final bool gateActive;
  final bool availableDismissed;

  Object get _fields => (
    status,
    latestVersion,
    minSupportedVersion,
    url,
    releaseNotes,
    gateActive,
    availableDismissed,
  );

  @override
  bool operator ==(Object other) =>
      other is AppUpdateView && _fields == other._fields;

  @override
  int get hashCode => _fields.hashCode;
}

enum AppAnnouncementLevel { popup, banner }

final class AppAnnouncement {
  const AppAnnouncement({
    required this.id,
    required this.level,
    required this.title,
    required this.body,
    this.linkUrl,
    this.linkText,
    this.confirmText,
    required this.startsAt,
    this.endsAt,
  });

  final String id;
  final AppAnnouncementLevel level;
  final String title;
  final String body;
  final Uri? linkUrl;
  final String? linkText;
  final String? confirmText;
  final DateTime startsAt;
  final DateTime? endsAt;

  Object get _fields => (
    id,
    level,
    title,
    body,
    linkUrl,
    linkText,
    confirmText,
    startsAt,
    endsAt,
  );

  @override
  bool operator ==(Object other) =>
      other is AppAnnouncement && _fields == other._fields;

  @override
  int get hashCode => _fields.hashCode;
}

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
    this.update,
    this.announcements = const [],
  });

  const AppServiceView.unavailable(this.policyVersion)
    : available = false,
      telemetryAllowed = false,
      consent = AppServiceConsent.unasked,
      agreedPolicyVersion = null,
      telemetryEnabled = false,
      canErase = false,
      erase = AppServiceEraseStatus.idle,
      update = null,
      announcements = const [];

  final bool available;
  final bool telemetryAllowed;
  final AppServiceConsent consent;
  final int policyVersion;
  final int? agreedPolicyVersion;
  final bool telemetryEnabled;
  final bool canErase;
  final AppServiceEraseStatus erase;
  final AppUpdateView? update;
  final List<AppAnnouncement> announcements;

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
        update: update,
        announcements: announcements,
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
    update,
  );

  @override
  bool operator ==(Object other) =>
      other is AppServiceView &&
      _fields == other._fields &&
      announcements.length == other.announcements.length &&
      Iterable<int>.generate(
        announcements.length,
      ).every((index) => announcements[index] == other.announcements[index]);

  @override
  int get hashCode => Object.hash(_fields, Object.hashAll(announcements));
}
