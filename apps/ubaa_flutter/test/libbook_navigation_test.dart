import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../integration_test/ui_library/backend.dart';

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets('图书馆默认不常驻选择与查询，右上保完整入口且关闭不额外读取', (tester) async {
    final backend = await _open(tester);
    expect(find.byType(FilterChip), findsNothing);
    expect(find.byType(ActionChip), findsNothing);
    expect(find.text('查询座位'), findsNothing);
    final count = backend.libraryReads.length;
    await _tap(tester, find.byTooltip('搜索与筛选'));
    for (final label in ['楼馆', '楼层', '分区']) {
      expect(find.byKey(ValueKey('libbook-choice-$label')), findsOneWidget);
    }
    expect(find.text('查询座位'), findsOneWidget);
    await _tap(tester, find.widgetWithText(TextButton, '完成'));
    expect(backend.libraryReads, hasLength(count));
    expect(find.byType(FilterChip), findsNothing);
  });
  testWidgets('图书馆座位查询后保分区时段选项，关闭未应用草稿不清已选座位', (tester) async {
    final backend = await _open(tester);
    await _seatQuery(tester, backend);
    await _tap(tester, find.widgetWithText(Card, 'A1'));
    final count = backend.libraryReads.length;
    await _tap(tester, find.byTooltip('搜索与筛选'));
    expect(find.widgetWithText(ActionChip, '下午 14:00–16:00'), findsOneWidget);
    final field = find.widgetWithText(TextField, '开始时间');
    await tester.ensureVisible(field);
    await tester.enterText(field, '09:00');
    FocusManager.instance.primaryFocus?.unfocus();
    await _tap(tester, find.widgetWithText(TextButton, '完成'));
    expect(find.text('已选座位：A1'), findsOneWidget);
    expect(backend.libraryReads, hasLength(count));
    await _tap(tester, find.byTooltip('搜索与筛选'));
    expect(tester.widget<TextField>(field).controller!.text, '09:00');
    expect(
      tester
          .widget<DropdownButton<String>>(
            find.byKey(const ValueKey('libbook-choice-分区')),
          )
          .value,
      'library-a-floor-1-area-1',
    );
  });
  testWidgets('分区响应缺省父标识仍沿原查询进入详情，不伪造DTO父字段', (tester) async {
    final backend = await _open(tester, state: 'missing-parents');
    expect(backend.libraryReads.map((q) => q.view), [
      FeatureQueryView.summary,
      FeatureQueryView.libbookAreas,
      FeatureQueryView.libbookAreaDetail,
    ]);
    expect(backend.libraryReads.last.areaId, 'library-a-floor-1-area-1');
    final original = libraryData(backend.libraryReads[1], 'missing-parents');
    final area =
        original.details.first.presentation! as LibbookAreaPresentation;
    expect(area.premisesId, isEmpty);
    expect(area.storeyId, isEmpty);
    expect(find.text('分区时段'), findsOneWidget);
    expect(backend.preparedSeats, isEmpty);
    expect(backend.commitCalls, 0);
  });
  testWidgets('分区响应明确冲突的父标识不自动进入详情', (tester) async {
    final backend = await _open(tester, state: 'conflicting-parents');
    expect(backend.libraryReads.map((q) => q.view), [
      FeatureQueryView.summary,
      FeatureQueryView.libbookAreas,
    ]);
    expect(find.text('分区时段'), findsNothing);
    expect(backend.commitCalls, 0);
  });
  testWidgets('图书馆点选时段只回填原始三字段，日期仍须明确填写', (tester) async {
    final backend = await _open(tester);
    final before = backend.libraryReads.length;
    await _tap(tester, find.byTooltip('搜索与筛选'));
    await _tap(tester, find.widgetWithText(ActionChip, '下午 14:00–16:00'));
    expect(backend.libraryReads, hasLength(before));
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '日期'))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '开始时间'))
          .controller!
          .text,
      '14:00',
    );
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '结束时间'))
          .controller!
          .text,
      '16:00',
    );
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '时段编号（必填）'))
          .controller!
          .text,
      'segment-b',
    );
    await _tap(tester, find.widgetWithText(FilledButton, '应用筛选'));
    expect(backend.libraryReads, hasLength(before));
    expect(find.text('请先明确选择预约日期。'), findsOneWidget);
  });
  testWidgets('图书馆本地搜索保留状态查询能力且不触发读取', (tester) async {
    final backend = await _open(tester);
    await _seatQuery(tester, backend);
    final before = backend.libraryReads.length;
    await _tap(tester, find.byTooltip('搜索与筛选'));
    await tester.enterText(find.widgetWithText(TextField, '筛选详情'), '未知');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _tap(tester, find.widgetWithText(TextButton, '完成'));
    expect(find.widgetWithText(Card, 'A3'), findsOneWidget);
    expect(find.widgetWithText(Card, 'A6'), findsOneWidget);
    expect(find.widgetWithText(Card, 'A1'), findsNothing);
    expect(backend.libraryReads, hasLength(before));
  });
  test('合成图书馆默认记录查询与生产一致使用第一页', () {
    final result = libraryData(
      const FeatureQuery(view: FeatureQueryView.libbookBookings),
      'normal',
    );
    expect(result.pagination?.page, 1);
    expect(result.details, hasLength(3));
    expect(result.details.first.action<LibbookCancelAction>()?.page, 1);
  });
  testWidgets('图书馆隐藏后首页刷新不能触发后台自动分区链', (tester) async {
    final backend = await _open(tester, width: 1280);
    await _tap(tester, find.byIcon(Icons.home_outlined));
    final before = backend.libraryReads.length;
    await _tap(tester, find.byTooltip('刷新'));
    expect(backend.libraryReads, hasLength(before + 1));
    expect(backend.libraryReads.last.view, FeatureQueryView.summary);
  });
  testWidgets('图书馆明确空座位后重新加载不复活已清掉的选择', (tester) async {
    final backend = await _open(tester);
    await _seatQuery(tester, backend);
    await _tap(tester, find.widgetWithText(Card, 'A1'));
    backend.emptyNext = true;
    await _tap(tester, find.byTooltip('刷新当前查询'));
    expect(find.text('已选座位：A1'), findsNothing);
    await _tap(tester, find.byTooltip('刷新当前查询'));
    expect(find.widgetWithText(Card, 'A1'), findsOneWidget);
    expect(find.text('已选座位：A1'), findsNothing);
  });
  testWidgets('图书馆重新查询楼馆列表仍保留存在的原楼馆选择', (tester) async {
    final backend = await _open(tester);
    await _tap(tester, find.byTooltip('搜索与筛选'));
    await _tap(tester, find.byKey(const ValueKey('libbook-choice-楼馆')));
    await _tap(tester, find.text('合成乙馆 3/40').last);
    await _tap(tester, find.text('更多查询'));
    await _tap(tester, find.byType(DropdownButton<FeatureQueryView>));
    await _tap(tester, find.text('馆列表').last);
    await _tap(tester, find.widgetWithText(FilledButton, '应用筛选'));
    await _tap(tester, find.widgetWithText(TextButton, '完成'));
    expect(
      backend.libraryReads[backend.libraryReads.length - 2].premisesId,
      'library-b',
    );
    expect(backend.libraryReads.last.areaId, 'library-b-floor-1-area-1');
  });
  testWidgets('图书馆自动进入原楼馆楼层分区而不臆造日期时段，手动完整查询保留canonical目标', (tester) async {
    final backend = await _open(tester);
    expect(backend.libraryReads.map((q) => q.view), [
      FeatureQueryView.summary,
      FeatureQueryView.libbookAreas,
      FeatureQueryView.libbookAreaDetail,
    ]);
    expect(backend.libraryReads[1].premisesId, 'library-a');
    expect(backend.libraryReads[1].storeyId, 'library-a-floor-1');
    expect(backend.libraryReads.last.areaId, 'library-a-floor-1-area-1');
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('从右上角选择日期和时段'), findsOneWidget);
    await _seatQuery(tester, backend);
    expect(backend.libraryReads.last.areaId, 'library-a-floor-1-area-1');
    expect(backend.libraryReads.last.segment, 'segment-a');
    expect(backend.libraryReads.last.date, DateTime(2026, 9, 4));
    await _tap(tester, find.widgetWithText(Card, 'A2'));
    expect(find.text('已选座位：A2'), findsNothing);
    await _tap(tester, find.widgetWithText(Card, 'A3'));
    expect(find.text('已选座位：A3'), findsNothing);
    await _tap(tester, find.widgetWithText(Card, 'A1'));
    await _tap(tester, find.text('准备预约此座位'));
    expect(backend.preparedSeats.single.seatId, 'canonical-seat-0');
    expect(backend.preparedSeats.single.areaId, 'library-a-floor-1-area-1');
    expect(backend.preparedSeats.single.segment, 'segment-a');
    await _tap(tester, find.widgetWithText(OutlinedButton, '取消'));
    expect(backend.commitCalls, 0);
  });
  testWidgets('图书馆换楼馆后清掉旧时段座位，返回不会增加领域返回层级', (tester) async {
    final backend = await _open(tester);
    await _seatQuery(tester, backend);
    await _tap(tester, find.widgetWithText(Card, 'A1'));
    expect(find.text('已选座位：A1'), findsOneWidget);
    final gate = Completer<void>();
    await _tap(tester, find.byTooltip('搜索与筛选'));
    await _tap(tester, find.byKey(const ValueKey('libbook-choice-楼馆')));
    backend.pending = gate;
    await tester.tap(find.text('合成乙馆 3/40').last);
    await tester.pump();
    expect(find.text('已选座位：A1'), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(
      backend.libraryReads[backend.libraryReads.length - 2].premisesId,
      'library-b',
    );
    expect(backend.libraryReads.last.areaId, 'library-b-floor-1-area-1');
    expect(
      tester
          .widget<DropdownButton<String>>(
            find.byKey(const ValueKey('libbook-choice-楼层')),
          )
          .value,
      'library-b-floor-1',
    );
    await _tap(tester, find.widgetWithText(TextButton, '完成'));
    expect(find.text('已选座位：A1'), findsNothing);
    await _tap(tester, find.byTooltip('返回'));
    expect(find.widgetWithText(Card, '预约座位'), findsOneWidget);
    expect(backend.preparedSeats, isEmpty);
  });
}

