import 'dart:async';

import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

/// Core 错误载荷的安全解析投影。
///
/// `message` 只作为可选的开发诊断输入，默认不会进入 [UiError] 的可展示
/// 文本。解析器只接受稳定的错误字段，不保留未知字段或上游响应正文。
@immutable
class CoreErrorPayload {
  const CoreErrorPayload({
    required this.code,
    this.kind,
    this.retryable,
    this.message,
    this.issueId,
  });

  final String code;
  final String? kind;
  final bool? retryable;
  final String? message;
  final String? issueId;

  /// 从 Core 错误对象或当前 CLI schema-v7 envelope 中解析。
  factory CoreErrorPayload.fromJson(Object? value) {
    final parsed = tryParse(value);
    return parsed ?? const CoreErrorPayload(code: 'internal_error');
  }

  /// 解析失败时返回 `null`，绝不抛出类型转换异常。
  static CoreErrorPayload? tryParse(Object? value) {
    final map = _extractErrorMap(value);
    if (map == null) return null;
    final rawCode = map['code'];
    if (rawCode is! String || rawCode.trim().isEmpty) return null;
    final rawKind = map['kind'];
    final rawRetryable = map['retryable'];
    final rawMessage = map['message'];
    final rawIssueId = map['issueId'] ?? map['issue_id'];
    return CoreErrorPayload(
      code: rawCode.trim(),
      kind: rawKind is String ? rawKind.trim() : null,
      retryable: rawRetryable is bool ? rawRetryable : null,
      message: rawMessage is String ? rawMessage : null,
      issueId: rawIssueId is String ? rawIssueId : null,
    );
  }

  Map<Object?, Object?> toJson({bool includeMessage = false}) =>
      <Object?, Object?>{
        'code': code,
        if (kind != null) 'kind': kind,
        if (retryable != null) 'retryable': retryable,
        if (includeMessage && message != null) 'message': message,
        if (issueId != null) 'issueId': issueId,
      };
}

/// 与 Core `ErrorKind` 对齐的 UI 错误类别。
enum UiErrorKind {
  input,
  authentication,
  network,
  upstream,
  parse,
  internal,
  unknown,
}

extension UiErrorKindText on UiErrorKind {
  String get wireName => switch (this) {
    UiErrorKind.input => 'input',
    UiErrorKind.authentication => 'authentication',
    UiErrorKind.network => 'network',
    UiErrorKind.upstream => 'upstream',
    UiErrorKind.parse => 'parse',
    UiErrorKind.internal => 'internal',
    UiErrorKind.unknown => 'unknown',
  };
}

/// 把 Core/CLI 错误归约为不泄露上游细节的界面错误。
class UiErrorMapper {
  const UiErrorMapper();

  /// 根据 Core 稳定错误字段生成 UI 错误。
  UiError fromCore(
    CoreErrorPayload payload, {
    String? feature,
    bool includeTechnicalDetail = false,
  }) {
    final code = _parseCode(payload.code);
    final template = _templateFor(code);
    final retryable = payload.retryable ?? _defaultRetryable(code);
    final issueId = _safeIssueId(payload.issueId);
    final technicalDetail = includeTechnicalDetail
        ? _safeTechnicalDetail(payload.message)
        : null;
    // `feature` 只用于调用方上下文；绝不拼进可能含个人数据的错误文本。
    // 保留参数是为了让页面层可以统一传入功能标识，而不改变稳定文案。
    // ignore: avoid_unused_constructor_parameters
    feature;
    return UiError(
      code: code,
      title: template.title,
      message: template.message,
      actionLabel: template.actionLabel,
      retryable: retryable,
      issueId: issueId,
      technicalDetail: technicalDetail,
    );
  }

  /// 解析 Core 错误对象或当前 schema-v7 envelope。
  UiError fromJson(
    Object? value, {
    String? feature,
    bool includeTechnicalDetail = false,
  }) => fromCore(
    CoreErrorPayload.fromJson(value),
    feature: feature,
    includeTechnicalDetail: includeTechnicalDetail,
  );

  /// 把平台异常转换为稳定 UI 错误；不保留异常正文。
  UiError fromException(Object error, {String? feature}) {
    final typeName = error.runtimeType.toString().toLowerCase();
    final code = error is TimeoutException || typeName.contains('timeout')
        ? 'timeout'
        : _looksLikeNetworkError(typeName)
        ? 'network_error'
        : 'internal_error';
    return fromCore(CoreErrorPayload(code: code), feature: feature);
  }

