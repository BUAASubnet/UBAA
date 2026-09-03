part of '../app_flow_test.dart';

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

    expect(find.text('课表查询'), findsOneWidget);
    await tester.tap(find.text('课表查询'));
    await tester.pumpAndSettle();
    expect(find.text('集成测试课程'), findsOneWidget);

    final queryMenu = find.byType(DropdownButton<FeatureQueryView>);
    expect(queryMenu, findsOneWidget);
    await tester.tap(queryMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('周课表').last);
    await tester.pumpAndSettle();

    final termField = find.widgetWithText(TextField, '学期编码（可选）');
    final weekField = find.widgetWithText(TextField, '周次（可选）');
    expect(termField, findsOneWidget);
    expect(weekField, findsOneWidget);
    await tester.enterText(termField, '2026-2027-1');
    await tester.enterText(weekField, '3');
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();

    expect(backend.lastQuery?.view, FeatureQueryView.scheduleWeek);
    expect(backend.lastQuery?.term, '2026-2027-1');
    expect(backend.lastQuery?.week, 3);
    expect(find.text('查询后的课程'), findsOneWidget);

    await tester.tap(find.text('返回功能列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.text('直连'), findsOneWidget);
  });
}
