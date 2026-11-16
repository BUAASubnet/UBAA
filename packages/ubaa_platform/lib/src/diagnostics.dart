import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:ubaa_domain/ubaa_domain.dart';
import '../diagnostic_operation.dart';
import 'credentials.dart';
import 'infrastructure/preferences.dart';
import 'secure_material.dart';

/// 只依赖异常类型，绝不通过异常正文猜测原因。
enum DiagnosticCause {
  none,
  timeout,
  format,
  state,
  argument,
  assertion,
  type,
  credentialStorage,
  secureMaterial,
  unknown,
}

/// 启动过程中能独立定位的宿主阶段。
enum DiagnosticInitializationStage {
  sdk,
  bridgeCheck,
  platformCapabilities,
  backendOpen,
  backendInstall,
  localAccountRestore,
  sessionState,
  credentialRestore,
}

const _platformNames = {'android', 'ios', 'macos', 'windows', 'linux', 'ohos'};

/// 只含允许字段的不可变诊断事件；不能直接构造或填入任意文本。
final class DiagnosticRecord {
  DiagnosticRecord._({
    required this.issueId,
    required this.operation,
    required this.code,
    required this.kind,
    required this.retryable,
    required this.cause,
    required this.timestamp,
    required List<String> source,
    this.route,
    this.feature,
    this.writeOperation,
    this.fileIndex,
    this.latency,
    this.initializationFailure,
    this.initializationStage,
    this.authStage,
    this.authReason,
    this.diagnostic,
    this.relatedIssueId,
  }) : source = List.unmodifiable(source);

  final String issueId;
  final DiagnosticOperation operation;
  final UbaaErrorCode code;
  final UbaaErrorKind kind;
  final bool retryable;
  final DiagnosticCause cause;
  final DateTime timestamp;
  final List<String> source;
  final ConnectionMode? route;
  final FeatureId? feature;
  final WriteOperation? writeOperation;
  final int? fileIndex;
  final Duration? latency;
  final InitializationFailure? initializationFailure;
  final DiagnosticInitializationStage? initializationStage;
  final AuthFailureStage? authStage;
  final AuthFailureReason? authReason;
  final ErrorDiagnostic? diagnostic;
  final String? relatedIssueId;

  Map<String, Object?> toJson() => {
    'issue_id': issueId,
    'operation': operation.name,
    'code': code.wireName,
    'kind': kind.name,
    'retryable': retryable,
    'cause': cause.name,
    if (diagnostic != null) 'diagnostic': diagnostic!.toJson(),
    if (authStage != null) 'stage': authStage!.wireName,
    if (authReason != null) 'reason': authReason!.wireName,
    if (relatedIssueId != null) 'related_issue_id': relatedIssueId,
    'time': timestamp.toUtc().toIso8601String(),
    if (route != null) 'route': route!.name,
    if ((feature?.wireName ??
            operation.serviceFeature ??
            (writeOperation == WriteOperation.bhpan ? 'bhpan' : null))
        case final name?)
      'feature': name,
    if (writeOperation != null) 'write_operation': writeOperation!.name,
    if (fileIndex != null) 'file_index': fileIndex,
    if (latency != null) 'latency_ms': latency!.inMilliseconds,
    if (source.isNotEmpty) 'source': source,
    if (initializationFailure != null)
      'initialization_failure': initializationFailure!.name,
    if (initializationStage != null)
      'initialization_stage': initializationStage!.name,
  };
}

/// 默认保存在内存；宿主可提供本机存储，保留七天内最多 capacity 项，不发送网络请求。
final class LocalDiagnostics {
  LocalDiagnostics({int capacity = 100, PreferenceValues? storage})
    : _capacity = capacity,
      _storage = storage {
    if (capacity < 1 || capacity > 1000) {
      throw ArgumentError.value(capacity, 'capacity', '必须在 1 至 1000 之间');
    }
    _saved = _restore();
  }

  static int _runSequence = 0;
  static const _storageKey = 'ubaa.diagnostics.v3';
  final PreferenceValues? _storage;
  Future<void> _saved = Future.value();
  final List<Map<String, Object?>> _history = [];
  Future<void> get flushed => _saved;

