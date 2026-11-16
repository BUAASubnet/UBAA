import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('诊断跨重启保留具体原因且不保存异常正文', () async {
    final store = MemoryPreferenceValues();
    final diagnostics = LocalDiagnostics(storage: store);
    final context = ErrorDiagnostic.parse(
      jsonEncode({
        'source': 'crates/ubaa_core/src/features/http.rs:12',
        'stage': 'response',
        'reason': 'http_server_error',
        'status': 503,
      }),
    );
    diagnostics.record(
      operation: DiagnosticOperation.read,
      error: UiError(
        code: UbaaErrorCode.upstreamUnavailable,
        title: '失败',
        message: '服务不可用',
        diagnostic: context,
      ),
      cause: StateError('token=PRIVATE'),
    );
    await diagnostics.flushed;
    final reopened = LocalDiagnostics(storage: store);
    await reopened.flushed;
    expect(reopened.exportText(), contains('http_server_error'));
    expect(reopened.exportText(), isNot(contains('PRIVATE')));
    reopened.clear();
    await reopened.flushed;
    final cleared = LocalDiagnostics(storage: store);
    await cleared.flushed;
    expect(cleared.exportText(), isNot(contains('http_server_error')));
  });
  test('已确认的上游提示进入界面而未知正文不进入诊断', () {
    final context = ErrorDiagnostic.parse(
      jsonEncode({
        'source': 'crates/ubaa_core/src/features/bykc/parser.rs:30',
        'upstream_message': '报名失败，该课程人数已满',
      }),
    );
    final error = const UiErrorMapper().fromCore(
      CoreErrorPayload(code: 'upstream_changed', diagnostic: context),
    );
    expect(error.message, contains('报名失败，该课程人数已满'));
    expect(
      ErrorDiagnostic.parse(
        jsonEncode({
          'source': 'crates/ubaa_core/src/features/bykc/parser.rs:30',
          'upstream_message': '张三 token=PRIVATE',
        }),
      ),
      isNull,
    );
  });
}
