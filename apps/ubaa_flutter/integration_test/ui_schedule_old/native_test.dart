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

void main() {
  if (const bool.fromEnvironment('UBAA_UI_INSPECTION')) {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(
      UbaaFlutterApp(
        backend: ScheduleOldBackend(
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
    if (!const bool.fromEnvironment('UBAA_SCHEDULE_EMPTY_ONLY')) {
      testWidgets('原生旧周课表 网格详情筛选 ${brightness.name}', (tester) async {
        final backend = ScheduleOldBackend();
        await mount(tester, backend, brightness);
        expect(find.text('周日'), findsOneWidget);
        await capture(
          binding,
          tester,
          '${brightness.name}-normal-grid',
          '七日节次网格，正文无常驻查询',
        );
        final reads = backend.scheduleReads.length;
        await tap(tester, find.text('合成课程1'));
        expect(find.text('COURSE-SAFE-1'), findsOneWidget);
        expect(find.text('合成教师与周次'), findsOneWidget);
        await capture(
          binding,
          tester,
          '${brightness.name}-normal-detail',
          '本地详情保留原字段，不依赖credit',
        );
        await tap(tester, find.widgetWithText(TextButton, '关闭'));
        expect(backend.scheduleReads.length, reads);
        await tap(tester, find.byTooltip('搜索与筛选'));
        await edit(tester, '筛选详情', 'COURSE-SAFE-2');
        await tap(tester, find.widgetWithText(TextButton, '完成'));
        expect(find.text('合成课程2'), findsOneWidget);
        expect(find.text('合成课程1'), findsNothing);
        await capture(
          binding,
          tester,
          '${brightness.name}-normal-filter',
          '低频编号本地筛选，七日结构保留',
        );
        await tap(tester, find.byTooltip('搜索与筛选'));
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, '筛选详情'))
              .controller!
              .text,
          'COURSE-SAFE-2',
        );
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, '学期编码'))
              .controller!
              .text,
          '2026-2027-1',
        );
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, '周次'))
              .controller!
              .text,
          '4',
        );
        await capture(
          binding,
          tester,
          '${brightness.name}-normal-draft',
          '关闭重开保留筛选与学期周次草稿',
        );
        expect(backend.scheduleReads.length, reads);
      });
    }
    for (final state
        in const bool.fromEnvironment('UBAA_SCHEDULE_EMPTY_ONLY')
            ? ['empty']
            : ['long', 'many', 'empty', 'first-error', 'stale', 'loading']) {
      testWidgets('原生旧周课表 $state ${brightness.name}', (tester) async {
        final backend = ScheduleOldBackend(state: state);
        await mount(
          tester,
          backend,
          brightness,
          textScale: state == 'long' ? 1.3 : 1,
        );
        if (state == 'empty') {
          expect(find.text('周一'), findsOneWidget);
          expect(find.text('本周暂无课程'), findsOneWidget);
          expect(
            tester.getRect(find.text('本周暂无课程')).top,
            greaterThan(tester.getRect(find.text('周一')).bottom),
          );
        }
        if (state == 'stale') {
          backend.fail = true;
          await tap(tester, find.byTooltip('刷新当前查询'));
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
            '原生读取等待态',
          );
          gate.complete();
          backend.schedulePending = null;
          await tester.pumpAndSettle();
        }
        await capture(
          binding,
          tester,
          '${brightness.name}-$state-top',
          '旧课表状态与长文大字',
        );
        if (state == 'first-error') {
          await tap(tester, find.text('重试'));
          expect(find.text('周一'), findsOneWidget);
          await capture(
            binding,
            tester,
            '${brightness.name}-$state-recovered',
            '失败后显式重试恢复',
          );
        }
        if (state == 'many') {
          await tap(tester, find.text('22门课程'));
          await tap(tester, find.text('合成课程22'));
          expect(find.text('COURSE-SAFE-22'), findsOneWidget);
          await capture(
            binding,
            tester,
            '${brightness.name}-$state-last-detail',
            '超过20条且重叠的最后一门仍可查看',
          );
        }
        if (state == 'long') {
          await tap(tester, find.text(backend.title('合成课程1')));
          await capture(
            binding,
            tester,
            '${brightness.name}-$state-detail',
            '1.3长课程详情完整可滚动',
          );
          await ensure(tester, find.text('合成教学对象'));
          await capture(
            binding,
            tester,
            '${brightness.name}-$state-detail-end',
            '长详情滚动到底部，教师和教学对象实际可见',
          );
          await tap(tester, find.widgetWithText(TextButton, '关闭'));
          final horizontal = find.byWidgetPredicate(
            (w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.horizontal,
          );
          await tester.drag(horizontal, const Offset(-300, 0));
          await tester.pumpAndSettle();
          await capture(
            binding,
            tester,
            '${brightness.name}-$state-right',
            '必要横滚后周日及单节长课程',
          );
          expect(find.text('1').hitTestable(), findsOneWidget);
          await tap(tester, find.text(backend.title('合成课程7')));
          expect(find.text('COURSE-SAFE-7'), findsOneWidget);
          await capture(
            binding,
            tester,
            '${brightness.name}-$state-single-detail',
            '单节课程长文字没有丢失',
          );
          await tap(tester, find.widgetWithText(TextButton, '关闭'));
          await ensure(tester, find.text('合成时间待定课程'));
          await tester.drag(horizontal, const Offset(-300, 0));
          await tester.pumpAndSettle();
          expect(
            tester.getRect(find.text('合成时间待定课程')).left,
            greaterThanOrEqualTo(8),
          );
          await capture(
            binding,
            tester,
            '${brightness.name}-$state-unknown-list',
            '网格横滚不会裁切待确认课程列表',
          );
          await tap(tester, find.text('合成时间待定课程'));
          expect(find.text('原值 9'), findsOneWidget);
          expect(find.text('不因缺少学分隐藏教师'), findsOneWidget);
          await capture(
            binding,
            tester,
            '${brightness.name}-$state-unknown',
            '异常时间原值保留，不伪造网格位置',
          );
        }
      });
    }
  }
}
