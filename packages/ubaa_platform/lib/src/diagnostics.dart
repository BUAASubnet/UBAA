import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:ubaa_domain/ubaa_domain.dart';
import '../diagnostic_operation.dart';
import 'credentials.dart';
import 'infrastructure/preferences.dart';
import 'local_accounts.dart';
import 'secure_material.dart';
import 'media.dart';
import 'infrastructure/agenda_file.dart';

/// 只依赖异常类型和安全诊断，绝不通过异常正文猜测原因。
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
  platformCapability,
  agenda,
  file,
  operationConflict,
  authentication,
  permission,
  network,
  upstream,
  parse,
  unknown,
  cacheBusy,
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
    this.localReason,
    this.route,
    this.requestedPolicy,
    this.recoveryAttempts,
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
  final UbaaErrorCode? code;
  final UbaaErrorKind kind;
  final bool retryable;
  final DiagnosticCause cause;
  final String? localReason;
  final DateTime timestamp;
  final List<String> source;
  final ConnectionMode? route;
  final RoutePolicy? requestedPolicy;
  final int? recoveryAttempts;
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
    if (code case final code?) 'code': code.wireName,
    'kind': kind.name,
    'retryable': retryable,
    'cause': cause.name,
    if (localReason != null) 'local_reason': localReason,
    if (diagnostic != null) 'diagnostic': diagnostic!.toJson(),
    if (authStage != null) 'stage': authStage!.wireName,
    if (authReason != null) 'reason': authReason!.wireName,
    if (relatedIssueId != null) 'related_issue_id': relatedIssueId,
    'time': timestamp.toUtc().toIso8601String(),
    if (route != null) 'route': route!.name,
    if (requestedPolicy != null) 'requested_policy': requestedPolicy!.name,
    if (recoveryAttempts != null) 'recovery_attempts': recoveryAttempts,
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
        final reconciled =
            !item.containsKey('code') &&
            operation == DiagnosticOperation.initialization &&
            item['local_reason'] == 'material_transaction_reconciled';
        if (time == null ||
            time.isBefore(
              DateTime.now().toUtc().subtract(const Duration(days: 7)),
            ) ||
            (code == null && !reconciled) ||
            operation == null) {
          continue;
        }
        _history.add({
          'time': time.toUtc().toIso8601String(),
          if (code != null) 'code': code.wireName,
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
          if (RoutePolicy.values.any((v) => v.name == item['requested_policy']))
            'requested_policy': item['requested_policy'],
          if (item['recovery_attempts'] is int &&
              (item['recovery_attempts'] as int) >= 0)
            'recovery_attempts': item['recovery_attempts'],
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
          if (_localReasons.contains(item['local_reason']))
            'local_reason': item['local_reason'],
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

  /// 记录已提交的启动对账，返回撤销后应显示的登录提示。
  UiError? recordMaterialRecovery(
    MaterialTransactionRecovery recovery, {
    required DiagnosticInitializationStage stage,
  }) {
    if (recovery == MaterialTransactionRecovery.reconciled) {
      _append(
        DiagnosticRecord._(
          issueId: 'UBAA-$_runId-${++_sequence}',
          operation: DiagnosticOperation.initialization,
          code: null,
          kind: UbaaErrorKind.internal,
          retryable: false,
          cause: DiagnosticCause.none,
          localReason: 'material_transaction_reconciled',
          initializationStage: stage,
          timestamp: DateTime.now().toUtc(),
          source: const [],
        ),
      );
      return null;
    }
    return record(
      operation: DiagnosticOperation.initialization,
      initializationStage: stage,
      cause: recovery,
      error: const UiError(
        code: UbaaErrorCode.authenticationRequired,
        kind: UbaaErrorKind.authentication,
        title: '请重新登录',
        message: '本地登录状态已失效，请重新登录',
      ),
    );
  }

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
    RoutePolicy? requestedPolicy,
    int? recoveryAttempts,
    DiagnosticInitializationStage? initializationStage,
  }) {
    final issueId = 'UBAA-$_runId-${++_sequence}';
    _append(
      DiagnosticRecord._(
        issueId: issueId,
        operation: operation,
        code: error.code,
        kind: error.kind,
        retryable: error.retryable,
        route: error.resolvedRoute,
        requestedPolicy: requestedPolicy,
        recoveryAttempts: recoveryAttempts,
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
        cause:
            error.code == UbaaErrorCode.timeout &&
                error.kind == UbaaErrorKind.internal &&
                error.diagnostic?.isCacheBusy == true
            ? DiagnosticCause.cacheBusy
            : _classify(cause),
        localReason: _localReason(cause),
        timestamp: DateTime.now().toUtc(),
        source: _safeSource(stackTrace),
      ),
    );
    return error.withIssueId(issueId);
  }

  void _append(DiagnosticRecord record) {
    _records.add(record);
    while (_records.length > _capacity) {
      _records.removeFirst();
    }
    _persist();
  }

  String exportText({String? issueId}) {
    final related = _relatedIssueIds(issueId);
    bool selected(Map<String, Object?> event) =>
        issueId == null ||
        related.contains(event['issue_id']) ||
        related.contains(event['related_issue_id']);
    final history = _history.where(selected).toList(growable: false);
    final current = _records
        .map((event) => event.toJson())
        .where(selected)
        .toList(growable: false);
    return const JsonEncoder.withIndent('  ').convert({
      'schema_version': 3,
      if (_appVersion != null) 'app_version': _appVersion,
      if (_platform != null) 'platform': _platform,
      if (issueId == null && history.isNotEmpty) 'previous_events': history,
      'events': issueId == null ? current : [...history, ...current],
    });
  }

  Set<String?> _relatedIssueIds(String? issueId) {
    if (issueId == null) return <String?>{null};
    final events = <Map<String, Object?>>[
      ..._history,
      ..._records.map((event) => event.toJson()),
    ];
    final ids = <String>{issueId};
    var changed = true;
    while (changed) {
      changed = false;
      for (final event in events) {
        final eventId = event['issue_id'];
        final relatedId = event['related_issue_id'];
        if (eventId is String && ids.contains(eventId) && relatedId is String) {
          changed |= ids.add(relatedId);
        }
        if (relatedId is String &&
            ids.contains(relatedId) &&
            eventId is String) {
          changed |= ids.add(eventId);
        }
      }
    }
    return ids;
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

final _localReasons = <String>{
  for (final permission in PlatformPermission.values)
    for (final status in PlatformPermissionStatus.values)
      'permission_${permission.name}_${status.name}',
  for (final code in CredentialVaultErrorCode.values) 'credential_${code.name}',
  'material_transaction_uncertain',
  'material_transaction_unrecoverable',
  'material_transaction_reconciled',
  'material_transaction_reset',
  'material_coordination_unavailable',
  'agenda_file_save_failed',
  for (final failure in AgendaFailure.values) 'agenda_${failure.name}',
};

String? _localReason(Object? cause) => switch (cause) {
  PlatformCapabilityException(:final permission, :final status) =>
    'permission_${permission.name}_${status.name}',
  CredentialVaultException(:final code) => 'credential_${code.name}',
  MaterialTransactionUnrecoverable() => 'material_transaction_unrecoverable',
  MaterialTransactionRecovery.reset => 'material_transaction_reset',
  SecureMaterialCoordinationException(:final uncertain) ||
  MaterialCoordinationException(:final uncertain) =>
    uncertain
        ? 'material_transaction_uncertain'
        : 'material_coordination_unavailable',
  AgendaFileException() => 'agenda_file_save_failed',
  AgendaException(:final failure) => 'agenda_${failure.name}',
  _ => null,
};

DiagnosticCause _classify(Object? cause) => switch (cause) {
  null => DiagnosticCause.none,
  PlatformCapabilityException() => DiagnosticCause.platformCapability,
  AgendaException(failure: AgendaFailure.busy) => DiagnosticCause.cacheBusy,
  AgendaException() => DiagnosticCause.agenda,
  AgendaFileException() => DiagnosticCause.file,
  MaterialCoordinationException() => DiagnosticCause.secureMaterial,
  MaterialTransactionRecovery.reset => DiagnosticCause.secureMaterial,
  CredentialVaultException() => DiagnosticCause.credentialStorage,
  SecureMaterialException() => DiagnosticCause.secureMaterial,
  TimeoutException() => DiagnosticCause.timeout,
  FormatException() => DiagnosticCause.format,
  StateError() => DiagnosticCause.state,
  ArgumentError() => DiagnosticCause.argument,
  AssertionError() => DiagnosticCause.assertion,
  TypeError() => DiagnosticCause.type,
  UiError error => _classifyCode(error.code),
  _ => DiagnosticCause.unknown,
};

DiagnosticCause _classifyCode(UbaaErrorCode code) => switch (code) {
  UbaaErrorCode.operationConflict ||
  UbaaErrorCode.intentExpired => DiagnosticCause.operationConflict,
  UbaaErrorCode.authenticationRequired ||
  UbaaErrorCode.invalidCredentials ||
  UbaaErrorCode.passwordRiskConfirmationFailed =>
    DiagnosticCause.authentication,
  UbaaErrorCode.permissionDenied => DiagnosticCause.permission,
  UbaaErrorCode.networkError ||
  UbaaErrorCode.timeout => DiagnosticCause.network,
  UbaaErrorCode.upstreamUnavailable ||
  UbaaErrorCode.businessUnavailable ||
  UbaaErrorCode.businessRejected ||
  UbaaErrorCode.upstreamChanged ||
  UbaaErrorCode.outcomeUnknown => DiagnosticCause.upstream,
  UbaaErrorCode.parseError => DiagnosticCause.parse,
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
      .map((m) => m.group(0)!)
      .toSet()
      .take(8)
      .toList(growable: false);
}
