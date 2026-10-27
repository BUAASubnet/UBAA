part of '../flow_test.dart';

void _registerAuthFlowTests() {
  testWidgets('宿主集成流程从登录进入详情并传递 typed 查询', (tester) async {
    final backend = _IntegrationBackend();
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('UBAA 登录'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '2020000000');
    await tester.enterText(find.byType(TextField).at(1), 'fixture-password');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    expect(find.byType(UbaaMainShell), findsOneWidget);

    await _openIntegrationFeature(tester, FeatureId.schedule);
    expect(find.text('查询后的课程'), findsOneWidget);
    await _returnToFeatureRoot(tester);
    await uiOpenProfile(tester);
    expect(find.text('2020000000'), findsWidgets);
  });
}
