import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_ui/src/common/error_card.dart'
    show uiDiagnosticsGuidance, uiErrorMessageRestatesTitle;

void main() {
  testWidgets('诊断信息只分享完整诊断，不在界面展示内容且等待系统面板期间禁止重复打开', (tester) async {
    final pending = Completer<String?>();
    var calls = 0;
    String? shared;
    await tester.pumpWidget(
      MaterialApp(
        home: UiDiagnosticsScope(
          exportReport: (report) {
            calls++;
            shared = report;
            return pending.future;
          },
          exportLabel: '分享完整诊断',
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => uiShowDiagnosticsDialog(
                  context,
                  () =>
                      '{"schema_version":3,"events":[{"issue_id":"UBAA-test"}]}',
                ),
                child: const Text('打开诊断'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开诊断'));
    await tester.pumpAndSettle();
    expect(find.textContaining('UBAA-test'), findsNothing);
    await tester.tap(find.text('分享完整诊断'));
    await tester.pump();
    await tester.tap(find.text('分享完整诊断'));
    expect(calls, 1);
    expect(shared, contains('UBAA-test'));
    pending.completeError(StateError('模拟系统分享失败'));
    await tester.pumpAndSettle();
    expect(find.text('诊断未能导出，请重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('错误卡展开后只显示编号并指引到设置分享，不导出记录', (tester) async {
    var exports = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: UiDiagnosticsScope(
          exportReport: (_) async {
            exports++;
            return null;
          },
          child: const Scaffold(
            body: FriendlyErrorCard(
              error: UiError(
                code: UbaaErrorCode.parseError,
                kind: UbaaErrorKind.parse,
                title: '数据异常',
                message: '请反馈错误编号',
                issueId: 'UBAA-fixture-1',
                technicalDetail: '严禁展示的原始内容',
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('UBAA-fixture-1'), findsNothing);
    await tester.tap(find.text('错误详情'));
    await tester.pumpAndSettle();
    expect(find.text('错误编号：UBAA-fixture-1'), findsOneWidget);
    expect(find.text('错误代码：parse_error'), findsOneWidget);
    expect(find.text(uiDiagnosticsGuidance), findsOneWidget);
    expect(find.textContaining('原始内容'), findsNothing);
    expect(exports, 0);
  });

  testWidgets('写入失败短提示的错误详情显示编号并指引到设置分享', (tester) async {
    var exports = 0;
    const error = UiError(
      code: UbaaErrorCode.outcomeUnknown,
      title: '结果待核实',
      message: '请先核对结果',
      issueId: 'UBAA-expired',
      technicalDetail: '不应展示的模拟正文',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: UiDiagnosticsScope(
          exportReport: (_) async {
            exports++;
            return null;
          },
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => UbaaFeedback.showOutcome(
                  context,
                  const WriteOutcome(
                    operation: WriteOperation.bykcSelectCourse,
                    message: '请先核对结果',
                    result: WriteCommitResult(
                      operation: WriteOperation.bykcSelectCourse,
                      success: false,
                      message: '请先核对结果',
                      outcomeUnknown: true,
                    ),
                    resultError: error,
                  ),
                ),
                child: const Text('模拟写入'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('模拟写入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('错误详情'));
    await tester.pumpAndSettle();
    expect(find.text('错误编号：UBAA-expired'), findsOneWidget);
    expect(find.text(uiDiagnosticsGuidance), findsOneWidget);
    expect(find.textContaining('模拟正文'), findsNothing);
    expect(exports, 0);
  });

  test('错误说明只是重复标题时不再显示', () {
    expect(uiErrorMessageRestatesTitle('服务暂不可用', '服务暂时不可用，请稍后重试'), isTrue);
    expect(uiErrorMessageRestatesTitle('读取失败', '请检查网络后重试'), isFalse);
  });
}
