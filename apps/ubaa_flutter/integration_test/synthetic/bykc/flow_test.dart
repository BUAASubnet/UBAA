import 'package:ubaa_ui/ubaa_ui.dart' show UiDestination, UbaaMainShell;
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'backend.dart';
import 'feedback_backend.dart';
part 'support.dart';

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final brightness in Brightness.values) {
    testWidgets('博雅原生选课回读期间保留卡片 ${brightness.name}', (tester) async {
      final backend = BoyaFeedbackBackend();
      await _mount(tester, backend, brightness, 'courses');
      final card = find.widgetWithText(Card, '合成课程 1');
      final action = find.descendant(
        of: card,
        matching: find.widgetWithText(OutlinedButton, '选课'),
      );
      await _ensure(tester, action);
      await tester.tap(action);
      await tester.pump(const Duration(milliseconds: 100));
      expect(backend.readbacks, 1);
      expect(card, findsOneWidget);
      await _shot(
        binding,
        tester,
        '${brightness.name}-write-readback',
        '固定路线回读时保留列表和按钮内进度',
      );
      backend.readback.complete();
      await tester.pump(const Duration(milliseconds: 100));
      expect(card, findsOneWidget);
      backend.refresh.complete();
      await tester.pumpAndSettle();
      expect(backend.commitCalls, 1);
      expect(
        find.descendant(
          of: card,
          matching: find.widgetWithText(OutlinedButton, '退选'),
        ),
        findsOneWidget,
      );
      await _shot(
        binding,
        tester,
        '${brightness.name}-write-feedback',
        '刷新完成后原地更新课程并显示浮动反馈',
      );
    });
    testWidgets('博雅原生列表直接选退保持原页 ${brightness.name}', (tester) async {
      final backend = BoyaBackend();
      await _mount(tester, backend, brightness, 'courses');
      Finder action(String label) => find.descendant(
        of: find.widgetWithText(Card, '合成课程 1'),
        matching: find.widgetWithText(OutlinedButton, label),
      );
      await _tap(tester, action('选课'));
      expect(backend.commitCalls, 1);
      expect(backend.selections[101], isTrue);
      expect(find.widgetWithText(AppBar, '选择课程'), findsOneWidget);
      await _tap(tester, action('退选'));
      expect(backend.commitCalls, 2);
      expect(backend.selections[101], isFalse);
      expect(find.widgetWithText(AppBar, '选择课程'), findsOneWidget);
      await _shot(
        binding,
        tester,
        '${brightness.name}-list-direct',
        '列表按钮直接选退一次并刷新原列表',
      );
    });
    testWidgets('博雅原生卡片查询详情与直接选退 ${brightness.name}', (tester) async {
      final backend = BoyaBackend();
      await _mount(tester, backend, brightness, 'courses');
      Future<void> shot(String scene, String steps) =>
          _shot(binding, tester, '${brightness.name}-normal-$scene', steps);
      expect(_searchField, findsOneWidget);
      expect(find.text('选课'), findsWidgets);
      await shot('courses', '课程卡片正文进入详情，独立按钮直接选退');
      final reads = backend.boyaReads.length;
      await _panel(tester);
      await _tap(tester, find.widgetWithText(FilterChip, '已过期'));
      await shot('filters', '已加载课程的状态多选仅在顶栏面板中');
      await _closePanel(tester);
      await _ensure(tester, find.widgetWithText(Card, '合成课程 7'));
      await shot('expired', '主动包含过期课程，保留原始课程数据');
      await _panel(tester);
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, '已过期'))
            .selected,
        isTrue,
      );
      await _tap(tester, find.text('恢复默认'));
      await _closePanel(tester);
      await _search(tester, '合成课程 1');
      await shot('filtered', '常驻搜索作用于已加载课程，末页不再发新请求');
      await _panel(tester);
      await _closePanel(tester);
      expect(tester.widget<TextField>(_searchField).controller!.text, '合成课程 1');
      await _search(tester, '');
      expect(backend.boyaReads, hasLength(reads));
      await _tap(tester, find.widgetWithText(Card, '合成课程 1'));
      expect(backend.boyaReads.last.courseId, '101');
      await shot('course-detail-top', '课程标题状态、基本信息和时间安排');
      await _ensure(tester, find.widgetWithText(OutlinedButton, '选课'));
      await shot('course-detail-actions', '详情底部操作来自独立typed资格');
      await _tap(tester, find.widgetWithText(OutlinedButton, '选课'));
      expect(backend.preparedBoya.last, (
        WriteOperation.bykcSelectCourse,
        101,
        null,
      ));
      expect(backend.commitCalls, 1);
      await shot('select-result', '直接提交合成101号课程并刷新详情');
      await _tap(tester, find.byTooltip('返回'));
      await _tap(tester, find.widgetWithText(Card, '合成课程 5'));
      await _ensure(tester, find.widgetWithText(OutlinedButton, '选课'));
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '选课'))
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
      expect(backend.boyaReads, hasLength(beforeDetail + 1));
      expect(backend.boyaReads.last.view, FeatureQueryView.bykcChosenCourses);
      expect(backend.boyaReads.last.courseId, '101');
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
      await _tap(tester, find.widgetWithText(OutlinedButton, '退选'));
      expect(backend.preparedBoya.last, (
        WriteOperation.bykcDeselectCourse,
        101,
        null,
      ));
      expect(backend.commitCalls, 2);
      await shot('deselect-result', '直接退选课程101并清除原记录');
      await _tap(tester, find.byTooltip('返回'));
      await _tap(tester, find.byTooltip('返回'));
      await _tap(tester, find.widgetWithText(Card, '课程统计'));
      expect(find.text('0'), findsOneWidget);
      await shot('statistics', '旧总次数卡与分类三列，权威达标不由前端重算');
      // 统计页不提供搜索与筛选；博雅资料视图已不在 GUI 提供，CLI 保留。
      expect(_searchField, findsNothing);
      expect(find.text('总体净有效次数'), findsOneWidget);
      expect(backend.commitCalls, 2);
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
            final snapshot = tester
                .widget<UbaaMainShell>(find.byType(UbaaMainShell))
                .snapshots[FeatureId.bykc]!;
            expect(snapshot.error?.code, UbaaErrorCode.networkError);
          } else if (state == 'loading') {
            if (view == 'chosen') {
              await _tap(tester, find.widgetWithText(Card, '合成已选课 1'));
            }
            final gate = Completer<void>();
            backend.pending = gate;
            await tester.tap(find.byTooltip('刷新当前查询'));
            await tester.pump(const Duration(milliseconds: 200));
            for (final button in tester.widgetList<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '退选'),
            )) {
              expect(button.onPressed, isNull);
            }
            await shot('pending', '加载中不呈现上一次的可操作详情');
            gate.complete();
            await tester.pumpAndSettle();
          } else if (state == 'many') {
            if (view == 'courses') {
              await _panel(tester);
              await _tap(tester, find.text('状态不限'));
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
                view == 'courses' ? '选课' : '退选',
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
        initialDestination: UiDestination.coursework,
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

/// 人工巡检专用构造；自动测试入口不读取巡检模式开关。
Future<void> runInspection() async {
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
      initialDestination: UiDestination.coursework,
    ),
  );
  return;
}
