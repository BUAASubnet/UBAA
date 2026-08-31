import 'package:meta/meta.dart';

/// 路由策略。Auto 由 Rust Core 根据可达性和会话状态解析。
enum RoutePolicy { auto, direct, webvpn }

extension RoutePolicyText on RoutePolicy {
  String get label => switch (this) {
    RoutePolicy.auto => '自动',
    RoutePolicy.direct => '直连',
    RoutePolicy.webvpn => 'WebVPN',
  };

  String get description => switch (this) {
    RoutePolicy.auto => '优先使用可用的校园网路线',
    RoutePolicy.direct => '直接连接校园服务',
    RoutePolicy.webvpn => '通过 WebVPN 连接校园服务',
  };

  String get wireName => switch (this) {
    RoutePolicy.auto => 'auto',
    RoutePolicy.direct => 'direct',
    RoutePolicy.webvpn => 'webvpn',
  };
}

/// 首页和普通功能页中展示的只读功能。
enum FeatureId { schedule, exam, grades, bykc, classroom, spoc, judge, libbook }

extension FeatureIdText on FeatureId {
  String get title => switch (this) {
    FeatureId.schedule => '课表查询',
    FeatureId.exam => '考试查询',
    FeatureId.grades => '成绩查询',
    FeatureId.bykc => '博雅课程',
    FeatureId.classroom => '空教室查询',
    FeatureId.spoc => 'SPOC作业',
    FeatureId.judge => '希冀作业',
    FeatureId.libbook => '图书馆座位',
  };

  String get description => switch (this) {
    FeatureId.schedule => '查看课程表，支持周视图和学期切换',
    FeatureId.exam => '查看考试安排，支持学期切换',
    FeatureId.grades => '查看课程成绩、学分和绩点',
    FeatureId.bykc => '浏览选课，查看已选课程',
    FeatureId.classroom => '查询各校区空闲教室',
    FeatureId.spoc => '查看当前学期作业与提交状态',
    FeatureId.judge => '聚合希冀平台作业与提交进度',
    FeatureId.libbook => '查看图书馆座位和预约记录',
  };

  String get wireName => switch (this) {
    FeatureId.schedule => 'schedule',
    FeatureId.exam => 'exam',
    FeatureId.grades => 'grades',
    FeatureId.bykc => 'bykc',
    FeatureId.classroom => 'classroom',
    FeatureId.spoc => 'spoc',
    FeatureId.judge => 'judge',
    FeatureId.libbook => 'libbook',
  };
}

/// 稳定错误代码。值与 Rust Core/CLI 合同保持一致，UI 不直接展示上游文本。
enum UbaaErrorCode {
  invalidInput,
  authenticationRequired,
  invalidCredentials,
  passwordRiskConfirmationFailed,
  permissionDenied,
  networkError,
  timeout,
  upstreamUnavailable,
  upstreamChanged,
  parseError,
  internalError,
  unsupported,
}

extension UbaaErrorCodeText on UbaaErrorCode {
  String get wireName => switch (this) {
    UbaaErrorCode.invalidInput => 'invalid_input',
    UbaaErrorCode.authenticationRequired => 'authentication_required',
    UbaaErrorCode.invalidCredentials => 'invalid_credentials',
    UbaaErrorCode.passwordRiskConfirmationFailed =>
      'password_risk_confirmation_failed',
    UbaaErrorCode.permissionDenied => 'permission_denied',
    UbaaErrorCode.networkError => 'network_error',
    UbaaErrorCode.timeout => 'timeout',
    UbaaErrorCode.upstreamUnavailable => 'upstream_unavailable',
    UbaaErrorCode.upstreamChanged => 'upstream_changed',
    UbaaErrorCode.parseError => 'parse_error',
    UbaaErrorCode.internalError => 'internal_error',
    UbaaErrorCode.unsupported => 'unsupported',
  };
}

/// 面向用户的安全错误模型。
///
/// `technicalDetail` 只允许在开发日志中使用，不能直接渲染到界面或遥测。
@immutable
class UiError {
  const UiError({
    required this.code,
    required this.title,
    required this.message,
    this.actionLabel,
    this.retryable = false,
    this.issueId,
    this.technicalDetail,
  });

  final UbaaErrorCode code;
  final String title;
  final String message;
  final String? actionLabel;
  final bool retryable;
  final String? issueId;

  /// 不得包含密码、Cookie、URL、上游响应正文或个人信息。
  final String? technicalDetail;

  @override
  String toString() => 'UiError(${code.wireName}, retryable: $retryable)';
}

@immutable
class LoginInput {
  const LoginInput({
    required this.username,
    required this.password,
    this.captcha,
    this.rememberPassword = false,
    this.autoLogin = false,
    this.routePolicy = RoutePolicy.auto,
  });

  final String username;
  final String password;
  final String? captcha;
  final bool rememberPassword;
  final bool autoLogin;
  final RoutePolicy routePolicy;
}

@immutable
class UserSummary {
  const UserSummary({
    required this.username,
    this.displayName,
    this.department,
  });

  final String username;
  final String? displayName;
  final String? department;

  String get preferredName => displayName == null || displayName!.trim().isEmpty
      ? username
      : displayName!;
}

enum FeatureLoadStatus { idle, loading, success, empty, failure }

@immutable
class FeatureSnapshot {
  const FeatureSnapshot({
    required this.feature,
    this.status = FeatureLoadStatus.idle,
    this.summary,
    this.error,
    this.updatedAt,
  });

  final FeatureId feature;
  final FeatureLoadStatus status;
  final String? summary;
  final UiError? error;
  final DateTime? updatedAt;

  FeatureSnapshot copyWith({
    FeatureLoadStatus? status,
    String? summary,
    UiError? error,
    DateTime? updatedAt,
    bool clearError = false,
  }) => FeatureSnapshot(
    feature: feature,
    status: status ?? this.status,
    summary: summary ?? this.summary,
    error: clearError ? null : (error ?? this.error),
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// 首页加载结果。每个功能独立返回，避免单个上游故障遮蔽其他卡片。
@immutable
class FeatureResult {
  const FeatureResult.success({this.summary}) : isEmpty = false, error = null;

  const FeatureResult.empty() : summary = null, isEmpty = true, error = null;

  const FeatureResult.failure(this.error) : summary = null, isEmpty = false;

  final String? summary;
  final bool isEmpty;
  final UiError? error;
}
