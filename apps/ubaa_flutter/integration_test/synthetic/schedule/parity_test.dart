import 'package:ubaa_ui/ubaa_ui.dart' show UiDestination;
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'parity/backend.dart';
part 'parity/support.dart';

void main() {
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
        // 周次沿课表自身的选择器切换，不经手填。
        await tap(tester, find.byTooltip('下一周'));
        expect(backend.scheduleReads.last.week, 5);
        await tap(tester, find.text('第 5 周'));
        expect(find.text('选择教学周'), findsOneWidget);
        await capture(
          binding,
          tester,
          '${brightness.name}-normal-week-picker',
          '课表自身的教学周选择器列出合成周次',
        );
        await tap(tester, find.widgetWithText(ListTile, '第 4 周'));
        expect(backend.scheduleReads.last.term, '2026-2027-1');
        expect(backend.scheduleReads.last.week, 4);
        expect(backend.scheduleReads.length, reads + 2);
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
          final before = backend.scheduleReads.length;
          backend.fail = true;
          await tap(tester, find.byTooltip('刷新当前查询'));
          expect(backend.scheduleReads.length, before + 1);
          expect(find.text('合成课程1'), findsOneWidget);
          expect(find.widgetWithText(TextButton, '重试'), findsOneWidget);
          backend.fail = false;
          await tap(tester, find.widgetWithText(TextButton, '重试'));
          expect(backend.scheduleReads.length, before + 2);
          expect(find.text('合成课程1'), findsOneWidget);
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

/// 人工巡检专用构造；自动测试入口不读取巡检模式开关。
Future<void> runInspection() async {
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
      initialDestination: UiDestination.academic,
    ),
  );
  return;
}
