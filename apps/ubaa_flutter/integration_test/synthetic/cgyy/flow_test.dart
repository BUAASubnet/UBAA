import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'backend.dart';
part 'support.dart';
part 'form.dart';

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  _registerRoomFormTests(binding);
  for (final brightness in Brightness.values) {
    testWidgets('研讨室原生连续追加与刷新 ${brightness.name}', (tester) async {
      final backend = RoomBackend(state: 'paged');
      await _mount(tester, backend, brightness);
      await _tap(tester, find.byTooltip('返回'));
      await _tap(tester, find.widgetWithText(Card, '我的预约'));
      await tester.scrollUntilVisible(
        find.text('主题：连续订单144'),
        240,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 80,
      );
      await tester.pumpAndSettle();
      expect(
        backend.roomReads
            .where((q) => q.view == FeatureQueryView.cgyyOrders)
            .map((q) => q.page),
        [0, 1, 2],
      );
      await _shot(
        binding,
        tester,
        '${brightness.name}-infinite-bottom',
        '滚动加载三批订单，保留原始零基查询，末页停止',
      );
      await _tap(tester, find.byTooltip('刷新当前查询'));
      expect(backend.roomReads.last.page, 0);
      expect(find.text('主题：连续订单101'), findsOneWidget);
      final beforeReentry = backend.roomReads.length;
      await _tap(tester, find.byIcon(UiDestination.campus.selectedIcon).first);
      await _tap(tester, find.widgetWithText(Card, FeatureId.cgyy.title));
      expect(find.widgetWithText(Card, '预约研讨室'), findsOneWidget);
      expect(backend.roomReads, hasLength(beforeReentry));
      await _tap(tester, find.widgetWithText(Card, '我的预约'));
      expect(backend.roomReads.last.page, 0);
      expect(find.text('主题：连续订单101'), findsOneWidget);
      expect(backend.commitCalls, 0);
    });
    testWidgets('研讨室原生选择表单草稿和订单 ${brightness.name}', (tester) async {
      final backend = RoomBackend();
      await _mount(tester, backend, brightness);
      Future<void> shot(String scene, String steps) =>
          _shot(binding, tester, '${brightness.name}-normal-$scene', steps);
      expect(backend.roomReads.map((q) => q.view), [
        FeatureQueryView.summary,
        FeatureQueryView.cgyyDayInfo,
      ]);
      expect(backend.roomReads.last.siteId, 7);
      expect(find.byType(TextField), findsNothing);
      expect(
        find.byKey(const ValueKey('cgyy-date-2026-09-04')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('cgyy-date-2026-09-05')),
        findsOneWidget,
      );
      expect(find.text('下一步'), findsNothing);
      await shot('table', '自动选择首站点，保留旧版校区/日期/站点选择与时段矩阵；三排选项直接点选');
      await _tap(tester, _slot('合成研讨室 1', '08:00–09:00'));
      await _tap(tester, _slot('合成研讨室 1', '09:00–10:00'));
      expect(find.text('已选'), findsNWidgets(2));
      await shot('selected', '选择同房间相邻的9和3号时段，按原顺序而非ID排序');
      await _tap(tester, find.text('下一步'));
      await shot('form', '进入预约信息表单，原始两时段选择保留');
      for (final entry in {
        '联系电话': 'fixture-phone',
        '预约主题': 'study',
        '参与人数': '2',
        '活动内容': 'synthetic discussion',
        '参与人说明': 'fixture participants',
      }.entries) {
        await _edit(tester, entry.key, entry.value);
      }
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await _tap(tester, find.text('返回修改时段'));
      expect(find.text('已选'), findsNWidgets(2));
      await _tap(tester, find.text('下一步'));
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '联系电话'))
            .controller!
            .text,
        'fixture-phone',
      );
      expect(
        backend.roomReads.where(
          (q) => q.view == FeatureQueryView.cgyyPurposeTypes,
        ),
        hasLength(1),
      );
      await shot('form-draft', '返回修改时段后重开，保留字段/用途/选择且独立用途读取使用同代缓存');
      await _tap(tester, find.text('继续确认'));
      expect(backend.preparedRooms.single.actions.map((a) => a.timeId), [9, 3]);
      await shot('reserve-confirm', '仅prepare合成预约，两个原始target不从显示文字重建');
      await _tap(tester, find.widgetWithText(OutlinedButton, '取消'));
      await _chooseRoom(tester, '预约日期', '2026-09-05');
      expect(backend.roomReads.last.date, DateTime(2026, 9, 5));
      expect(find.text('下一步'), findsNothing);
      await shot('new-date', '换日期重新读取，旧选择不复用');
      await _chooseRoom(tester, '校区', '沙河');
      expect(backend.roomReads.last.siteId, 17);
      expect(backend.roomReads.last.date, DateTime(2026, 9, 5));
      await shot('campus', '切校区选择该校区首站点，保持明确日期');
      await _tap(tester, find.byTooltip('返回'));
      await _tap(tester, find.widgetWithText(Card, '我的预约'));
      expect(backend.roomReads.last.page, 0);
      await shot('orders', '预约记录地点状态时间优先，详情及允许取消入口');
      await _tap(tester, find.widgetWithText(TextButton, '查看详情').first);
      expect(backend.roomReads.last.orderId, 101);
      await shot('order-detail', '以typed订单ID读取详情，显示低频编号');
      await _tap(tester, find.byTooltip('返回'));
      await _tap(tester, find.widgetWithText(TextButton, '取消预约').first);
      expect(backend.preparedOrders, [101]);
      await shot('cancel-confirm', '取消确认弹窗覆盖在原列表上，保留预约后返回列表');
      await _tap(tester, find.widgetWithText(TextButton, '保留预约'));
      await _tap(tester, find.byTooltip('刷新当前查询'));
      expect(backend.roomReads.last.page, 0);
      await shot('orders-refresh', '刷新预约记录从零基首批开始，末页不自动追加');
      await _tap(tester, find.byTooltip('返回'));
      await _tap(tester, find.widgetWithText(Card, '查看密码'));
      await shot('lock', '专用页面显示合成密码，不输出真实材料');
      expect(find.text('001234'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('feature-filter-button')),
        findsNothing,
      );
      // 用途类型调试视图已不在 GUI 提供；表单内用途读取见 form-draft，CLI 保留独立查询。
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
      testWidgets('研讨室原生状态 $state ${brightness.name}', (tester) async {
        final backend = RoomBackend(state: state);
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
          await _ensure(tester, find.text('网络不可用'));
          expect(_slot('合成研讨室 1', '08:00–09:00'), findsOneWidget);
        } else if (state == 'loading') {
          final date = find.byKey(const ValueKey('cgyy-date-2026-09-05'));
          await _ensure(tester, date);
          final gate = Completer<void>();
          backend.pending = gate;
          await tester.tap(date);
          await tester.pump(const Duration(milliseconds: 200));
          await shot('pending', '重新读取中禁止选择旧时段');
          gate.complete();
          await tester.pumpAndSettle();
        } else if (state == 'many') {
          await shot('top', '42个房间列表首屏');
          final header = find.text('08:00–09:00');
          final position = tester.getTopLeft(header);
          await _ensure(tester, find.text('合成研讨室 42'));
          expect(header.hitTestable(), findsOneWidget);
          expect(tester.getTopLeft(header), position);
          final head = find.byKey(const ValueKey('cgyy-time-header-scroll'));
          final body = find.byKey(const ValueKey('cgyy-time-body-scroll'));
          await tester.drag(head, const Offset(-180, 0));
          await tester.pumpAndSettle();
          final a = tester.widget<SingleChildScrollView>(head).controller!;
          final b = tester.widget<SingleChildScrollView>(body).controller!;
          expect(a.offset, closeTo(b.offset, .01));
          expect(find.text('合成研讨室 42').hitTestable(), findsOneWidget);
        }
        await shot('result', '明确合成状态的原生展示及异常检查');
        if (state == 'first-error') {
          await _tap(tester, find.widgetWithText(TextButton, '重试'));
          expect(backend.roomReads.last.view, FeatureQueryView.cgyyDayInfo);
          await shot('retry', '首次错误显式重试后恢复选择表');
        }
        expect(backend.commitCalls, 0);
      });
    }
  }
}

Future<void> _mount(
  WidgetTester tester,
  RoomBackend backend,
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
  await _tap(tester, find.widgetWithText(Card, FeatureId.cgyy.title));
  await _tap(tester, find.widgetWithText(Card, '预约研讨室'));
}

/// 人工巡检专用构造；自动测试入口不读取巡检模式开关。
Future<void> runInspection() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    UbaaFlutterApp(
      backend: RoomBackend(),
      credentialVault: MemoryCredentialVault(),
      initialDestination: UiDestination.campus,
    ),
  );
  return;
}
