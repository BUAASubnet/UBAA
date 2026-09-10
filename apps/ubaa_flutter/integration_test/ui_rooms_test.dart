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
import 'ui_rooms/backend.dart';
part 'ui_rooms/support.dart';
part 'ui_rooms/form.dart';

void main() {
  if (const bool.fromEnvironment('UBAA_UI_INSPECTION')) {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(
      UbaaFlutterApp(
        backend: RoomBackend(),
        credentialVault: MemoryCredentialVault(),
        initialTab: 2,
      ),
    );
    return;
  }
  WidgetController.hitTestWarningShouldBeFatal = true;
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  _registerRoomFormTests(binding);
  for (final brightness in Brightness.values) {
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
      expect(find.byType(FilterChip), findsNothing);
      expect(find.text('下一步'), findsNothing);
      await shot('table', '自动选择首站点，只显示地点日期和时段矩阵；筛选仅在右上按需面板');
      await _tap(tester, find.byTooltip('合成研讨室 1 08:00–09:00'));
      await _tap(tester, find.byTooltip('合成研讨室 1 09:00–10:00'));
      expect(find.text('已选'), findsNWidgets(2));
      await shot('selected', '选择同房间相邻的9和3号时段，按原顺序而非ID排序');
      final count = backend.roomReads.length;
      await _panel(tester);
      await _edit(tester, '筛选详情', '1');
      await _closePanel(tester);
      expect(find.text('已选'), findsNWidgets(2));
      await _panel(tester);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '筛选详情'))
            .controller!
            .text,
        '1',
      );
      await shot('query-draft', '右上按需面板草稿关闭重开仍在，选择未清掉，未增加读取');
      await _edit(tester, '筛选详情', '');
      await _closePanel(tester);
      expect(backend.roomReads, hasLength(count));
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
      await _tap(tester, find.widgetWithText(OutlinedButton, '查看详情').first);
      expect(backend.roomReads.last.orderId, 101);
      await shot('order-detail', '以typed订单ID读取详情，显示低频编号');
      await _tap(tester, find.byTooltip('返回'));
      await _tap(tester, find.widgetWithText(OutlinedButton, '准备取消订单').first);
      expect(backend.preparedOrders, [101]);
      await shot('cancel-confirm', '仅prepare合成订单取消，不点击确认提交');
      await _tap(tester, find.widgetWithText(OutlinedButton, '取消'));
      await _panel(tester);
      await _edit(tester, '页码', '2');
      await _edit(tester, '每页数量', '2');
      await _tap(tester, find.text('应用筛选'));
      await _closePanel(tester);
      expect(backend.roomReads.last.page, 1);
      expect(find.textContaining('第 2 / 2 页'), findsOneWidget);
      await shot('page-two', '显示第2页但请求原始page=1，保留未知资格订单');
      await _tap(tester, find.byTooltip('上一页'));
      expect(backend.roomReads.last.page, 0);
      expect(find.textContaining('第 1 / 2 页'), findsOneWidget);
      await _tap(tester, find.byTooltip('下一页'));
      expect(backend.roomReads.last.page, 1);
      await _panel(tester);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '页码'))
            .controller!
            .text,
        '2',
      );
      await _closePanel(tester);
      await _tap(tester, find.byTooltip('返回'));
      await _tap(tester, find.widgetWithText(Card, '门锁状态'));
      await shot('lock', '仅显示公开available，不输出锁码或原始内容');
      expect(find.text('当前无可用门锁信息'), findsOneWidget);
      await _panel(tester);
      await _tap(tester, find.byType(DropdownButton<FeatureQueryView>));
      await _tap(tester, find.text('用途类型').last);
      await _tap(tester, find.text('应用筛选'));
      await _closePanel(tester);
      expect(backend.roomReads.last.view, FeatureQueryView.cgyyPurposeTypes);
      expect(find.text('本地冻结回退'), findsOneWidget);
      await shot('purposes', '独立用途查询保留回退来源，不把名称当作提交编号');
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
          await _ensure(tester, find.text('以下为上次成功加载的数据。'));
        } else if (state == 'loading') {
          await _panel(tester);
          await _tap(tester, find.byKey(const ValueKey('cgyy-choice-预约日期')));
          final gate = Completer<void>();
          backend.pending = gate;
          await tester.tap(find.text('2026-09-05').last);
          await tester.pump(const Duration(milliseconds: 200));
          await tester.tap(find.widgetWithText(TextButton, '完成'));
          await tester.pump(const Duration(milliseconds: 200));
          await shot('pending', '重新读取中禁止选择旧时段');
          gate.complete();
          await tester.pumpAndSettle();
        } else if (state == 'many') {
          await shot('top', '42个房间列表首屏');
          final header = find.text('08:00\n–09:00');
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
        initialTab: 2,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await _tap(tester, find.widgetWithText(Card, FeatureId.cgyy.title));
  await _tap(tester, find.widgetWithText(Card, '预约研讨室'));
}
