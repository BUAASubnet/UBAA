import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../integration_test/ui_library/backend.dart';

void main() {
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
    await _tap(tester, find.widgetWithText(FilterChip, '合成乙馆 3/40'));
    await _tap(tester, find.byTooltip('搜索与筛选'));
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
    expect(find.textContaining('当前时段未标明适用日期'), findsOneWidget);
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
    backend.pending = gate;
    await tester.ensureVisible(find.widgetWithText(FilterChip, '合成乙馆 3/40'));
    await tester.tap(find.widgetWithText(FilterChip, '合成乙馆 3/40'));
    await tester.pump();
    expect(find.text('已选座位：A1'), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(
      backend.libraryReads[backend.libraryReads.length - 2].premisesId,
      'library-b',
    );
    expect(backend.libraryReads.last.areaId, 'library-b-floor-1-area-1');
    expect(find.widgetWithText(FilterChip, '一层 1/20'), findsOneWidget);
    expect(find.text('已选座位：A1'), findsNothing);
    await _tap(tester, find.byTooltip('返回'));
    expect(find.widgetWithText(Card, '预约座位'), findsOneWidget);
    expect(backend.preparedSeats, isEmpty);
  });
}

Future<LibraryBackend> _open(WidgetTester tester, {double width = 402}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 874);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final backend = LibraryBackend();
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
  await _tap(tester, find.text('查询座位'));
  final picker = tester.widget<DropdownButton<String>>(
    find.byType(DropdownButton<String>),
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
