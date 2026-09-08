import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../integration_test/ui_rooms/backend.dart';

void main() {
  testWidgets('研讨室输入第2页及前后页按钮保留零基读取与一基显示', (tester) async {
    final backend = await _open(tester);
    await _tap(tester, find.byTooltip('返回'));
    await _tap(tester, find.widgetWithText(Card, '我的预约'));
    expect(backend.roomReads.last.page, 0);
    await _tap(tester, find.byTooltip('搜索与筛选'));
    await tester.enterText(find.widgetWithText(TextField, '每页数量'), '1');
    await tester.enterText(find.widgetWithText(TextField, '页码'), '2');
    await _tap(tester, find.text('应用筛选'));
    expect(backend.roomReads.last.page, 1);
    await _tap(tester, find.widgetWithText(TextButton, '完成'));
    expect(find.text('第 2 / 3 页（共 3 条）'), findsOneWidget);
    await _tap(tester, find.byTooltip('上一页'));
    expect(backend.roomReads.last.page, 0);
    expect(find.text('第 1 / 3 页（共 3 条）'), findsOneWidget);
    await _tap(tester, find.byTooltip('下一页'));
    expect(backend.roomReads.last.page, 1);
    expect(find.text('第 2 / 3 页（共 3 条）'), findsOneWidget);
    await _tap(tester, find.byTooltip('搜索与筛选'));
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '页码'))
          .controller!
          .text,
      '2',
    );
    expect(backend.commitCalls, 0);
  });
  testWidgets('研讨室隐藏后首页刷新只读取站点不自动扩展日期空间', (tester) async {
    final backend = await _open(tester, width: 1280);
    await _tap(tester, find.byIcon(Icons.home_outlined));
    final before = backend.roomReads.length;
    await _tap(tester, find.byTooltip('刷新'));
    expect(backend.roomReads, hasLength(before + 1));
    expect(backend.roomReads.last.view, FeatureQueryView.summary);
  });
  testWidgets('研讨室换日期清掉旧选择和表单目标且不增加返回层级', (tester) async {
    final backend = await _open(tester);
    await _tap(tester, find.byTooltip('合成研讨室 1 08:00–09:00'));
    expect(find.text('下一步'), findsOneWidget);
    await _tap(tester, find.widgetWithText(FilterChip, '2026-09-05'));
    expect(find.text('下一步'), findsNothing);
    expect(backend.roomReads.last.siteId, 7);
    expect(backend.roomReads.last.date, DateTime(2026, 9, 5));
    await _tap(tester, find.byTooltip('返回'));
    expect(find.widgetWithText(Card, '我的预约'), findsOneWidget);
    expect(backend.preparedRooms, isEmpty);
    expect(backend.commitCalls, 0);
  });
  testWidgets('研讨室明确空结果后刷新不复活已清掉的时段', (tester) async {
    final backend = await _open(tester);
    await _tap(tester, find.byTooltip('合成研讨室 1 08:00–09:00'));
    backend.emptyNext = true;
    await _tap(tester, find.byTooltip('刷新当前查询'));
    expect(find.text('下一步'), findsNothing);
    await _tap(tester, find.byTooltip('刷新当前查询'));
    expect(find.text('下一步'), findsNothing);
  });
  testWidgets('研讨室手填选择器采用typed站点而非兼容字段999', (tester) async {
    final backend = await _open(tester);
    await _tap(tester, find.byTooltip('搜索与筛选'));
    final picker = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(picker.items!.map((item) => item.value), ['7']);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '日期'))
          .controller!
          .text,
      '2026-09-04',
    );
    final count = backend.roomReads.length;
    await tester.enterText(find.widgetWithText(TextField, '站点 ID'), '17');
    await _tap(tester, find.widgetWithText(TextButton, '完成'));
    await _tap(tester, find.byTooltip('搜索与筛选'));
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '站点 ID'))
          .controller!
          .text,
      '17',
    );
    expect(backend.roomReads, hasLength(count));
  });
}

Future<RoomBackend> _open(WidgetTester tester, {double width = 402}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 874);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final backend = RoomBackend();
  await tester.pumpWidget(
    UbaaFlutterApp(
      backend: backend,
      credentialVault: MemoryCredentialVault(),
      initialTab: 2,
    ),
  );
  await tester.pumpAndSettle();
  await _tap(tester, find.widgetWithText(Card, FeatureId.cgyy.title));
  await _tap(tester, find.widgetWithText(Card, '预约研讨室'));
  return backend;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
