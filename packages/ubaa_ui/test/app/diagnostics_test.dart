import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('错误卡展示关联编号并只复制安全字段', (tester) async {
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
    expect(find.textContaining('UBAA-fixture-1'), findsOneWidget);
    expect(find.text('错误代码：parse_error'), findsOneWidget);
    await tester.tap(find.text('复制错误信息'));
    await tester.pumpAndSettle();
    expect(copied, contains('parse_error'));
    expect(copied, contains('UBAA-fixture-1'));
    expect(copied, contains('webvpn'));
    expect(copied, isNot(contains('原始内容')));
  });
}
