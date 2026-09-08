import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'ui_library/backend.dart';

void main() {
  if (const bool.fromEnvironment('UBAA_UI_INSPECTION')) {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(
      UbaaFlutterApp(
        backend: LibraryBackend(),
        credentialVault: MemoryCredentialVault(),
        initialTab: 1,
      ),
    );
    return;
  }
  WidgetController.hitTestWarningShouldBeFatal = true;
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test('合成图书馆记录分页与未知资格遵循同一合同', () {
    final result = libraryData(
      const FeatureQuery(
        view: FeatureQueryView.libbookBookings,
        page: 2,
        size: 2,
      ),
      'normal',
    );
    expect(result.details, hasLength(1));
    expect(
      (result.details.single.presentation! as LibbookBookingPresentation).id,
      'booking-3',
    );
    expect(
      result.details.single.action<LibbookCancelAction>()?.eligibility,
      ActionEligibility.unknown,
    );
    expect(result.pagination?.total, 3);
    expect(result.pagination?.hasMore, false);
  });
  for (final brightness in Brightness.values) {
    testWidgets('图书馆原生完整选择和取消准备 ${brightness.name}', (tester) async {
      final backend = LibraryBackend();
      await _mount(tester, backend, brightness);
      Future<void> shot(String scene, String steps) =>
          _shot(binding, tester, '${brightness.name}-normal-$scene', steps);
      expect(backend.libraryReads.map((q) => q.view), [
        FeatureQueryView.summary,
        FeatureQueryView.libbookAreas,
        FeatureQueryView.libbookAreaDetail,
      ]);
      await shot('flow', '进入预约座位，自动读首馆首层分区与时段；未查询座位');
      await _seatQuery(
        tester,
        backend,
        onOpen: () => shot('query-empty-date', '从分区进入座位查询，日期未自动组合'),
        onFilled: () => shot('query-draft', '手填日期和原始时段后关闭重开，草稿保留'),
      );
      await shot('seats', '仅一次座位查询，显示所有状态四列网格');
      final readCount = backend.libraryReads.length;
      await _panel(tester);
      await _edit(tester, '筛选详情', '未知');
      await _closePanel(tester);
      expect(find.widgetWithText(Card, 'A3'), findsOneWidget);
      expect(find.widgetWithText(Card, 'A1'), findsNothing);
      await shot('status-search', '按状态本地搜索并关闭面板，仍可查看未知座位且不新增读取');
      await _panel(tester);
      await _edit(tester, '筛选详情', '');
      await _closePanel(tester);
      expect(backend.libraryReads, hasLength(readCount));
      await _tap(tester, find.widgetWithText(Card, 'A2'));
      expect(find.text('已选座位：A2'), findsNothing);
      await _tap(tester, find.widgetWithText(Card, 'A3'));
      expect(find.text('已选座位：A3'), findsNothing);
      await _tap(tester, find.widgetWithText(Card, 'A1'));
      await _ensure(tester, find.text('准备预约此座位'));
      await shot('selected', '只选择allowed座位后显示摘要和准备入口');
      await _tap(tester, find.text('准备预约此座位'));
      expect(backend.preparedSeats.single.seatId, 'canonical-seat-0');
      expect(backend.preparedSeats.single.areaId, 'library-a-floor-1-area-1');
      expect(backend.preparedSeats.single.day, '2026-09-04');
      expect(backend.preparedSeats.single.segment, 'segment-a');
      await shot('reserve-confirm', '准备的是独立canonical目标；未提交');
      await _tap(tester, find.widgetWithText(OutlinedButton, '取消'));
      await shot('after-reserve-cancel', '取消准备后查看原选择与父选项');
      await _tap(tester, find.widgetWithText(FilterChip, '合成乙馆 3/40'));
      expect(backend.libraryReads.last.areaId, 'library-b-floor-1-area-1');
      expect(find.text('已选座位：A1'), findsNothing);
      await shot('other-library', '换楼馆清除旧座位和时段，仍是同一预约页面');
      await _tap(tester, find.byTooltip('返回'));
      await _tap(tester, find.widgetWithText(Card, '我的预约'));
      await shot('bookings', '预约记录以地点、状态、时间和座位优先，含不可取消和未知状态');
      await _tap(tester, find.byTooltip('预约详情').first);
      await shot('booking-detail', '仅在只读详情查看编号和兼容字段');
      await _tap(tester, find.widgetWithText(TextButton, '关闭'));
      await _tap(tester, find.widgetWithText(OutlinedButton, '准备取消预约').first);
      expect(backend.preparedBookings.single, ('canonical-booking-1', 1, 20));
      await shot('cancel-confirm', '准备取消canonical预约，保留服务器分页');
      await _tap(tester, find.widgetWithText(OutlinedButton, '取消'));
      await _panel(tester);
      await tester.enterText(find.widgetWithText(TextField, '页码'), '2');
      await tester.enterText(find.widgetWithText(TextField, '每页数量'), '2');
      await _tap(tester, find.widgetWithText(FilledButton, '应用筛选'));
      await _closePanel(tester);
      expect(backend.libraryReads.last.page, 2);
      expect(backend.libraryReads.last.size, 2);
      expect(find.textContaining('第 2 / 2 页'), findsOneWidget);
      await shot('booking-page-two', '第二页显示剩余一条，总数仍为3；未知资格无可点取消');
      expect(backend.discarded, hasLength(2));
      expect(backend.commitCalls, 0);
    });
    for (final state in [
      'empty',
      'first-error',
      'stale',
      'loading',
      'long',
      'many',
    ]) {
      testWidgets('图书馆原生状态 $state ${brightness.name}', (tester) async {
        final backend = LibraryBackend(state: state);
        if (state == 'long') {
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        }
        await _mount(tester, backend, brightness);
        Future<void> shot(String scene, String steps) =>
            _shot(binding, tester, '${brightness.name}-$state-$scene', steps);
        if (state == 'stale') {
          backend.failNext = true;
          await _tap(tester, find.byTooltip('刷新当前查询'));
          await _ensure(tester, find.text('以下为上次成功加载的数据。'));
          expect(find.text('以下为上次成功加载的数据。'), findsOneWidget);
        } else if (state == 'loading') {
          final gate = Completer<void>();
          backend.pending = gate;
          await _ensure(tester, find.widgetWithText(FilterChip, '二层 2/20'));
          await tester.tap(find.widgetWithText(FilterChip, '二层 2/20'));
          await tester.pump(const Duration(milliseconds: 200));
          await shot('pending', '显式保持读取，旧分区和座位不能继续操作');
          gate.complete();
          await tester.pumpAndSettle();
        } else if (state == 'many') {
          await _seatQuery(tester, backend);
          await shot('top', '大量座位首屏四列，各状态均可见');
          await _ensure(tester, find.widgetWithText(Card, 'A42'));
        }
        await shot('result', '检查本状态实际原生视图、文字、滚动和错误说明');
        if (state == 'first-error') {
          await _tap(tester, find.widgetWithText(TextButton, '重试'));
          await shot('retry', '首次失败显式重试后恢复楼馆分区');
        }
        if (state == 'long') {
          await _ensure(tester, find.text('查询座位'));
          await shot('bottom', '1.3文字与长名称仍可滚动到下一操作');
        }
        expect(backend.commitCalls, 0);
      });
    }
  }
}

