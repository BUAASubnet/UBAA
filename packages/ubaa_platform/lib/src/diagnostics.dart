import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:ubaa_domain/ubaa_domain.dart';

/// 本地排障阶段。记录的是程序操作，不接收用户输入或业务目标。
enum DiagnosticOperation {
  initialization,
  login,
  routeChange,
  logout,
  read,
  writePrepare,
  writeCommit,
  writeDiscard,
  readback,
  telemetry,
  disposal,
}

/// 只依赖异常类型，绝不通过异常正文猜测原因。
enum DiagnosticCause {
  none,
  timeout,
  format,
  state,
  argument,
  assertion,
  type,
  unknown,
}

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
    this.latency,
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
  final Duration? latency;

  Map<String, Object?> toJson() => {
    'issue_id': issueId,
    'operation': operation.name,
    'code': code.wireName,
    'kind': kind.name,
    'retryable': retryable,
    'cause': cause.name,
    'time': timestamp.toUtc().toIso8601String(),
    if (route != null) 'route': route!.name,
    if (feature != null) 'feature': feature!.wireName,
    if (latency != null) 'latency_ms': latency!.inMilliseconds,
    if (source.isNotEmpty) 'source': source,
  };
}

/// 默认仅在本次运行的内存中保存，用户主动复制；没有文件或网络出口。
final class LocalDiagnostics {
  LocalDiagnostics({int capacity = 100}) : _capacity = capacity {
    if (capacity < 1 || capacity > 1000) {
      throw ArgumentError.value(capacity, 'capacity', '必须在 1 至 1000 之间');
    }
  }

  static int _runSequence = 0;
  final int _capacity;
  final String _runId =
      '${DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36)}-${++_runSequence}';
  final Queue<DiagnosticRecord> _records = Queue();
  int _sequence = 0;

  List<DiagnosticRecord> get records => List.unmodifiable(_records);

  UiError record({
    required DiagnosticOperation operation,
    required UiError error,
    FeatureId? feature,
    Duration? latency,
    Object? cause,
    StackTrace? stackTrace,
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
        latency: latency,
        cause: _classify(cause),
        timestamp: DateTime.now().toUtc(),
        source: _safeSource(stackTrace),
      ),
    );
    while (_records.length > _capacity) {
      _records.removeFirst();
    }
    return error.withIssueId(issueId);
  }

  String exportText() => const JsonEncoder.withIndent('  ').convert({
    'schema_version': 1,
    'events': _records.map((event) => event.toJson()).toList(growable: false),
  });

  void clear() => _records.clear();
}

DiagnosticCause _classify(Object? cause) => switch (cause) {
  null => DiagnosticCause.none,
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
