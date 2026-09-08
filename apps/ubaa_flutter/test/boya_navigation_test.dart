import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../integration_test/ui_boya/backend.dart';

void main() {
  testWidgets('已选博雅详情不新增读取，准备取消后仍回到同一详情', (tester) async {
    final backend = await _open(tester);
    final count = backend.boyaReads.length;
    await _tap(tester, find.widgetWithText(Card, '合成已选课 1'));
    expect(find.widgetWithText(AppBar, '课程详情'), findsOneWidget);
    expect(backend.boyaReads, hasLength(count));
    await _tap(tester, find.widgetWithText(OutlinedButton, '准备退选'));
    expect(backend.preparedBoya, [
      (WriteOperation.bykcDeselectCourse, 101, null),
    ]);
    await _tap(tester, find.widgetWithText(OutlinedButton, '取消'));
    expect(find.widgetWithText(AppBar, '课程详情'), findsOneWidget);
    expect(find.text('签到信息'), findsOneWidget);
    await _tap(tester, find.byTooltip('返回'));
    expect(find.widgetWithText(Card, '合成已选课 1'), findsOneWidget);
    expect(backend.commitCalls, 0);
  });
  testWidgets('已选记录刷新为空后详情和返回列表都不能复活旧动作', (tester) async {
    final backend = await _open(tester);
    await _tap(tester, find.widgetWithText(Card, '合成已选课 1'));
    backend.emptyNext = true;
    final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    await shell.onFeatureQuery!(
      FeatureId.bykc,
      const FeatureQuery(view: FeatureQueryView.bykcChosenCourses),
    );
    await tester.pumpAndSettle();
    expect(find.text('准备退选'), findsNothing);
    await _tap(tester, find.byTooltip('返回'));
    expect(find.widgetWithText(Card, '合成已选课 1'), findsNothing);
    expect(backend.preparedBoya, isEmpty);
    expect(backend.commitCalls, 0);
  });
}

Future<BoyaBackend> _open(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(402, 874);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final backend = BoyaBackend();
  await tester.pumpWidget(
    UbaaFlutterApp(
      backend: backend,
      credentialVault: MemoryCredentialVault(),
      initialTab: 1,
    ),
  );
  await tester.pumpAndSettle();
  await _tap(tester, find.widgetWithText(Card, FeatureId.bykc.title));
  await _tap(tester, find.widgetWithText(Card, '我的课程'));
  return backend;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
