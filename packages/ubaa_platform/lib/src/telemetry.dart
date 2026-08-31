import 'dart:async';

import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart' show FeatureId, FeatureIdText;

/// 允许上报的稳定事件名称。
///
/// 事件集合是代码中的白名单；调用方不能通过任意字符串扩展遥测面。事件
/// 只描述产品流程状态，不包含账号、密码、Cookie、令牌、URL、响应正文或
/// 个人信息。
abstract final class TelemetryEvents {
  static const appStarted = 'app_started';
  static const authStarted = 'auth_started';
  static const authSucceeded = 'auth_succeeded';
  static const authFailed = 'auth_failed';
  static const sessionExpired = 'session_expired';
  static const routeResolved = 'route_resolved';
  static const featureLoaded = 'feature_loaded';
  static const featureFailed = 'feature_failed';
  static const uiErrorShown = 'ui_error_shown';

  /// 生产默认事件白名单。
  static const Set<String> allowed = <String>{
    appStarted,
    authStarted,
    authSucceeded,
    authFailed,
    sessionExpired,
    routeResolved,
    featureLoaded,
    featureFailed,
    uiErrorShown,
  };
}

/// `TelemetryEvents` 的兼容命名别名。
abstract final class TelemetryEventName {
  static const appStarted = TelemetryEvents.appStarted;
  static const authStarted = TelemetryEvents.authStarted;
  static const authSucceeded = TelemetryEvents.authSucceeded;
  static const authFailed = TelemetryEvents.authFailed;
  static const sessionExpired = TelemetryEvents.sessionExpired;
  static const routeResolved = TelemetryEvents.routeResolved;
  static const featureLoaded = TelemetryEvents.featureLoaded;
  static const featureFailed = TelemetryEvents.featureFailed;
  static const uiErrorShown = TelemetryEvents.uiErrorShown;
  static const Set<String> allowed = TelemetryEvents.allowed;
}

/// 遥测字段策略。
///
/// 默认只接受跨平台 UI 需要的低基数、非敏感字段。自定义策略可以收窄
/// 白名单，但不能绕过敏感字段屏蔽。
class TelemetryPolicy {
  TelemetryPolicy({Set<String>? allowedEvents, Set<String>? allowedFields})
    : allowedEvents = Set.unmodifiable(
        (allowedEvents ?? TelemetryEvents.allowed).where(
          TelemetryEvents.allowed.contains,
        ),
      ),
      allowedFields = Set.unmodifiable(
        (allowedFields ?? _defaultAllowedFields).where(
          _defaultAllowedFields.contains,
        ),
      );

  final Set<String> allowedEvents;
  final Set<String> allowedFields;

  static final TelemetryPolicy defaultPolicy = TelemetryPolicy();

  bool allowsEvent(String name) => allowedEvents.contains(name);

  bool allowsField(String name) =>
      allowedFields.contains(name) && !_isSensitiveField(name);
}

const Set<String> _defaultAllowedFields = <String>{
  'platform',
  'app_version',
  'route',
  'route_policy',
  'readiness',
  'feature',
  'error_code',
  'error_kind',
  'retryable',
  'surface',
  'source',
  'result',
  'latency_ms',
};

/// 即使自定义策略错误地加入，也必须始终拒绝的字段。
const Set<String> _sensitiveFieldNames = <String>{
  'password',
  'passwd',
  'secret',
  'token',
  'access_token',
  'refresh_token',
  'cookie',
  'set_cookie',
  'authorization',
  'username',
  'account',
  'email',
  'phone',
  'id_card_number',
  'idcard',
  'raw',
  'body',
  'url',
};

bool _isSensitiveField(String name) {
  final normalized = name.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  return _sensitiveFieldNames.any(
    (candidate) => normalized.contains(candidate.replaceAll('_', '')),
  );
}

/// 已净化的遥测事件。
@immutable
class TelemetryRecord {
  TelemetryRecord({
    required this.name,
    Map<String, Object?> properties = const {},
  }) : properties = Map.unmodifiable(properties);

