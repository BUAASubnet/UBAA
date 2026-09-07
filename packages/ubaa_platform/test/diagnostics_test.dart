import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
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
        '#1 external (file:///Users/private/person.dart:2:1)\n'
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