  Future<void> _restore() async {
    if (_storage == null) return;
    try {
      final text = await _storage.read(_storageKey);
      if (text == null || text.length > 256 * 1024) return;
      final payload = jsonDecode(text);
      if (payload is! List) return;
      for (final item in payload.take(_capacity)) {
        if (item is! Map) continue;
        final time = DateTime.tryParse(
          item['time'] is String ? item['time'] : '',
        );
        final diagnostic = ErrorDiagnostic.parse(
          jsonEncode(item['diagnostic']),
        );
        final code = UbaaErrorCode.values
            .where((v) => v.wireName == item['code'])
            .firstOrNull;
        final operation = DiagnosticOperation.values
            .where((v) => v.name == item['operation'])
            .firstOrNull;
        if (time == null ||
            time.isBefore(
              DateTime.now().toUtc().subtract(const Duration(days: 7)),
            ) ||
            code == null ||
            operation == null) {
          continue;
        }
        _history.add({
          'time': time.toUtc().toIso8601String(),
          'code': code.wireName,
          'operation': operation.name,
          for (final key in ['issue_id', 'related_issue_id'])
            if (item[key] is String &&
                RegExp(r'^UBAA-[A-Za-z0-9-]{1,59}$').hasMatch(item[key]))
              key: item[key],
          if (AuthFailureStage.parse(
                item['stage'] is String ? item['stage'] : null,
              )
              case final stage?)
            'stage': stage.wireName,
          if (AuthFailureReason.parse(
                item['reason'] is String ? item['reason'] : null,
              )
              case final reason?)
            'reason': reason.wireName,
          if (InitializationFailure.values.any(
            (v) => v.name == item['initialization_failure'],
          ))
            'initialization_failure': item['initialization_failure'],
          if (DiagnosticInitializationStage.values.any(
            (v) => v.name == item['initialization_stage'],
          ))
            'initialization_stage': item['initialization_stage'],
          if (item['latency_ms'] is int && (item['latency_ms'] as int) >= 0)
            'latency_ms': item['latency_ms'],
          if (ConnectionMode.values.any((v) => v.name == item['route']))
            'route': item['route'],
          if (FeatureId.values.any((v) => v.wireName == item['feature']) ||
              DiagnosticOperation.serviceFeatures.contains(item['feature']))
            'feature': item['feature'],
          if (WriteOperation.values.any(
            (v) => v.name == item['write_operation'],
          ))
            'write_operation': item['write_operation'],
          if (item['file_index'] is int && (item['file_index'] as int) > 0)
            'file_index': item['file_index'],
          if (UbaaErrorKind.values.any((v) => v.name == item['kind']))
            'kind': item['kind'],
          if (DiagnosticCause.values.any((v) => v.name == item['cause']))
            'cause': item['cause'],
          if (item['retryable'] is bool) 'retryable': item['retryable'],
          if (item['app_version'] is String &&
              RegExp(
                r'^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.+-]+)?$',
              ).hasMatch(item['app_version']))
            'app_version': item['app_version'],
          if (_platformNames.contains(item['platform']))
            'platform': item['platform'],
          if (diagnostic != null) 'diagnostic': diagnostic.toJson(),
          'source': _safeSource(
            StackTrace.fromString(
              item['source'] is List
                  ? (item['source'] as List).whereType<String>().join('\n')
                  : '',
            ),
          ),
        });
      }
      await _storage.write(_storageKey, jsonEncode(_history));
    } on Object {
      /* 本地存储不可用时继续保留本次运行的诊断。 */
    }
  }

  void _persist() {
    if (_storage == null) return;
    _saved = _saved
        .then((_) async {
          final events = [
            ..._history,
            ..._records.map(
              (r) => {
                ...r.toJson(),
                if (_appVersion != null) 'app_version': _appVersion,
                if (_platform != null) 'platform': _platform,
              },
            ),
          ];
          final recent = events
              .skip(events.length > _capacity ? events.length - _capacity : 0)
              .toList();
          while (recent.isNotEmpty &&
              utf8.encode(jsonEncode(recent)).length > 256 * 1024) {
            recent.removeAt(0);
          }
          await _storage.write(_storageKey, jsonEncode(recent));
        })
        .catchError((Object _) {});
  }