  final String name;
  final Map<String, Object?> properties;

  /// 兼容调用方使用的字段命名。
  Map<String, Object?> get fields => properties;

  /// 便于测试和平台 sink 消费的扁平 JSON 投影。
  Map<String, Object?> toJson() => <String, Object?>{
    'event': name,
    ...properties,
  };

  @override
  String toString() =>
      'TelemetryRecord($name, fields: ${properties.keys.toList()})';
}

typedef TelemetrySink = FutureOr<void> Function(TelemetryRecord record);

/// 遥测客户端的最小平台接口。
///
/// 无参构造函数就是安全默认值：遥测关闭且不会调用任何外部 sink。只有在
/// 显式传入 `enabled: true` 和 sink 时才会发送白名单事件。
abstract class TelemetryClient {
  const TelemetryClient._();

  factory TelemetryClient({
    bool enabled = false,
    TelemetrySink? sink,
    TelemetryPolicy? policy,
  }) {
    if (!enabled || sink == null) return const NoopTelemetryClient();
    return CallbackTelemetryClient(
      sink: sink,
      policy: policy ?? TelemetryPolicy.defaultPolicy,
    );
  }

  /// 创建显式关闭的客户端。
  factory TelemetryClient.noop() => const NoopTelemetryClient();

  /// 创建测试客户端；默认开启以便断言事件，但仍受白名单约束。
  factory TelemetryClient.mock({
    bool enabled = true,
    TelemetryPolicy? policy,
  }) => MockTelemetryClient(
    enabled: enabled,
    policy: policy ?? TelemetryPolicy.defaultPolicy,
  );

  bool get enabled;

  TelemetryPolicy get policy;

  /// 记录事件。未知事件、未知字段和敏感字段会被静默丢弃。
  ///
  /// 遥测不应影响业务流程；具体 sink 的异常也会被实现吞掉。
  Future<void> track(
    String event, {
    Map<String, Object?> properties = const <String, Object?>{},
  });

  /// `track` 的语义别名。
  Future<void> record(
    String event, {
    Map<String, Object?> properties = const <String, Object?>{},
  }) => track(event, properties: properties);

  /// 为有批量发送能力的平台保留的刷新钩子；默认实现为空操作。
  Future<void> flush() async {}
}

/// 关闭遥测的实现。
class NoopTelemetryClient extends TelemetryClient {
  const NoopTelemetryClient() : super._();

  @override
  bool get enabled => false;

  @override
  TelemetryPolicy get policy => TelemetryPolicy.defaultPolicy;

  @override
  Future<void> track(
    String event, {
    Map<String, Object?> properties = const <String, Object?>{},
  }) async {}
}

/// 测试用遥测客户端；只保留净化后的事件。
class MockTelemetryClient extends TelemetryClient {
  MockTelemetryClient({this.enabled = true, TelemetryPolicy? policy})
    : policy = policy ?? TelemetryPolicy.defaultPolicy,
      super._();

  @override
  final bool enabled;

  @override
  final TelemetryPolicy policy;

  final List<TelemetryRecord> records = <TelemetryRecord>[];

  @override
  Future<void> track(
    String event, {
    Map<String, Object?> properties = const <String, Object?>{},
  }) async {
    if (!enabled) return;
    final record = sanitizeTelemetryRecord(event, properties, policy: policy);
    if (record != null) records.add(record);
  }

  void reset() => records.clear();
}

/// 由应用注入真实平台分析 SDK 的实现。
class CallbackTelemetryClient extends TelemetryClient {
  CallbackTelemetryClient({
    required TelemetrySink sink,
    TelemetryPolicy? policy,
    bool enabled = true,
  }) : _sink = sink,
       _enabled = enabled,
       policy = policy ?? TelemetryPolicy.defaultPolicy,
       super._();

  final TelemetrySink _sink;
  final bool _enabled;

  @override
  bool get enabled => _enabled;

