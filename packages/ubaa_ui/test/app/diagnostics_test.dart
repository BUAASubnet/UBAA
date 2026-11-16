import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_ui/src/common/error_card.dart'
    show uiErrorMessageRestatesTitle;

void main() {
  testWidgets('分享错误报告使用对应记录且等待系统面板期间禁止重复打开', (tester) async {
    final pending = Completer<String?>();
    var calls = 0;
    String? shared;
    await tester.pumpWidget(
      MaterialApp(
        home: UiDiagnosticsScope(
          readRecord: (id) => id == 'UBAA-test'
              ? '{"schema_version":3,"events":[{"issue_id":"UBAA-test"}]}'
              : null,
          exportReport: (report) {
            calls++;
            shared = report;
            return pending.future;
          },
          child: const Scaffold(
            body: FriendlyErrorCard(
              error: UiError(
                code: UbaaErrorCode.networkError,
                title: '连接失败',
                message: '请检查网络',
                issueId: 'UBAA-test',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('错误详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分享报告文件'));
    await tester.pump();
    await tester.tap(find.text('分享报告文件'));
    expect(calls, 1);
    expect(shared, contains('UBAA-test'));
    expect(shared, contains('schema_version'));
    pending.completeError(StateError('模拟系统分享失败'));
    await tester.pumpAndSettle();
    expect(find.text('报告文件未导出，请重试或复制诊断信息'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('错误卡复制对应诊断记录', (tester) async {
    String? requested;
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: UiDiagnosticsScope(
          readRecord: (id) {
            requested = id;
            return '{"schema_version":2,"events":[{"stage":"identity_validation"}]}';
          },
          child: const Scaffold(
            body: FriendlyErrorCard(
              error: UiError(
                code: UbaaErrorCode.upstreamChanged,
                title: '登录失败',
                message: '请反馈诊断',
                issueId: 'UBAA-test',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('错误详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制错误信息'));
    await tester.pumpAndSettle();
    expect(requested, 'UBAA-test');
    expect(copied, contains('identity_validation'));
    expect(copied, contains('schema_version'));
  });

  testWidgets('错误卡按需展开诊断并只复制安全字段', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FriendlyErrorCard(
            error: UiError(
              code: UbaaErrorCode.parseError,
              kind: UbaaErrorKind.parse,
              title: '数据异常',
              message: '请反馈错误编号',
              issueId: 'UBAA-fixture-1',
              resolvedRoute: ConnectionMode.webvpn,
              technicalDetail: '严禁复制的原始内容',
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('UBAA-fixture-1'), findsNothing);
    expect(find.text('错误代码：parse_error'), findsNothing);
    await tester.tap(find.text('错误详情'));
    await tester.pumpAndSettle();
    expect(find.textContaining('UBAA-fixture-1'), findsOneWidget);
    expect(find.text('错误代码：parse_error'), findsOneWidget);
    await tester.tap(find.text('复制错误信息'));
    await tester.pumpAndSettle();
    expect(copied, contains('parse_error'));
    expect(copied, contains('UBAA-fixture-1'));
    expect(copied, contains('webvpn'));
    expect(copied, isNot(contains('原始内容')));
  });

  test('错误说明只是重复标题时不再显示', () {
    expect(uiErrorMessageRestatesTitle('服务暂不可用', '服务暂时不可用，请稍后重试'), isTrue);
    expect(uiErrorMessageRestatesTitle('读取失败', '请检查网络后重试'), isFalse);
  });
}