Future<LibraryBackend> _open(
  WidgetTester tester, {
  double width = 402,
  String state = 'normal',
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 874);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final backend = LibraryBackend(state: state);
  await tester.pumpWidget(
    UbaaFlutterApp(
      backend: backend,
      credentialVault: MemoryCredentialVault(),
      initialTab: 1,
    ),
  );
  await tester.pumpAndSettle();
  await _tap(tester, find.widgetWithText(Card, FeatureId.libbook.title));
  await _tap(tester, find.widgetWithText(Card, '预约座位'));
  return backend;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _seatQuery(WidgetTester tester, LibraryBackend backend) async {
  final count = backend.libraryReads.length;
  await _tap(tester, find.byTooltip('搜索与筛选'));
  await _tap(tester, find.text('查询座位'));
  final picker = tester.widget<DropdownButton<String>>(
    find.ancestor(
      of: find.text('从当前馆区选择'),
      matching: find.byType(DropdownButton<String>),
    ),
  );
  expect(picker.items!.map((item) => item.value), ['library-a-floor-1-area-1']);
  expect(backend.libraryReads, hasLength(count));
  expect(
    tester
        .widget<TextField>(find.widgetWithText(TextField, '日期'))
        .controller!
        .text,
    isEmpty,
  );
  for (final entry in {
    '开始时间': '08:00',
    '结束时间': '10:00',
    '时段编号（必填）': 'segment-a',
  }.entries) {
    await tester.ensureVisible(find.widgetWithText(TextField, entry.key));
    await tester.enterText(
      find.widgetWithText(TextField, entry.key),
      entry.value,
    );
  }
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await _tap(tester, find.widgetWithText(FilledButton, '应用筛选'));
  expect(backend.libraryReads, hasLength(count));
  expect(find.text('请先明确选择预约日期。'), findsOneWidget);
  for (final entry in {
    '日期': '2026-09-04',
    '开始时间': '08:00',
    '结束时间': '10:00',
    '时段编号（必填）': 'segment-a',
  }.entries) {
    await tester.ensureVisible(find.widgetWithText(TextField, entry.key));
    await tester.enterText(
      find.widgetWithText(TextField, entry.key),
      entry.value,
    );
  }
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await _tap(tester, find.widgetWithText(FilledButton, '应用筛选'));
  await _tap(tester, find.widgetWithText(TextButton, '完成'));
  expect(backend.libraryReads, hasLength(count + 1));
}
