import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../integration_test/ui_sports/backend.dart';

void main() {
  testWidgets('阳光仅进入可见页面后补记录，隐藏后刷新不自动追加查询', (tester) async {
    final backend = await _mount(tester);
    expect(backend.queries, isEmpty);
    await _tap(tester, find.widgetWithText(Card, FeatureId.ygdk.title));
    expect(backend.queries, hasLength(1));
    expect(find.text('合成运动记录 1'), findsOneWidget);
    await _tap(tester, find.byTooltip('返回'));
    final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    await shell.onRefresh();
    await tester.pumpAndSettle();
    expect(backend.queries, hasLength(1));
  });
  testWidgets('阳光加载更多追加记录，向上滚动仍保留首批记录', (tester) async {
    final backend = await _mount(tester, state: 'many');
    await _tap(tester, find.widgetWithText(Card, FeatureId.ygdk.title));
    await tester.scrollUntilVisible(
      find.text('加载更多'),
      300,
      scrollable: find.byType(Scrollable).hitTestable().last,
      maxScrolls: 40,
    );
    await _tap(tester, find.text('加载更多'));
    expect(backend.queries.last.page, 2);
    await tester.scrollUntilVisible(
      find.text('合成运动记录 40'),
      300,
      scrollable: find.byType(Scrollable).hitTestable().last,
      maxScrolls: 40,
    );
    expect(find.text('合成运动记录 40'), findsOneWidget);
    await tester.drag(
      find.byType(Scrollable).hitTestable().last,
      const Offset(0, 30000),
    );
    await tester.pumpAndSettle();
    expect(find.text('合成运动记录 1'), findsOneWidget);
  });
  testWidgets('阳光写后固定路线回读直接更新首页记录，不触发额外Auto查询', (tester) async {
    final backend = await _mount(tester);
    await _tap(tester, find.widgetWithText(Card, FeatureId.ygdk.title));
    backend.recordVersion = 2;
    final reads = backend.queries.length;
    final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    await shell.onRefreshYgdkAfterWrite!(expectedRoute: ConnectionMode.direct);
    await tester.pumpAndSettle();
    expect(backend.queries, hasLength(reads));
    expect(backend.pinnedReads, ['overview:direct', 'records:direct:1:20']);
    expect(find.text('合成运动记录 1 更新2'), findsOneWidget);
    expect(backend.commitCalls, 0);
  });
}

Future<SportsBackend> _mount(
  WidgetTester tester, {
  String state = 'normal',
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(402, 874);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final backend = SportsBackend(state: state);
  await tester.pumpWidget(
    UbaaFlutterApp(
      backend: backend,
      credentialVault: MemoryCredentialVault(),
      photoPicker: MemoryPhotoPicker(),
      permissionGateway: MemoryPermissionGateway(),
      initialTab: 2,
    ),
  );
  await tester.pumpAndSettle();
  return backend;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
