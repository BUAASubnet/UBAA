import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  testWidgets('启动后展示登录表单并可进入主页', (tester) async {
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: DemoBackend(loginDelay: Duration.zero),
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('UBAA 登录'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '2020000000');
    await tester.enterText(find.byType(TextField).at(1), 'demo-password');
    await tester.pump();
    final loginButton = find.widgetWithText(FilledButton, '登录');
    expect(tester.widget<FilledButton>(loginButton).onPressed, isNotNull);
    await tester.tap(loginButton);
    await tester.pumpAndSettle();
    expect(find.text('主页'), findsWidgets);
    expect(find.text('课表查询'), findsOneWidget);
  });
}