Future<void> _mount(
  WidgetTester tester,
  LibraryBackend backend,
  Brightness brightness,
) async {
  expect(Platform.isIOS || Platform.isMacOS, isTrue);
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await tester.pumpWidget(
    KeyedSubtree(
      key: UniqueKey(),
      child: UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
        initialTab: 1,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await _tap(tester, find.widgetWithText(Card, FeatureId.libbook.title));
  await _tap(tester, find.widgetWithText(Card, '预约座位'));
  if (tester.view.physicalSize.width / tester.view.devicePixelRatio < 600) {
    expect(find.byType(NavigationBar), findsNothing);
  }
  expect(find.byType(TextField), findsNothing);
}

Future<void> _ensure(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final scroll = find
        .byWidgetPredicate(
          (w) =>
              w is Scrollable &&
              w.axisDirection == AxisDirection.down &&
              w.physics is! NeverScrollableScrollPhysics,
        )
        .last;
    await tester.drag(scroll, const Offset(0, 1200));
    await tester.pumpAndSettle();
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        240,
        scrollable: scroll,
        maxScrolls: 80,
      );
    }
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _ensure(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _edit(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(TextField, label);
  await _tap(tester, field);
  await tester.enterText(field, value);
  await tester.pump();
  expect(tester.widget<TextField>(field).controller!.text, value);
}

Future<void> _panel(WidgetTester tester) async {
  if (find.widgetWithText(TextButton, '完成').evaluate().isEmpty) {
    await _tap(tester, find.byTooltip('搜索与筛选'));
  }
}

Future<void> _closePanel(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await _tap(tester, find.widgetWithText(TextButton, '完成'));
}

Future<void> _seatQuery(
  WidgetTester tester,
  LibraryBackend backend, {
  Future<void> Function()? onOpen,
  Future<void> Function()? onFilled,
}) async {
  final count = backend.libraryReads.length;
  await _tap(tester, find.text('查询座位'));
  expect(
    tester
        .widget<TextField>(find.widgetWithText(TextField, '日期'))
        .controller!
        .text,
    isEmpty,
  );
  expect(backend.libraryReads, hasLength(count));
  if (onOpen != null) await onOpen();
  for (final entry in {
    '日期': '2026-09-04',
    '开始时间': '08:00',
    '结束时间': '10:00',
    '时段编号（必填）': 'segment-a',
  }.entries) {
    await _ensure(tester, find.widgetWithText(TextField, entry.key));
    await tester.enterText(
      find.widgetWithText(TextField, entry.key),
      entry.value,
    );
  }
  await _closePanel(tester);
  await _panel(tester);
  expect(
    tester
        .widget<TextField>(find.widgetWithText(TextField, '时段编号（必填）'))
        .controller!
        .text,
    'segment-a',
  );
  if (onFilled != null) await onFilled();
  await _tap(tester, find.widgetWithText(FilledButton, '应用筛选'));
  await _closePanel(tester);
  expect(backend.libraryReads, hasLength(count + 1));
}

Future<void> _shot(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
  String steps,
) async {
  expect(tester.takeException(), isNull);
  final size = tester.view.physicalSize, ratio = tester.view.devicePixelRatio;
  final records =
      (binding.reportData ??= <String, dynamic>{}).putIfAbsent(
            'uiEvidence',
            () => <Object?>[],
          )
          as List;
  records.add({
    'name': name,
    'steps': steps,
    'backend': 'synthetic-library',
    'platform': Platform.operatingSystem,
    'system': Platform.operatingSystemVersion,
    'logicalWidth': size.width / ratio,
    'logicalHeight': size.height / ratio,
    'devicePixelRatio': ratio,
    'viewportSource': 'native-view-unmodified',
    'dateUtc': DateTime.now().toUtc().toIso8601String(),
    'sourceSha': const String.fromEnvironment('UBAA_UI_SOURCE_SHA'),
  });
  if (Platform.isIOS) {
    await binding.takeScreenshot(name);
  } else {
    debugPrint('原生图书馆检查点：$name');
  }
}
