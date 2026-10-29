import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../../support/bykc/backend.dart';

void main() {
  testWidgets('课程列表选课和确认退选后刷新原列表，不跳详情或已选页', (tester) async {
    final backend = await _open(tester, chosen: false);
    Finder action(String label) => find.descendant(
      of: find.widgetWithText(Card, '合成课程 1'),
      matching: find.widgetWithText(OutlinedButton, label),
    );
    await _tap(tester, action('选课'));
    expect(backend.commitCalls, 1);
    expect(backend.selections[101], isTrue);
    expect(find.widgetWithText(AppBar, FeatureId.bykc.title), findsOneWidget);
    expect(backend.boyaReads.last.view, FeatureQueryView.summary);
    await _tap(tester, action('退选'));
    expect(backend.commitCalls, 1);
    await _tap(tester, find.text('确认退选'));
    expect(backend.commitCalls, 2);
    expect(backend.selections[101], isFalse);
    expect(find.widgetWithText(AppBar, FeatureId.bykc.title), findsOneWidget);
    expect(
      backend.boyaReads.where(
        (query) => query.view == FeatureQueryView.bykcDetail,
      ),
      isEmpty,
    );
    expect(action('选课'), findsOneWidget);
  });
  testWidgets('已选博雅详情确认退选后移除记录并保留返回路径', (tester) async {
    final backend = await _open(tester);
    final count = backend.boyaReads.length;
    await _tap(tester, find.widgetWithText(Card, '合成已选课 1'));
    expect(find.widgetWithText(AppBar, '课程详情'), findsOneWidget);
    expect(backend.boyaReads, hasLength(count + 1));
    expect(backend.boyaReads.last.view, FeatureQueryView.bykcChosenCourses);
    expect(backend.boyaReads.last.courseId, '101');
    expect(find.text('合成课程联系人'), findsOneWidget);
    await _tap(tester, find.widgetWithText(OutlinedButton, '退选'));
    expect(backend.preparedBoya, isEmpty);
    await _tap(tester, find.text('确认退选'));
    expect(backend.preparedBoya, [
      (WriteOperation.bykcDeselectCourse, 101, null),
    ]);

    expect(find.widgetWithText(AppBar, '课程详情'), findsOneWidget);
    expect(find.text('签到信息'), findsNothing);
    await _tap(tester, find.byTooltip('返回'));
    expect(find.widgetWithText(Card, '合成已选课 1'), findsNothing);
    expect(find.widgetWithText(AppBar, FeatureId.bykc.title), findsOneWidget);
    expect(backend.commitCalls, 1);
  });
  testWidgets('详情选课后返回原课程列表', (tester) async {
    final backend = await _open(tester, chosen: false);
    await _tap(tester, find.widgetWithText(Card, '合成课程 1'));
    await _tap(tester, find.widgetWithText(OutlinedButton, '选课'));
    expect(backend.commitCalls, 1);
    await _tap(tester, find.byTooltip('返回'));
    expect(find.widgetWithText(AppBar, FeatureId.bykc.title), findsOneWidget);
    expect(find.widgetWithText(Card, '合成课程 1'), findsOneWidget);
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
    expect(find.text('退选'), findsNothing);
    await _tap(tester, find.byTooltip('返回'));
    expect(find.widgetWithText(Card, '合成已选课 1'), findsNothing);
    expect(backend.preparedBoya, isEmpty);
    expect(backend.commitCalls, 0);
  });
}

Future<BoyaBackend> _open(WidgetTester tester, {bool chosen = true}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(402, 874);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final backend = BoyaBackend();
  await tester.pumpWidget(
    UbaaFlutterApp(
      backend: backend,
      credentialVault: MemoryCredentialVault(),
      initialDestination: UiDestination.coursework,
    ),
  );
  await tester.pumpAndSettle();
  await _tap(tester, find.widgetWithText(Card, FeatureId.bykc.title));
  if (chosen) {
    await _tap(
      tester,
      find.descendant(
        of: find.byType(SegmentedButton<FeatureQueryView>),
        matching: find.text('已选'),
      ),
    );
  }
  return backend;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