  /// Core `kind` 的安全映射。
  UiErrorKind kindOf(CoreErrorPayload payload) =>
      _parseKind(payload.kind, payload.code);
}

/// Core 错误字段到 UI 错误的便捷函数。
UiError mapCoreError({
  required String code,
  String? kind,
  bool? retryable,
  String? message,
  String? issueId,
  String? feature,
  bool includeTechnicalDetail = false,
}) => UiErrorMapper().fromCore(
  CoreErrorPayload(
    code: code,
    kind: kind,
    retryable: retryable,
    message: message,
    issueId: issueId,
  ),
  feature: feature,
  includeTechnicalDetail: includeTechnicalDetail,
);

/// 从 JSON/CLI envelope 生成 UI 错误。
UiError mapCoreErrorJson(
  Object? value, {
  String? feature,
  bool includeTechnicalDetail = false,
}) => UiErrorMapper().fromJson(
  value,
  feature: feature,
  includeTechnicalDetail: includeTechnicalDetail,
);

/// 从平台异常生成 UI 错误。
UiError mapExceptionToUiError(Object error, {String? feature}) =>
    UiErrorMapper().fromException(error, feature: feature);

/// 把现有领域 [UiError] 投影为安全的 wire 字段。
Map<String, Object?> uiErrorToJson(UiError error) => <String, Object?>{
  'code': error.code.wireName,
  'retryable': error.retryable,
  'message': error.message,
  if (error.issueId != null) 'issueId': error.issueId,
};

UbaaErrorCode _parseCode(String raw) {
  final normalized = raw.trim().toLowerCase();
  for (final code in UbaaErrorCode.values) {
    if (code.wireName == normalized) return code;
  }
  return UbaaErrorCode.internalError;
}

UiErrorKind _parseKind(String? raw, String code) {
  final normalized = raw?.trim().toLowerCase();
  for (final kind in UiErrorKind.values) {
    if (kind.wireName == normalized) return kind;
  }
  return switch (_parseCode(code)) {
    UbaaErrorCode.invalidInput ||
    UbaaErrorCode.confirmationRequired ||
    UbaaErrorCode.intentExpired ||
    UbaaErrorCode.operationConflict => UiErrorKind.input,
    UbaaErrorCode.authenticationRequired ||
    UbaaErrorCode.invalidCredentials ||
    UbaaErrorCode.passwordRiskConfirmationFailed ||
    UbaaErrorCode.permissionDenied => UiErrorKind.authentication,
    UbaaErrorCode.networkError ||
    UbaaErrorCode.timeout ||
    UbaaErrorCode.upstreamUnavailable ||
    UbaaErrorCode.outcomeUnknown => UiErrorKind.network,
    UbaaErrorCode.upstreamChanged => UiErrorKind.upstream,
    UbaaErrorCode.parseError => UiErrorKind.parse,
    UbaaErrorCode.internalError ||
    UbaaErrorCode.unsupported => UiErrorKind.internal,
  };
}

bool _defaultRetryable(UbaaErrorCode code) => switch (code) {
  UbaaErrorCode.networkError ||
  UbaaErrorCode.timeout ||
  UbaaErrorCode.upstreamUnavailable => true,
  UbaaErrorCode.invalidInput ||
  UbaaErrorCode.authenticationRequired ||
  UbaaErrorCode.invalidCredentials ||
  UbaaErrorCode.passwordRiskConfirmationFailed ||
  UbaaErrorCode.permissionDenied ||
  UbaaErrorCode.upstreamChanged ||
  UbaaErrorCode.parseError ||
  UbaaErrorCode.internalError ||
  UbaaErrorCode.unsupported ||
  UbaaErrorCode.confirmationRequired ||
  UbaaErrorCode.intentExpired ||
  UbaaErrorCode.operationConflict ||
  UbaaErrorCode.outcomeUnknown => false,
};

