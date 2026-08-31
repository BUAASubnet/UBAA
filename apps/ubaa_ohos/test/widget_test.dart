import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_ohos/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  testWidgets('OHOS 薄宿主使用共享登录界面', (tester) async {
    await tester.pumpWidget(
      UbaaOhosApp(
        backend: DemoBackend(loginDelay: Duration.zero),
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('UBAA 登录'), findsOneWidget);
  });
}
