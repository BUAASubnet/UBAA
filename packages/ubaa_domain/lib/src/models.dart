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
enum FeatureId {
  schedule,
  exam,
  grades,
  bykc,
  classroom,
  spoc,
  judge,
  libbook,
  signin,
  cgyy,
  ygdk,
  evaluation,
}

/// 普通功能页的稳定顺序。
const ordinaryFeatureIds = <FeatureId>[
  FeatureId.schedule,
  FeatureId.exam,
  FeatureId.grades,
  FeatureId.bykc,
  FeatureId.classroom,
  FeatureId.spoc,
  FeatureId.judge,
  FeatureId.libbook,
];

/// 高级功能页的稳定顺序。
const advancedFeatureIds = <FeatureId>[
  FeatureId.signin,
  FeatureId.cgyy,
  FeatureId.ygdk,
  FeatureId.evaluation,
];

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
    FeatureId.signin => '课堂签到',
    FeatureId.cgyy => '场馆预约',
    FeatureId.ygdk => '阳光打卡',
    FeatureId.evaluation => '教学评教',
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
    FeatureId.signin => '查看今日课程签到状态',
    FeatureId.cgyy => '查看场馆站点、日期和预约订单',
    FeatureId.ygdk => '查看学期进度与打卡记录',
    FeatureId.evaluation => '查看待评课程和完成进度',
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
    FeatureId.signin => 'signin',
    FeatureId.cgyy => 'cgyy',
    FeatureId.ygdk => 'ygdk',
    FeatureId.evaluation => 'evaluation',
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
  confirmationRequired,
  intentExpired,
  operationConflict,
  outcomeUnknown,
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
    UbaaErrorCode.confirmationRequired => 'confirmation_required',
    UbaaErrorCode.intentExpired => 'intent_expired',
    UbaaErrorCode.operationConflict => 'operation_conflict',
    UbaaErrorCode.outcomeUnknown => 'outcome_unknown',
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

enum FeatureLoadStatus { idle, loading, success, empty, stale, failure }

/// 领域详情读取的稳定视图。默认 [summary] 保持首页摘要行为；其余值只对
/// 对应领域生效，bridge 会拒绝缺少必要 ID 或时段的查询。
enum FeatureQueryView {
  summary,
  libbookAreas,
  libbookAreaDetail,
  libbookSeats,
  libbookBookings,
}

@immutable
class FeatureSnapshot {
  const FeatureSnapshot({
    required this.feature,
    this.status = FeatureLoadStatus.idle,
    this.summary,
    this.details = const <FeatureDetail>[],
    this.error,
    this.resolvedRoute,
    this.updatedAt,
  });

  final FeatureId feature;
  final FeatureLoadStatus status;
  final String? summary;
  final List<FeatureDetail> details;
  final UiError? error;

  /// Core 对本次读取实际解析出的路线；不能用配置策略替代。
  final ConnectionMode? resolvedRoute;
  final DateTime? updatedAt;

