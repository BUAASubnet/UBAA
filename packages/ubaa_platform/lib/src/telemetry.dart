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
  static const crash = 'crash';

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
    crash,
  };
}

/// 遥测字段策略。
///
/// 默认只接受跨平台 UI 需要的低基数、非敏感字段。自定义策略可以收窄
/// 白名单，但不能绕过敏感字段屏蔽。
class TelemetryPolicy {
  TelemetryPolicy({Set<String>? allowedEvents, Set<String>? allowedFields})
    : allowedEvents = Set.unmodifiable(
        (allowedEvents ??
                {...TelemetryEvents.allowed, ...TelemetryMetrics.allowed})
            .where(isTelemetryEventAllowed),
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

  bool allowsField(String name) => allowedFields.contains(name);
}

/// 耗时与普通事件使用同一个入口，Core 分别聚合到 timings 和计数数组。
abstract final class TelemetryMetrics {
  static const coldStart = 'cold_start';
  static const firstContent = 'first_content';
  static const auth = 'auth';
  static const featureLoad = 'feature_load';

  static const allowed = {coldStart, firstContent, auth, featureLoad};

  static String bucket(Duration duration) {
    final ms = duration.inMilliseconds;
    for (final upper in [250, 500, 1000, 2000, 5000, 10000]) {
      if (ms < upper) return 'lt_$upper';
    }
    return 'ge_10000';
  }
}

const Set<String> _defaultAllowedFields = {
  'route',
  'feature',
  'error_code',
  'error_kind',
  'retryable',
  'source',
  'result',
  'bucket',
};

final _features = {'app', 'auth', ...FeatureId.values.map((f) => f.wireName)};
const _routes = {'direct', 'webvpn', 'none'};
const _results = {'success', 'empty', 'failure'};
const _errorKinds = {
  'input',
  'authentication',
  'network',
  'upstream',
  'parse',
  'internal',
};
const _buckets = {
  'lt_250',
  'lt_500',
  'lt_1000',
  'lt_2000',
  'lt_5000',
  'lt_10000',
  'ge_10000',
};
final _errorCode = RegExp(r'^[a-z][a-z0-9_]{0,47}$');
final _crashCode = RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,63}$');
final _source = RegExp(r'^package:ubaa_[a-z_]+/[A-Za-z0-9_/]+\.dart:\d+$');
final _frame = RegExp(
  r'\((package:ubaa_[a-z_]+/[A-Za-z0-9_/]+\.dart:\d+)(?::\d+)?\)\s*$',
);

/// 仅取第一个仓库内 Dart 帧，去掉列号；不接受异常消息或本机路径。
String? telemetrySource(StackTrace? stackTrace) {
  if (stackTrace == null) return null;
  try {
    final stack = stackTrace.toString();
    final sample = stack.length <= 8192 ? stack : stack.substring(0, 8192);
    for (final line in sample.split('\n')) {
      final source = _frame.firstMatch(line)?.group(1);
      if (source != null && source.length <= 128) return source;
    }
  } on Object {
    // 栈无法格式化时仍可记录稳定错误码。
  }
  return null;
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
    void Function()? onFailure,
  }) : _sink = sink,
       _onFailure = onFailure,
       _enabled = enabled,
       policy = policy ?? TelemetryPolicy.defaultPolicy,
       super._();

  final TelemetrySink _sink;
  final void Function()? _onFailure;
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
      await Future<void>.sync(
        () => _sink(record),
      ).timeout(const Duration(seconds: 2));
    } catch (_) {
      _onFailure?.call();
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

  Future<void> recordAppOpen({String? platform, String? appVersion}) =>
      track(TelemetryEvents.appStarted);

  Future<void> recordFeatureUsed(
    FeatureId feature, {
    required TelemetryOutcome outcome,
    Duration? latency,
  }) async {
    await track(
      outcome == TelemetryOutcome.failure
          ? TelemetryEvents.featureFailed
          : TelemetryEvents.featureLoaded,
      properties: {'feature': feature.wireName, 'result': outcome.wireName},
    );
    if (latency != null) {
      await track(
        TelemetryMetrics.featureLoad,
        properties: {
          'feature': feature.wireName,
          'bucket': TelemetryMetrics.bucket(latency),
        },
      );
    }
  }

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
    final accepted = switch (key) {
      'feature' => _features.contains(value),
      'route' => _routes.contains(value),
      'result' => _results.contains(value),
      'bucket' => _buckets.contains(value),
      'error_kind' => _errorKinds.contains(value),
      'retryable' => value is bool,
      'error_code' =>
        value is String &&
            (event == TelemetryEvents.crash ? _crashCode : _errorCode).hasMatch(
              value,
            ),
      'source' =>
        value is String && value.length <= 128 && _source.hasMatch(value),
      _ => false,
    };
    if (accepted) clean[key] = value;
  });
  return TelemetryRecord(name: event, properties: clean);
}

/// 判断名称是否为合同事件或耗时指标。
bool isTelemetryEventAllowed(String event) =>
    TelemetryEvents.allowed.contains(event) ||
    TelemetryMetrics.allowed.contains(event);
