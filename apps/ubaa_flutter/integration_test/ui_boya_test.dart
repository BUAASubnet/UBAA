import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'ui_boya/backend.dart';
part 'ui_boya/support.dart';

void main() {
  if (const bool.fromEnvironment('UBAA_UI_INSPECTION')) {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(
      UbaaFlutterApp(
        backend: BoyaBackend(
          state: const String.fromEnvironment(
            'UBAA_UI_STATE',
            defaultValue: 'normal',
          ),
        ),
        credentialVault: MemoryCredentialVault(),
        initialTab: 1,
      ),
    );
    return;
  }
  WidgetController.hitTestWarningShouldBeFatal = true;
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final brightness in Brightness.values) {
    testWidgets('博雅原生卡片查询详情及准备取消 ${brightness.name}', (tester) async {
      final backend = BoyaBackend();
      await _mount(tester, backend, brightness, 'courses');
      Future<void> shot(String scene, String steps) =>
          _shot(binding, tester, '${brightness.name}-normal-$scene', steps);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('准备选课'), findsNothing);
      await shot('courses', '旧版课程卡片，正文没有搜索或写入按钮堆叠');
      final reads = backend.boyaReads.length;
      await _panel(tester);
      await _tap(tester, find.widgetWithText(FilterChip, '已过期'));
      await shot('filters', '当前页状态多选仅在顶栏面板中');
      await _closePanel(tester);
      await _ensure(tester, find.widgetWithText(Card, '合成课程 7'));
      await shot('expired', '主动包含过期课程，保留服务器总数');
      await _panel(tester);
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, '已过期'))
            .selected,
        isTrue,
      );
      await _tap(tester, find.text('恢复默认'));
      await _edit(tester, '筛选详情', '合成课程 1');
      await _closePanel(tester);
      await shot('filtered', '关闭后搜索仍作用于当前页，未发新请求');
      await _panel(tester);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '筛选详情'))
            .controller!
            .text,
        '合成课程 1',
      );
      await _edit(tester, '筛选详情', '');
      await _closePanel(tester);
      expect(backend.boyaReads, hasLength(reads));
      await _tap(tester, find.widgetWithText(Card, '合成课程 1'));
      expect(backend.boyaReads.last.courseId, '101');
      await shot('course-detail-top', '课程标题状态、基本信息和时间安排');
      await _ensure(tester, find.widgetWithText(OutlinedButton, '准备选课'));
      await shot('course-detail-actions', '详情底部操作来自独立typed资格');
      await _tap(tester, find.widgetWithText(OutlinedButton, '准备选课'));
      expect(backend.preparedBoya.last, (
        WriteOperation.bykcSelectCourse,
        101,
        null,
      ));
      await shot('select-confirm', '仅准备合成101号课程，未使用兼容字段999');
      await _tap(tester, find.widgetWithText(OutlinedButton, '取消'));
      await _tap(tester, find.byTooltip('返回'));
      await _tap(tester, find.widgetWithText(Card, '合成课程 5'));
      await _ensure(tester, find.widgetWithText(OutlinedButton, '准备选课'));
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '准备选课'))
            .onPressed,
        isNull,
      );
      await shot('unknown-detail', '未知资格保持不可操作，不从可选状态猜写资格');
      await _tap(tester, find.byTooltip('返回'));
      await _tap(tester, find.byTooltip('返回'));
      await _tap(tester, find.widgetWithText(Card, '我的课程'));
      await shot('chosen', '已选卡片突出考勤、考核和零分，不铺编号');
      final beforeDetail = backend.boyaReads.length;
      await _tap(tester, find.widgetWithText(Card, '合成已选课 1'));
      expect(backend.boyaReads, hasLength(beforeDetail));
      expect(find.widgetWithText(AppBar, '课程详情'), findsOneWidget);
      await shot('chosen-detail-top', '已选独立详情保留原记录和课程身份');
      await _ensure(tester, find.widgetWithText(OutlinedButton, '准备博雅签到'));
      await shot('chosen-detail-actions', '签到配置及原签到、签退、退选能力保持可达');
      for (final item in [
        ('准备博雅签到', 1, 'sign-in-confirm'),
        ('准备博雅签退', 2, 'sign-out-confirm'),
      ]) {
        await _tap(tester, find.widgetWithText(OutlinedButton, item.$1));
        expect(backend.preparedBoya.last, (
          WriteOperation.bykcSignCourse,
          101,
          item.$2,
        ));
        await shot(item.$3, '合成签到类型与课程目标核对，仅准备与取消');
        await _tap(tester, find.widgetWithText(OutlinedButton, '取消'));
        expect(find.widgetWithText(AppBar, '课程详情'), findsOneWidget);
      }
      await _tap(tester, find.widgetWithText(OutlinedButton, '准备退选'));
      expect(backend.preparedBoya.last, (
        WriteOperation.bykcDeselectCourse,
        101,
        null,
      ));
      await shot('deselect-confirm', '退选仍针对课程101，而非记录9001');
      await _tap(tester, find.widgetWithText(OutlinedButton, '取消'));
      await _tap(tester, find.byTooltip('返回'));
      await _tap(tester, find.byTooltip('返回'));
      await _tap(tester, find.widgetWithText(Card, '课程统计'));
      expect(find.text('0'), findsOneWidget);
      await shot('statistics', '旧总次数卡与分类三列，权威达标不由前端重算');
      await _panel(tester);
      await _edit(tester, '筛选详情', '分类 1');
      await _closePanel(tester);
      expect(find.text('总体净有效次数'), findsOneWidget);
      await shot('statistics-filter', '筛选分类仍保留独立总次数');
      await _panel(tester);
      await _edit(tester, '筛选详情', '');
      await _tap(tester, find.byType(DropdownButton<FeatureQueryView>));
      await _tap(tester, find.text('个人资料').last);
      await _tap(tester, find.text('应用筛选'));
      await _closePanel(tester);
      expect(backend.boyaReads.last.view, FeatureQueryView.bykcProfile);
      await shot('profile', '既有博雅资料查询继续可达，仅合成白名单字段');
      expect(backend.commitCalls, 0);
    });
    for (final view in ['courses', 'chosen', 'statistics']) {
      for (final state in [
        'empty',
        'first-error',
        'stale',
        'loading',
        'long',
        'many',
      ]) {
        testWidgets('博雅原生 $view $state ${brightness.name}', (tester) async {
          final backend = BoyaBackend(state: state);
          if (state == 'long') {
            tester.platformDispatcher.textScaleFactorTestValue = 1.3;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
          }
          await _mount(tester, backend, brightness, view);
          Future<void> shot(String scene, String steps) => _shot(
            binding,
            tester,
            '${brightness.name}-$view-$state-$scene',
            steps,
          );
          if (state == 'stale') {
            backend.failNext = true;
            await _tap(tester, find.byTooltip('刷新当前查询'));
            await _ensure(tester, find.text('以下为上次成功加载的数据。'));
          } else if (state == 'loading') {
            if (view == 'chosen') {
              await _tap(tester, find.widgetWithText(Card, '合成已选课 1'));
            }
            final gate = Completer<void>();
            backend.pending = gate;
            await tester.tap(find.byTooltip('刷新当前查询'));
            await tester.pump(const Duration(milliseconds: 200));
            expect(find.text('准备退选'), findsNothing);
            await shot('pending', '加载中不呈现上一次的可操作详情');
            gate.complete();
            await tester.pumpAndSettle();
          } else if (state == 'many') {
            if (view == 'courses') {
              await _panel(tester);
              await _tap(tester, find.text('状态不限'));
              await _edit(tester, '每页数量', '50');
              await _tap(tester, find.text('应用筛选'));
              await _closePanel(tester);
            }
            await shot('top', '42条合成记录首屏');
            await _ensure(
              tester,
              view == 'statistics'
                  ? find.text('分类 42')
                  : find.widgetWithText(
                      Card,
                      view == 'courses' ? '合成课程 42' : '合成已选课 42',
                    ),
            );
          }
          await shot('result', '明确合成状态与原生异常检查');
          if (state == 'first-error') {
            await _tap(tester, find.widgetWithText(TextButton, '重试'));
            await shot('retry', '显式重试恢复当前视图');
          }
          if (state == 'long' && view != 'statistics') {
            await _tap(
              tester,
              find.widgetWithText(
                Card,
                view == 'courses'
                    ? '合成课程 1${' 与跨学科创新实践及大学生活专题研讨的较长名称' * 3}'
                    : '合成已选课 1${' 与跨学科创新实践及大学生活专题研讨的较长名称' * 3}',
              ),
            );
            await shot('detail-top', '1.3字体长名称详情头部');
            await _ensure(
              tester,
              find.widgetWithText(
                OutlinedButton,
                view == 'courses' ? '准备选课' : '准备退选',
              ),
            );
            await shot('detail-actions', '长内容滚动后操作仍可达');
          }
          expect(backend.commitCalls, 0);
        });
      }
    }
  }
}

Future<void> _mount(
  WidgetTester tester,
  BoyaBackend backend,
  Brightness brightness,
  String view,
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
  await _tap(tester, find.widgetWithText(Card, FeatureId.bykc.title));
  await _tap(
    tester,
    find.widgetWithText(
      Card,
      view == 'courses'
          ? '选择课程'
          : view == 'chosen'
          ? '我的课程'
          : '课程统计',
    ),
  );
}