({String title, String message, String? actionLabel}) _templateFor(
  UbaaErrorCode code,
) => switch (code) {
  UbaaErrorCode.invalidInput => (
    title: '输入有误',
    message: '请检查输入后重试',
    actionLabel: null,
  ),
  UbaaErrorCode.authenticationRequired => (
    title: '需要登录',
    message: '请先登录后再继续',
    actionLabel: '去登录',
  ),
  UbaaErrorCode.invalidCredentials => (
    title: '登录失败',
    message: '账号或密码不正确',
    actionLabel: '重试',
  ),
  UbaaErrorCode.passwordRiskConfirmationFailed => (
    title: '登录失败',
    message: '密码风险确认未完成，请重试',
    actionLabel: '重试',
  ),
  UbaaErrorCode.permissionDenied => (
    title: '没有权限',
    message: '当前账号没有执行此操作的权限',
    actionLabel: null,
  ),
  UbaaErrorCode.networkError => (
    title: '网络不可用',
    message: '请检查网络连接后重试',
    actionLabel: '重试',
  ),
  UbaaErrorCode.timeout => (
    title: '请求超时',
    message: '服务响应较慢，请稍后重试',
    actionLabel: '重试',
  ),
  UbaaErrorCode.upstreamUnavailable => (
    title: '服务暂不可用',
    message: '服务暂时不可用，请稍后重试',
    actionLabel: '重试',
  ),
  UbaaErrorCode.upstreamChanged => (
    title: '服务需要更新',
    message: '服务接口发生变化，请稍后再试',
    actionLabel: null,
  ),
  UbaaErrorCode.parseError => (
    title: '数据异常',
    message: '服务返回的数据无法识别',
    actionLabel: '重试',
  ),
  UbaaErrorCode.internalError => (
    title: '应用异常',
    message: '应用内部错误，请稍后重试',
    actionLabel: '重试',
  ),
  UbaaErrorCode.unsupported => (
    title: '暂不支持',
    message: '此功能暂不支持',
    actionLabel: null,
  ),
  UbaaErrorCode.confirmationRequired => (
    title: '需要确认',
    message: '请先查看并确认本次操作的目标与影响。',
    actionLabel: null,
  ),
  UbaaErrorCode.intentExpired => (
    title: '确认已过期',
    message: '操作确认已过期，请重新准备。',
    actionLabel: '重新准备',
  ),
  UbaaErrorCode.operationConflict => (
    title: '操作状态已变化',
    message: '路线或会话已变化，请重新准备操作。',
    actionLabel: '重新准备',
  ),
  UbaaErrorCode.outcomeUnknown => (
    title: '结果待核对',
    message: '操作结果暂时无法确认，请先刷新相关状态，勿重复提交。',
    actionLabel: '刷新状态',
  ),
};

String? _safeIssueId(String? value) {
  if (value == null || !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(value)) {
    return null;
  }
  return value;
}

String? _safeTechnicalDetail(String? value) {
  if (value == null) return null;
  final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty || normalized.length > 256) return null;
  final lower = normalized.toLowerCase();
  const sensitiveMarkers = <String>[
    'password',
    'token',
    'cookie',
    'authorization',
    'set-cookie',
    'username',
    'account',
    'email',
    'phone',
    'id_card',
    'idcard',
    'http://',
    'https://',
  ];
  if (sensitiveMarkers.any(lower.contains)) return null;
  if (RegExp(r'\b1[3-9][0-9]{9}\b').hasMatch(normalized) ||
      RegExp(r'\b[^\s@]+@[^\s@]+\.[^\s@]+\b').hasMatch(normalized)) {
    return null;
  }
  return normalized;
}

bool _looksLikeNetworkError(String typeName) =>
    typeName.contains('socket') ||
    typeName.contains('network') ||
    typeName.contains('http') ||
    typeName.contains('handshake') ||
    typeName.contains('connection');

Map<Object?, Object?>? _extractErrorMap(Object? value) {
  if (value is! Map) return null;
  final map = <Object?, Object?>{};
  value.forEach((key, item) => map[key] = item);
  final nested = map['error'];
  if (nested is Map) {
    final nestedMap = <Object?, Object?>{};
    nested.forEach((key, item) => nestedMap[key] = item);
    return nestedMap;
  }
  // 某些桥接层把 envelope 放在 data.error 中；只沿固定字段向下查找，
  // 不遍历任意上游正文。
  final data = map['data'];
  if (data is Map && data['error'] is Map) {
    final nestedMap = <Object?, Object?>{};
    (data['error'] as Map).forEach((key, item) => nestedMap[key] = item);
    return nestedMap;
  }
  return map;
}