  @override
  final TelemetryPolicy policy;

  @override
  Future<void> track(
    String event, {
    Map<String, Object?> properties = const <String, Object?>{},
  }) async {
    if (!_enabled) return;
    final record = sanitizeTelemetryRecord(event, properties, policy: policy);
    if (record == null) return;
    try {
      await _sink(record);
    } catch (_) {
      // 遥测失败不能改变登录或只读请求结果。
    }
  }
}

/// 功能使用事件的低基数结果。
enum TelemetryOutcome { success, empty, failure }

extension TelemetryOutcomeText on TelemetryOutcome {
  String get wireName => switch (this) {
    TelemetryOutcome.success => 'success',
    TelemetryOutcome.empty => 'empty',
    TelemetryOutcome.failure => 'failure',
  };
}

/// 可开关的测试内存实现。
///
/// 默认关闭；关闭时会清空已经记录的事件，避免测试或开发环境误把历史事件
/// 当成待发送队列。它只记录经过与生产客户端相同白名单处理的字段。
class InMemoryTelemetryClient extends TelemetryClient {
  InMemoryTelemetryClient({bool enabled = false, TelemetryPolicy? policy})
    : _enabled = enabled,
      policy = policy ?? TelemetryPolicy.defaultPolicy,
      super._();

  bool _enabled;

  @override
  bool get enabled => _enabled;

  @override
  final TelemetryPolicy policy;

  final List<TelemetryRecord> _events = <TelemetryRecord>[];

  List<TelemetryRecord> get events => List.unmodifiable(_events);

  /// 与 [MockTelemetryClient.records] 一致的只读命名。
  List<TelemetryRecord> get records => events;

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    if (!value) _events.clear();
  }

  @override
  Future<void> track(
    String event, {
    Map<String, Object?> properties = const <String, Object?>{},
  }) async {
    if (!_enabled) return;
    final record = sanitizeTelemetryRecord(event, properties, policy: policy);
    if (record != null) _events.add(record);
  }

  Future<void> recordAppOpen({String? platform, String? appVersion}) => track(
    TelemetryEvents.appStarted,
    properties: <String, Object?>{
      if (platform != null) 'platform': platform,
      if (appVersion != null) 'app_version': appVersion,
    },
  );

  Future<void> recordFeatureUsed(
    FeatureId feature, {
    required TelemetryOutcome outcome,
    Duration? latency,
  }) => track(
    outcome == TelemetryOutcome.failure
        ? TelemetryEvents.featureFailed
        : TelemetryEvents.featureLoaded,
    properties: <String, Object?>{
      'feature': feature.wireName,
      'result': outcome.wireName,
      if (latency != null) 'latency_ms': latency.inMilliseconds,
    },
  );

  void reset() => _events.clear();
}

/// 按事件和字段白名单净化事件。
TelemetryRecord? sanitizeTelemetryRecord(
  String event,
  Map<String, Object?> properties, {
  TelemetryPolicy? policy,
}) {
  final effectivePolicy = policy ?? TelemetryPolicy.defaultPolicy;
  if (!effectivePolicy.allowsEvent(event)) return null;

  final clean = <String, Object?>{};
  properties.forEach((key, value) {
    if (!effectivePolicy.allowsField(key)) return;
    final sanitized = _sanitizeValue(value);
    if (sanitized is _RejectedValue) return;
    clean[key] = sanitized;
  });
  return TelemetryRecord(name: event, properties: clean);
}

/// 判断事件名称是否在默认白名单中。
bool isTelemetryEventAllowed(String event) =>
    TelemetryEvents.allowed.contains(event);

const _RejectedValue _rejectedValue = _RejectedValue();

Object? _sanitizeValue(Object? value) {
  if (value == null || value is bool) return value;
  if (value is int) return value;
  if (value is double && value.isFinite) return value;
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.length > 128) return trimmed.substring(0, 128);
    return trimmed;
  }
  return _rejectedValue;
}

class _RejectedValue {
  const _RejectedValue();
}
