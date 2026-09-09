import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'backend.dart';
part 'support.dart';

Future<void> chooseWeek(WidgetTester tester, String name) => tap(
  tester,
  find.descendant(of: find.byType(AlertDialog), matching: find.text(name)),
);

void main() {
  if (const bool.fromEnvironment('UBAA_UI_INSPECTION')) {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(
      UbaaFlutterApp(
        backend: ScheduleNavigationBackend(
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
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  for (final brightness in Brightness.values) {
    testWidgets('原生周导航 自动当前与选择草稿 ${brightness.name}', (tester) async {
      final backend = ScheduleNavigationBackend();
      await mount(tester, backend, brightness);
      expect(find.text('合成教学第4周'), findsOneWidget);
      expect(find.text('9-7'), findsOneWidget);
      expect(find.text('9-13'), findsOneWidget);
      await capture(
        binding,
        tester,
        '${brightness.name}-normal-current',
        '唯一当前学期和周自动进入，标题与真实七日日期',
      );
      await tap(tester, find.byTooltip('搜索与筛选'));
      await tap(tester, find.widgetWithText(OutlinedButton, '选择教学周'));
      await capture(
        binding,
        tester,
        '${brightness.name}-normal-weeks',
        '旧周列表、日期、本周和已选提示，按内容收缩',
      );
      await chooseWeek(tester, '合成教学第5周');
      final reads = backend.scheduleReads.length;
      await tap(tester, find.widgetWithText(TextButton, '完成'));
      expect(find.text('合成教学第4周'), findsOneWidget);
      await tap(tester, find.byTooltip('搜索与筛选'));
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '周次'))
            .controller!
            .text,
        '5',
      );
      expect(backend.scheduleReads.length, reads);
      await capture(
        binding,
        tester,
        '${brightness.name}-normal-draft',
        '关闭重开保留第5周草稿，未把它当成已显示第4周',
      );
      await tap(tester, find.text('应用筛选'));
      await tap(tester, find.widgetWithText(TextButton, '完成'));
      expect(find.text('合成教学第5周'), findsOneWidget);
      expect(find.text('9-14'), findsOneWidget);
      await capture(
        binding,
        tester,
        '${brightness.name}-normal-applied',
        '明确应用后才读取新周课程并更新日期',
      );
      await tap(tester, find.byTooltip('搜索与筛选'));
      await tap(tester, find.widgetWithText(OutlinedButton, '选择学期'));
      await tap(tester, find.text('合成上一学期'));
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '周次'))
            .controller!
            .text,
        isEmpty,
      );
      await tap(tester, find.widgetWithText(OutlinedButton, '选择教学周'));
      await chooseWeek(tester, '合成教学第3周');
      await tap(tester, find.text('应用筛选'));
      await tap(tester, find.widgetWithText(TextButton, '完成'));
      expect(backend.scheduleReads.last.term, '2025-2026-2');
      expect(find.text('3-3'), findsOneWidget);
      await capture(
        binding,
        tester,
        '${brightness.name}-normal-other-term',
        '切换学期后清掉旧周，日期来自该学期返回值',
      );
    });
    for (final state in [
      'long',
      'empty',
      'first-error',
      'stale',
      'loading',
      'no-current',
      'ambiguous-term',
      'no-current-week',
      'duplicate-week',
      'gapped',
      'options-error',
    ]) {
      testWidgets('原生周导航 $state ${brightness.name}', (tester) async {
        final backend = ScheduleNavigationBackend(state: state);
        await mount(
          tester,
          backend,
          brightness,
          textScale: state == 'long' ? 1.3 : 1,
        );
        if (state == 'stale') {
          backend.fail = true;
          await tap(tester, find.byTooltip('刷新当前查询'));
          expect(find.text('9-7'), findsOneWidget);
          expect(find.text('以下为上次成功加载的数据。'), findsWidgets);
        }
        if (state == 'loading') {
          final gate = Completer<void>();
          backend.schedulePending = gate;
          await tester.tap(find.byTooltip('刷新当前查询'));
          await tester.pump();
          await capture(
            binding,
            tester,
            '${brightness.name}-$state-pending',
            '课程读取等待态，不显示旧日期为新周',
          );
          gate.complete();
          backend.schedulePending = null;
          await tester.pumpAndSettle();
        }
        await capture(
          binding,
          tester,
          '${brightness.name}-$state-top',
          '自然周选择的原生状态',
        );
        if (state == 'first-error') {
          await tap(tester, find.text('重试'));
          expect(find.text('9-7'), findsOneWidget);
          await capture(
            binding,
            tester,
            '${brightness.name}-$state-recovered',
            '显式重试恢复周课表',
          );
        }
        if (state == 'empty') {
          expect(find.text('本周暂无课程'), findsOneWidget);
          expect(find.text('9-7'), findsOneWidget);
        }
        if (state == 'long') {
          expect(
            tester.widget<Text>(find.text(backend.title('合成教学第4周'))).maxLines,
            1,
          );
          await tap(tester, find.byTooltip('搜索与筛选'));
          await tap(tester, find.widgetWithText(OutlinedButton, '选择教学周'));
          await capture(
            binding,
            tester,
            '${brightness.name}-$state-options',
            '1.3长周名称在列表完整换行，顶栏单行省略',
          );
          await chooseWeek(tester, backend.title('合成教学第5周'));
          await tap(tester, find.text('应用筛选'));
          await tap(tester, find.widgetWithText(TextButton, '完成'));
          await capture(
            binding,
            tester,
            '${brightness.name}-$state-next',
            '长文字周选择和真实日期更新',
          );
        }
        if ([
          'no-current',
          'ambiguous-term',
          'no-current-week',
          'duplicate-week',
        ].contains(state)) {
          expect(backend.scheduleReads, isEmpty);
          expect(find.text('请从右上角选择学期和教学周'), findsOneWidget);
          await tap(tester, find.byTooltip('搜索与筛选'));
          if (state == 'no-current' || state == 'ambiguous-term') {
            await tap(tester, find.widgetWithText(OutlinedButton, '选择学期'));
            await tap(tester, find.text('合成本学期'));
          }
          await tap(tester, find.widgetWithText(OutlinedButton, '选择教学周'));
          if (state == 'duplicate-week') {
            expect(
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.text('合成教学第4周'),
              ),
              findsNothing,
            );
            expect(find.text('重复编号周'), findsNothing);
          }
          await capture(
            binding,
            tester,
            '${brightness.name}-$state-choice',
            '无唯一当前标记时明确选择，重复编号不静默采用',
          );
          await chooseWeek(tester, '合成教学第3周');
          await tap(tester, find.text('应用筛选'));
          await tap(tester, find.widgetWithText(TextButton, '完成'));
          expect(backend.scheduleReads.single.week, 3);
          expect(find.text('8-31'), findsOneWidget);
          await capture(
            binding,
            tester,
            '${brightness.name}-$state-selected',
            '仅在明确选择后读取原term/week',
          );
        }
        if (state == 'gapped') {
          expect(backend.scheduleReads.single.week, 7);
          await tap(tester, find.byTooltip('搜索与筛选'));
          await tap(tester, find.byTooltip('上一教学周'));
          expect(
            tester
                .widget<TextField>(find.widgetWithText(TextField, '周次'))
                .controller!
                .text,
            '3',
          );
          await tap(tester, find.byTooltip('下一教学周'));
          await tap(tester, find.byTooltip('下一教学周'));
          expect(
            tester
                .widget<TextField>(find.widgetWithText(TextField, '周次'))
                .controller!
                .text,
            '12',
          );
          expect(backend.scheduleReads, hasLength(1));
          await capture(
            binding,
            tester,
            '${brightness.name}-$state-draft',
            '前后周按原列表3→7→12，而非猜加减一',
          );
        }
        if (state == 'options-error') {
          backend.failOptions = FeatureQueryView.scheduleWeeks;
          await tap(tester, find.byTooltip('搜索与筛选'));
          await tap(tester, find.widgetWithText(OutlinedButton, '选择教学周'));
          expect(find.text('重试'), findsWidgets);
          await capture(
            binding,
            tester,
            '${brightness.name}-$state-failed',
            '周选项读取失败不覆盖课表',
          );
          backend.failOptions = null;
          await tap(tester, find.text('重新获取'));
          await chooseWeek(tester, '合成教学第5周');
          await capture(
            binding,
            tester,
            '${brightness.name}-$state-recovered',
            '周选项明确重试保留原草稿，不自动提交',
          );
          expect(backend.scheduleReads, hasLength(1));
        }
      });
    }
  }
}