  FeatureSnapshot copyWith({
    FeatureLoadStatus? status,
    String? summary,
    List<FeatureDetail>? details,
    UiError? error,
    ConnectionMode? resolvedRoute,
    DateTime? updatedAt,
    bool clearError = false,
    bool clearSummary = false,
    bool clearDetails = false,
    bool clearResolvedRoute = false,
  }) => FeatureSnapshot(
    feature: feature,
    status: status ?? this.status,
    summary: clearSummary ? null : (summary ?? this.summary),
    details: clearDetails ? const <FeatureDetail>[] : (details ?? this.details),
    error: clearError ? null : (error ?? this.error),
    resolvedRoute: clearResolvedRoute
        ? null
        : (resolvedRoute ?? this.resolvedRoute),
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// 首页加载结果。每个功能独立返回，避免单个上游故障遮蔽其他卡片。
@immutable
class FeatureResult {
  const FeatureResult.success({
    this.summary,
    this.details = const <FeatureDetail>[],
    this.resolvedRoute,
  }) : isEmpty = false,
       error = null;

  const FeatureResult.empty({this.resolvedRoute})
    : summary = null,
      details = const <FeatureDetail>[],
      isEmpty = true,
      error = null;

  const FeatureResult.failure(this.error)
    : summary = null,
      details = const <FeatureDetail>[],
      resolvedRoute = null,
      isEmpty = false;

  final String? summary;
  final List<FeatureDetail> details;

  /// Core 对本次读取实际解析出的路线；失败或未执行时可以为空。
  final ConnectionMode? resolvedRoute;
  final bool isEmpty;
  final UiError? error;
}

/// 领域读取查询参数。未提供的字段由 Core/bridge 采用当前稳定默认值；
/// UI 不拼接 URL，也不把该对象序列化为 raw payload。
@immutable
class FeatureQuery {
  const FeatureQuery({
    this.term,
    this.date,
    this.campus,
    this.week,
    this.page = 0,
    this.size = 20,
    this.view = FeatureQueryView.summary,
    this.premisesId,
    this.storeyId,
    this.areaId,
    this.startTime,
    this.endTime,
  });

  final String? term;
  final DateTime? date;
  final int? campus;
  final int? week;
  final int page;
  final int size;
  final FeatureQueryView view;

  /// 图书馆楼馆/楼层/分区 ID。它们是用户从读取结果中选择的公开标识，
  /// 不包含 Session、Cookie 或 token。
  final String? premisesId;
  final String? storeyId;
  final String? areaId;
  final String? startTime;
  final String? endTime;

  FeatureQuery copyWith({
    String? term,
    DateTime? date,
    int? campus,
    int? week,
    int? page,
    int? size,
    FeatureQueryView? view,
    String? premisesId,
    String? storeyId,
    String? areaId,
    String? startTime,
    String? endTime,
  }) => FeatureQuery(
    term: term ?? this.term,
    date: date ?? this.date,
    campus: campus ?? this.campus,
    week: week ?? this.week,
    page: page ?? this.page,
    size: size ?? this.size,
    view: view ?? this.view,
    premisesId: premisesId ?? this.premisesId,
    storeyId: storeyId ?? this.storeyId,
    areaId: areaId ?? this.areaId,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
  );
}

/// 只读详情页使用的稳定展示模型，不携带原始上游载荷。
@immutable
class FeatureDetail {
  const FeatureDetail({
    required this.title,
    this.subtitle,
    this.fields = const <FeatureField>[],
  });

  final String title;
  final String? subtitle;
  final List<FeatureField> fields;
}

/// 详情卡片中的标签和值；值必须来自 bridge 白名单 DTO。
@immutable
class FeatureField {
  const FeatureField({required this.label, required this.value});

  final String label;
  final String value;
}

/// 写入确认时显示的实际连接路线。
enum ConnectionMode { direct, webvpn }

extension ConnectionModeText on ConnectionMode {
  String get label => switch (this) {
    ConnectionMode.direct => '直连',
    ConnectionMode.webvpn => 'WebVPN',
  };
}

/// 与 bridge 一一对应的封闭写操作枚举。
enum WriteOperation {
  bykcSelectCourse,
  bykcDeselectCourse,
  bykcSignCourse,
  signinPerform,
  libbookReserve,
  libbookCancelBooking,
  ygdkSubmit,
  cgyySubmitReservation,
  cgyyCancelOrder,
  evaluationSubmitCourses,
}

extension WriteOperationText on WriteOperation {
  String get title => switch (this) {
    WriteOperation.bykcSelectCourse => '博雅选课',
    WriteOperation.bykcDeselectCourse => '博雅退选',
    WriteOperation.bykcSignCourse => '博雅签到',
    WriteOperation.signinPerform => '课堂签到',
    WriteOperation.libbookReserve => '图书馆预约',
    WriteOperation.libbookCancelBooking => '取消图书馆预约',
    WriteOperation.ygdkSubmit => '阳光打卡',
    WriteOperation.cgyySubmitReservation => '场馆预约',
    WriteOperation.cgyyCancelOrder => '取消场馆订单',
    WriteOperation.evaluationSubmitCourses => '教学评教',
  };

  bool get isIrreversible => switch (this) {
    WriteOperation.bykcDeselectCourse ||
    WriteOperation.libbookCancelBooking ||
    WriteOperation.cgyyCancelOrder => false,
    _ => true,
  };
}

/// 一次性写入确认意图的安全投影。
@immutable
class WriteIntent {
  const WriteIntent({
    required this.intentId,
    required this.operation,
    required this.targetSummary,
    required this.resolvedRoute,
    required this.warnings,
    required this.expiresAt,
    required this.requestDigest,
  });

  final String intentId;
  final WriteOperation operation;
  final String targetSummary;
  final ConnectionMode resolvedRoute;
  final List<String> warnings;
  final DateTime expiresAt;
  final String requestDigest;

  bool isExpired([DateTime? now]) =>
      !(expiresAt.isAfter(now ?? DateTime.now()));
}

/// 写入提交后的安全结果；不携带上游原始正文。
@immutable
class WriteCommitResult {
  const WriteCommitResult({
    required this.operation,
    required this.success,
    required this.message,
    required this.outcomeUnknown,
    this.resolvedRoute,
  });

  final WriteOperation operation;
  final bool success;
  final String message;
  final bool outcomeUnknown;
  final ConnectionMode? resolvedRoute;
}
