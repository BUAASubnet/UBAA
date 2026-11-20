import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('权限拒绝与认证失败分别归类', () {
    final diagnostics = LocalDiagnostics();
    for (final code in ['permission_denied', 'authentication_required']) {
      final error = mapCoreError(code: code);
      diagnostics.record(
        operation: DiagnosticOperation.read,
        error: error,
        cause: error,
      );
    }
    expect(diagnostics.records.map((r) => r.cause.name), [
      'permission',
      'authentication',
    ]);
  });

  test('原生权限和凭据失败保留固定原因并跨重启导出', () async {
    final storage = MemoryPreferenceValues();
    final diagnostics = LocalDiagnostics(storage: storage);
    for (final cause in [
      const PlatformCapabilityException(
        PlatformPermission.camera,
        PlatformPermissionStatus.denied,
      ),
      const CredentialVaultException(CredentialVaultErrorCode.storageFailure),
      const SecureMaterialCoordinationException(true),
      const MaterialTransactionUnrecoverable(),
    ]) {
      diagnostics.record(
        operation: DiagnosticOperation.initialization,
        error: const UiErrorMapper().fromException(cause),
        cause: cause,
      );
    }
    diagnostics.recordMaterialRecovery(
      MaterialTransactionRecovery.reconciled,
      stage: DiagnosticInitializationStage.platformCapabilities,
    );
    diagnostics.recordMaterialRecovery(
      MaterialTransactionRecovery.reset,
      stage: DiagnosticInitializationStage.platformCapabilities,
    );
    await diagnostics.flushed;
    final restarted = LocalDiagnostics(storage: storage);
    await restarted.flushed;
    final events =
        jsonDecode(restarted.exportText())['previous_events'] as List;
    expect(events.map((e) => e['local_reason']), [
      'permission_camera_denied',
      'credential_storageFailure',
      'material_transaction_uncertain',
      'material_transaction_unrecoverable',
      'material_transaction_reconciled',
      'material_transaction_reset',
    ]);
    expect(events[4], isNot(contains('code')));
    expect(events[5]['code'], 'authentication_required');
  });

  test('已映射的业务错误保留分类和去重后的完整项目调用链', () {
    final diagnostics = LocalDiagnostics();
    const error = UiError(
      code: UbaaErrorCode.operationConflict,
      title: '冲突',
      message: 'PRIVATE',
    );
    diagnostics.record(
      operation: DiagnosticOperation.read,
      error: error,
      cause: error,
      stackTrace: StackTrace.fromString(
        [
          'package:ubaa_app/src/bridge/read.dart:1',
          'package:ubaa_app/src/bridge/read.dart:1',
          'package:ubaa_app/src/cache.dart:2',
          'package:ubaa_app/src/controller.dart:3',
          'package:ubaa_ui/src/grades.dart:4',
        ].join('\n'),
      ),
    );
    final event =
        (jsonDecode(diagnostics.exportText())['events'] as List).single;
    expect(event['cause'], 'operationConflict');
    expect(event['source'], contains('package:ubaa_ui/src/grades.dart:4'));
    expect(
      event['source'].where(
        (v) => v == 'package:ubaa_app/src/bridge/read.dart:1',
      ),
      hasLength(1),
    );
    expect(diagnostics.exportText(), isNot(contains('PRIVATE')));
  });

  test('业务错误保留类型来源和最深业务调用点', () {
    final diagnostics = LocalDiagnostics();
    diagnostics.record(
      operation: DiagnosticOperation.read,
      error: mapCoreError(code: 'operation_conflict'),
      cause: mapCoreError(code: 'operation_conflict'),
      stackTrace: StackTrace.fromString(
        '#0 dispatch (package:ubaa_app/src/bridge/read/dispatch.dart:56:7)\n'
        '#1 cache (package:ubaa_app/src/bridge/cache/lifecycle.dart:41:9)\n'
        '#2 run (package:ubaa_app/src/controller/read_scheduler.dart:122:3)\n'
        '#3 grades (package:ubaa_app/src/bridge/features/academic/reader.dart:97:2)',
      ),
    );
    final event = (jsonDecode(diagnostics.exportText()) as Map)['events'][0];
    expect(event['cause'], 'operationConflict');
    expect(
      event['source'],
      contains(
        'package:ubaa_app/src/bridge/features/academic/reader.dart:97:2',
      ),
    );
  });

  test('重启后的单项报告包含完整关联链', () async {
    final storage = MemoryPreferenceValues();
    final first = LocalDiagnostics(storage: storage);
    final original = first.record(
      operation: DiagnosticOperation.read,
      error: mapCoreError(code: 'authentication_required'),
    );
    final recovery = first.record(
      operation: DiagnosticOperation.login,
      error: mapCoreError(code: 'timeout'),
      relatedIssueId: original.issueId,
    );
    final retry = first.record(
      operation: DiagnosticOperation.read,
      error: mapCoreError(code: 'parse_error'),
      relatedIssueId: recovery.issueId,
    );
    await first.flushed;
    final restarted = LocalDiagnostics(storage: storage);
    await restarted.flushed;
    final report =
        jsonDecode(restarted.exportText(issueId: retry.issueId)) as Map;
    expect((report['events'] as List).map((e) => e['code']), [
      'authentication_required',
      'timeout',
      'parse_error',
    ]);
  });

  test('重启后保留云打印文件序号和写操作归属', () async {
    final storage = MemoryPreferenceValues();
    final diagnostics = LocalDiagnostics(storage: storage);
    diagnostics.record(
      operation: DiagnosticOperation.cloudPrintUpload,
      fileIndex: 2,
      error: mapCoreError(code: 'network_error'),
    );
    diagnostics.record(
      operation: DiagnosticOperation.writeCommit,
      feature: FeatureId.libbook,
      writeOperation: WriteOperation.libbookReserve,
      error: mapCoreError(code: 'business_unavailable'),
    );
    await diagnostics.flushed;
    final restarted = LocalDiagnostics(storage: storage);
    await restarted.flushed;
    final rows =
        (jsonDecode(restarted.exportText()) as Map)['previous_events'] as List;
    expect(rows[0]['feature'], 'cloud_print');
    expect(rows[0]['file_index'], 2);
    expect(rows[1]['write_operation'], 'libbookReserve');
  });

  test('重启导出应保留错误编号与关联编号', () async {
    final storage = MemoryPreferenceValues();
    final first = LocalDiagnostics(storage: storage);
    final failure = first.record(
      operation: DiagnosticOperation.login,
      error: const UiErrorMapper().fromCore(
        const CoreErrorPayload(
          code: 'upstream_changed',
          authStage: AuthFailureStage.identityValidation,
          authReason: AuthFailureReason.identityMismatch,
        ),
      ),
    );
    first.record(
      operation: DiagnosticOperation.login,
      error: mapCoreError(code: 'network_error'),
      relatedIssueId: failure.issueId,
    );
    await first.flushed;
    final restarted = LocalDiagnostics(storage: storage);
    await restarted.flushed;
    final report = jsonDecode(restarted.exportText()) as Map;
    final previous = report['previous_events'] as List;
    expect(previous[0]['issue_id'], failure.issueId);
    expect(previous[1]['related_issue_id'], failure.issueId);
    expect(previous[0]['reason'], 'identity_mismatch');
  });

  test('复制单次失败包含关联路线与版本并保留安全原因', () {
    final diagnostics = LocalDiagnostics()
      ..setEnvironment(appVersion: '2.0.0+2004', platform: 'android');
    final first = diagnostics.record(
      operation: DiagnosticOperation.login,
      error: const UiErrorMapper().fromCore(
        const CoreErrorPayload(
          code: 'upstream_changed',
          resolvedRoute: ConnectionMode.webvpn,
          authStage: AuthFailureStage.identityValidation,
          authReason: AuthFailureReason.identityMismatch,
          message: '不得进入报告的原始身份',
        ),
      ),
    );
    diagnostics.record(
      operation: DiagnosticOperation.login,
      error: mapCoreError(
        code: 'network_error',
        resolvedRoute: ConnectionMode.direct,
      ),
      relatedIssueId: first.issueId,
    );
    diagnostics.record(
      operation: DiagnosticOperation.read,
      error: mapCoreError(code: 'parse_error'),
    );
    final report =
        jsonDecode(diagnostics.exportText(issueId: first.issueId)) as Map;
    expect(report['events'], hasLength(2));
    expect(report['app_version'], '2.0.0+2004');
    expect(report['platform'], 'android');
    expect(report['events'][0]['stage'], 'identity_validation');
    expect(report['events'][0]['reason'], 'identity_mismatch');
    expect(report.toString(), isNot(contains('原始身份')));
  });

  test('诊断有界保存且编号唯一并提供不可修改快照', () {
    final diagnostics = LocalDiagnostics(capacity: 2);
    final ids = <String>{};
    for (var index = 0; index < 3; index++) {
      ids.add(
        diagnostics
            .record(
              operation: DiagnosticOperation.read,
              error: mapCoreError(code: 'network_error'),
            )
            .issueId!,
      );
    }
    expect(ids, hasLength(3));
    expect(diagnostics.records, hasLength(2));
    expect(() => diagnostics.records.clear(), throwsUnsupportedError);
    expect(diagnostics.records.first.issueId, ids.elementAt(1));
  });

  test('诊断不保留异常正文个人资料或外部堆栈路径', () {
    final diagnostics = LocalDiagnostics();
    final error = diagnostics.record(
      operation: DiagnosticOperation.read,
      feature: FeatureId.schedule,
      error: const UiError(
        code: UbaaErrorCode.parseError,
        kind: UbaaErrorKind.parse,
        title: '姓名：示例用户',
        message: '账号：2099000000',
        technicalDetail: 'https://private.invalid/path?token=synthetic',
        resolvedRoute: ConnectionMode.webvpn,
      ),
      cause: _MustNotFormat(),
      stackTrace: StackTrace.fromString(
        '#0 read (package:ubaa_app/src/controller/app_controller.dart:123:4)\n'
        '#1 external (file:///external-source/person.dart:2:1)\n'
        '#2 secret (https://private.invalid:1:2)',
      ),
    );
    final text = diagnostics.exportText();
    for (final forbidden in ['示例用户', '2099000000', 'private', 'token', '账号']) {
      expect(text, isNot(contains(forbidden)));
    }
    final record = (jsonDecode(text) as Map)['events'].single as Map;
    expect(record['issue_id'], error.issueId);
    expect(record['code'], 'parse_error');
    expect(record['route'], 'webvpn');
    expect(record['feature'], 'schedule');
    expect(record['source'], [
      'package:ubaa_app/src/controller/app_controller.dart:123:4',
    ]);
    expect(record['cause'], 'unknown');
  });

  test('清空诊断不复用编号也不修改已取得快照', () {
    final diagnostics = LocalDiagnostics();
    final first = diagnostics.record(
      operation: DiagnosticOperation.login,
      error: mapCoreError(code: 'timeout'),
    );
    final snapshot = diagnostics.records;
    diagnostics.clear();
    expect(snapshot, hasLength(1));
    expect(diagnostics.records, isEmpty);
    final second = diagnostics.record(
      operation: DiagnosticOperation.login,
      error: mapCoreError(code: 'timeout'),
    );
    expect(second.issueId, isNot(first.issueId));
  });
}

class _MustNotFormat {
  @override
  String toString() => throw StateError('禁止格式化原始异常');
}
