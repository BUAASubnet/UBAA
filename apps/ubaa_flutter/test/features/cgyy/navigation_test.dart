import 'package:ubaa_ui/ubaa_ui.dart' show UiDestination;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../../../integration_test/synthetic/cgyy/backend.dart';

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets('移动端直接选择时段和清空不增加读取', (tester) async {
    final backend = await _open(tester);
    final count = backend.roomReads.length;
    await _tap(tester, _slot('合成研讨室 1', '08:00–09:00'));
    expect(find.text('已选'), findsOneWidget);
    await _tap(tester, find.text('清空选择'));
    expect(find.text('下一步'), findsNothing);
    expect(backend.roomReads.length, count);
  });
  testWidgets('研讨室长表滚到底仍保留时段表头', (tester) async {
    await _open(tester, state: 'many');
    final header = find.text('08:00–09:00');
    final before = tester.getTopLeft(header);
    await tester.ensureVisible(find.text('合成研讨室 42'));
    await tester.pumpAndSettle();
    expect(header.hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(header), before);
    final heading = find.byKey(const ValueKey('cgyy-time-header-scroll'));
    final body = find.byKey(const ValueKey('cgyy-time-body-scroll'));
    await tester.drag(heading, const Offset(-180, 0));
    await tester.pumpAndSettle();
    final a = tester.widget<SingleChildScrollView>(heading).controller!;
    final b = tester.widget<SingleChildScrollView>(body).controller!;
    expect(a.offset, greaterThan(0));
    expect(b.offset, closeTo(a.offset, .01));
    expect(find.text('合成研讨室 42').hitTestable(), findsOneWidget);
    final previous = b.offset;
    await tester.drag(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                (widget.properties.label?.startsWith('合成研讨室 42 ') ?? false),
          )
          .hitTestable()
          .first,
      const Offset(180, 0),
    );
    await tester.pumpAndSettle();
    expect(b.offset, lessThan(previous));
    expect(a.offset, closeTo(b.offset, .01));
  });

  testWidgets('预约记录滚动续载保留零基请求，刷新从首页重新开始', (tester) async {
    final backend = await _open(tester, state: 'paged');
    await _tap(tester, find.byTooltip('返回'));
    await _tap(tester, find.widgetWithText(Card, '我的预约'));
    expect(backend.roomReads.last.page, 0);
    final scroll = find
        .descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('主题：连续订单144'),
      600,
      scrollable: scroll,
      maxScrolls: 100,
    );
    final reads = backend.roomReads
        .where((q) => q.view == FeatureQueryView.cgyyOrders)
        .toList();
    expect(reads.map((q) => q.page), [0, 1, 2]);
    await _tap(tester, find.byTooltip('刷新当前查询'));
    expect(backend.roomReads.last.page, 0);
    expect(find.text('主题：连续订单101'), findsOneWidget);
    expect(backend.commitCalls, 0);
  });
  testWidgets('研讨室隐藏后首页仅刷新待办订单，不重读站点或扩展日期空间', (tester) async {
    final backend = await _open(tester, width: 1280);
    await _tap(tester, find.byIcon(Icons.home_outlined));
    final before = backend.roomReads.length;
    await _tap(tester, find.byTooltip('刷新'));
    expect(backend.roomReads.skip(before).map((query) => query.view), [
      FeatureQueryView.cgyyOrders,
    ]);
    expect(backend.roomReads.last.page, 0);
    expect(backend.roomReads.last.size, 20);
  });
  testWidgets('研讨室换日期清掉旧选择和表单目标且不增加返回层级', (tester) async {
    final backend = await _open(tester);
    await _tap(tester, _slot('合成研讨室 1', '08:00–09:00'));
    expect(find.text('下一步'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('cgyy-date-2026-09-05')));
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
    await _tap(tester, _slot('合成研讨室 1', '08:00–09:00'));
    backend.emptyNext = true;
    await _tap(tester, find.byTooltip('刷新当前查询'));
    expect(find.text('下一步'), findsNothing);
    await _tap(tester, find.byTooltip('刷新当前查询'));
    expect(find.text('下一步'), findsNothing);
  });
  testWidgets('直接切换校区按原始站点读取且保留当前日期', (tester) async {
    final backend = await _open(tester);
    await _tap(tester, find.byKey(const ValueKey('cgyy-date-2026-09-05')));
    await _tap(tester, _slot('合成研讨室 1', '08:00–09:00'));
    await _tap(tester, find.byKey(const ValueKey('cgyy-campus-沙河')));
    expect(backend.roomReads.last.siteId, 17);
    expect(backend.roomReads.last.date, DateTime(2026, 9, 5));
    expect(find.text('下一步'), findsNothing);
    expect(backend.preparedRooms, isEmpty);
    expect(backend.commitCalls, 0);
  });
}

Future<RoomBackend> _open(
  WidgetTester tester, {
  double width = 402,
  String state = 'normal',
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 874);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final backend = RoomBackend(state: state);
  await tester.pumpWidget(
    UbaaFlutterApp(
      backend: backend,
      credentialVault: MemoryCredentialVault(),
      initialDestination: UiDestination.campus,
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

Finder _slot(String room, String time) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      (widget.properties.label?.startsWith('$room ') ?? false) &&
      (widget.properties.label?.contains(' $time ') ?? false),
);