  final int _capacity;
  final String _runId =
      '${DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36)}-${++_runSequence}';
  final Queue<DiagnosticRecord> _records = Queue();
  int _sequence = 0;
  String? _appVersion;
  String? _platform;

  /// 宿主提供安装包版本和系统名称，不接受设备标识。
  void setEnvironment({String? appVersion, String? platform}) {
    var changed = false;
    if (appVersion != null &&
        appVersion != _appVersion &&
        RegExp(
          r'^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.+-]+)?$',
        ).hasMatch(appVersion)) {
      _appVersion = appVersion;
      changed = true;
    }
    if (platform != _platform && _platformNames.contains(platform)) {
      _platform = platform;
      changed = true;
    }
    if (changed && _records.isNotEmpty) _persist();
  }

  List<DiagnosticRecord> get records => List.unmodifiable(_records);

  UiError record({
    required DiagnosticOperation operation,
    required UiError error,
    FeatureId? feature,
    WriteOperation? writeOperation,
    int? fileIndex,
    Duration? latency,
    Object? cause,
    StackTrace? stackTrace,
    String? relatedIssueId,
    DiagnosticInitializationStage? initializationStage,
  }) {
    final issueId = 'UBAA-$_runId-${++_sequence}';
    _records.add(
      DiagnosticRecord._(
        issueId: issueId,
        operation: operation,
        code: error.code,
        kind: error.kind,
        retryable: error.retryable,
        route: error.resolvedRoute,
        feature: feature,
        writeOperation: writeOperation,
        fileIndex: fileIndex,
        latency: latency,
        initializationFailure: error.initializationFailure,
        initializationStage: initializationStage,
        authStage: error.authStage,
        authReason: error.authReason,
        diagnostic: error.diagnostic,
        relatedIssueId: _records.any((r) => r.issueId == relatedIssueId)
            ? relatedIssueId
            : null,
        cause: _classify(cause),
        timestamp: DateTime.now().toUtc(),
        source: _safeSource(stackTrace),
      ),
    );
    while (_records.length > _capacity) {
      _records.removeFirst();
    }
    _persist();
    return error.withIssueId(issueId);
  }

  String exportText({String? issueId}) {
    String? group = issueId;
    for (final record in _records) {
      if (record.issueId == issueId) group = record.relatedIssueId ?? issueId;
    }
    return const JsonEncoder.withIndent('  ').convert({
      'schema_version': 3,
      if (_appVersion != null) 'app_version': _appVersion,
      if (_platform != null) 'platform': _platform,
      if (issueId == null && _history.isNotEmpty) 'previous_events': _history,
      'events': _records
          .where(
            (r) =>
                issueId == null ||
                r.issueId == group ||
                r.relatedIssueId == group,
          )
          .map((event) => event.toJson())
          .toList(growable: false),
    });
  }

  void clear() {
    _records.clear();
    _saved = _saved
        .then((_) async {
          _history.clear();
          await _storage?.remove(_storageKey);
        })
        .catchError((Object _) {});
  }
}

DiagnosticCause _classify(Object? cause) => switch (cause) {
  null => DiagnosticCause.none,
  CredentialVaultException() => DiagnosticCause.credentialStorage,
  SecureMaterialException() => DiagnosticCause.secureMaterial,
  TimeoutException() => DiagnosticCause.timeout,
  FormatException() => DiagnosticCause.format,
  StateError() => DiagnosticCause.state,
  ArgumentError() => DiagnosticCause.argument,
  AssertionError() => DiagnosticCause.assertion,
  TypeError() => DiagnosticCause.type,
  _ => DiagnosticCause.unknown,
};

List<String> _safeSource(StackTrace? stackTrace) {
  if (stackTrace == null) return const [];
  final text = stackTrace.toString();
  final bounded = text.length > 8192 ? text.substring(0, 8192) : text;
  final pattern = RegExp(
    r'package:ubaa_(?:app|domain|platform|ui|host|bindings)/[a-zA-Z0-9_/]+\.dart:[0-9]+(?::[0-9]+)?',
  );
  return pattern
      .allMatches(bounded)
      .take(3)
      .map((match) => match.group(0)!)
      .toList(growable: false);
}
