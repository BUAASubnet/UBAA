import 'package:ubaa_ui/ubaa_ui.dart' show UiDestination;
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'backend.dart';
part 'map_scenarios.dart';
part 'parent_scenarios.dart';

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment('UBAA_LIBRARY_MAPS_ONLY')) {
    registerLibraryMapTests(binding);
    return;
  }
  registerLibraryParentTests(binding);
  if (const bool.fromEnvironment('UBAA_LIBRARY_PARENTS_ONLY')) return;
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
  registerLibraryMapTests(binding);
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
        FeatureQueryView.libbookSeats,
      ]);
      await shot('seats', '进入分区后自动查询首日首时段，只显示可预约座位');
      expect(find.widgetWithText(Card, 'A2'), findsNothing);
      expect(find.widgetWithText(Card, 'A3'), findsNothing);
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
      await _chooseLibraryOption(tester, '楼馆', '合成乙馆 3/40');
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
      await _tap(tester, find.byTooltip('刷新当前查询'));
      expect(backend.libraryReads.last.page, 1);
      await shot('booking-refresh', '刷新预约列表从首批重新加载，保留原始取消资格');
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
          expect(find.text('重试'), findsOneWidget);
        } else if (state == 'loading') {
          final gate = Completer<void>();
          await _ensure(tester, find.widgetWithText(FilterChip, '二层 2/20'));
          backend.pending = gate;
          await tester.tap(find.widgetWithText(FilterChip, '二层 2/20'));
          await tester.pump(const Duration(milliseconds: 400));
          await shot('pending', '显式保持读取，旧分区和座位不能继续操作');
          gate.complete();
          await tester.pumpAndSettle();
        } else if (state == 'many') {
          await shot('top', '大量可预约座位首屏四列');
          await _ensure(tester, find.widgetWithText(Card, 'A40'));
        }
        await shot('result', '检查本状态实际原生视图、文字、滚动和错误说明');
        if (state == 'first-error') {
          await _tap(tester, find.widgetWithText(TextButton, '重试'));
          await shot('retry', '首次失败显式重试后恢复楼馆分区');
        }
        if (state == 'long') {
          await _ensure(tester, find.widgetWithText(Card, 'A7'));
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
        initialDestination: UiDestination.campus,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await _tap(tester, find.widgetWithText(Card, FeatureId.libbook.title));
  await _tap(tester, find.widgetWithText(Card, '预约座位'));
  if (tester.view.physicalSize.width / tester.view.devicePixelRatio < 600) {
    expect(find.byType(NavigationBar), findsOneWidget);
  }
  expect(find.byType(TextField), findsNothing);
}

Future<void> _ensure(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final scroll = find
        .byElementPredicate((element) {
          final widget = element.widget;
          // 排除错误编号等可选择文本内部的20像素滚动区。
          return widget is Scrollable &&
              widget.axisDirection == AxisDirection.down &&
              widget.physics is! NeverScrollableScrollPhysics &&
              element is StatefulElement &&
              (element.state as ScrollableState).position.viewportDimension >
                  100;
        })
        .hitTestable()
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

Future<void> _shot(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
  String steps,
) async {
  await tester.pump(const Duration(milliseconds: 300));
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

Future<void> _chooseLibraryOption(
  WidgetTester tester,
  String label,
  String value,
) async {
  if (tester.view.physicalSize.width / tester.view.devicePixelRatio >= 600) {
    final chipText = label == '分区' ? value.replaceAll(' · 合成校区', '') : value;
    await _tap(tester, find.widgetWithText(FilterChip, chipText));
  } else {
    await _tap(tester, find.byKey(ValueKey('libbook-choice-$label')));
    await _tap(tester, find.text(value).last);
  }
}

/// 人工巡检专用构造；自动测试入口不读取巡检模式开关。
Future<void> runInspection() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    UbaaFlutterApp(
      backend: LibraryBackend(
        state: const String.fromEnvironment(
          'UBAA_UI_STATE',
          defaultValue: 'normal',
        ),
      ),
      credentialVault: MemoryCredentialVault(),
      initialDestination: UiDestination.campus,
    ),
  );
  return;
}
