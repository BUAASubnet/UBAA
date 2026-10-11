import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('初始化白名单分类与诊断编号保留而异常正文不可进入报告', () {
    final diagnostics = LocalDiagnostics();
    for (final failure in InitializationFailure.values) {
      final error = const UiErrorMapper().fromException(
        InitializationException(failure),
      );
      final recorded = diagnostics.record(
        operation: DiagnosticOperation.initialization,
        error: error,
        cause: StateError('/private/token=synthetic'),
      );
      expect(recorded.initializationFailure, failure);
      expect(recorded.issueId, startsWith('UBAA-'));
      expect(recorded.actionLabel, '重新打开');
    }
    final text = diagnostics.exportText();
    expect(text, isNot(contains('/private')));
    final events = (jsonDecode(text) as Map)['events'] as List;
    expect(
      events.map((e) => e['initialization_failure']).toSet(),
      InitializationFailure.values.map((e) => e.name).toSet(),
    );
  });
}
