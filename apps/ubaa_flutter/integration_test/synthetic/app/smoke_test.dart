import 'package:integration_test/integration_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_test_support/ubaa_test_support.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('官方宿主完成登录并显示首页', (tester) async {
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
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, '首页'), findsOneWidget);
    expect(find.text('今日课表'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
