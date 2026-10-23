import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart' show UiDestination;
import 'navigation/backend.dart';
part 'navigation/support.dart';

Future<void> chooseWeek(WidgetTester tester, String name) => tap(
  tester,
  find.descendant(of: find.byType(AlertDialog), matching: find.text(name)),
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  for (final brightness in Brightness.values) {
    testWidgets('原生课表 学期与周次直接选择 ${brightness.name}', (tester) async {
      final backend = ScheduleNavigationBackend();
      await mount(tester, backend, brightness);
      await capture(
        binding,
        tester,
        '${brightness.name}-current',
        '完整作息、课程配色、统一宽度与单一周次标题',
      );
      await tap(tester, find.text('合成教学第4周'));
      await capture(
        binding,
        tester,
        '${brightness.name}-weeks',
        '周次选择保留日期与当前周',
      );
      await chooseWeek(tester, '合成教学第5周');
      expect(backend.scheduleReads.last.week, 5);
      expect(find.text('9-14'), findsOneWidget);
      await tap(tester, find.byTooltip('选择学期'));
      await capture(
        binding,
        tester,
        '${brightness.name}-terms',
        '直接选择学期，无需搜索筛选',
      );
      await tap(tester, find.text('合成上一学期'));
      expect(backend.scheduleReads.last.term, '2025-2026-2');
      await tap(tester, find.byTooltip('上一周'));
      expect(backend.scheduleReads.last.week, 3);
      expect(find.text('3-3'), findsOneWidget);
      await capture(
        binding,
        tester,
        '${brightness.name}-other-term',
        '切换学期及上一周后的真实日期',
      );
      await tester.drag(
        find.byKey(const ValueKey('schedule-grid-scroll')),
        const Offset(0, -950),
      );
      await tester.pumpAndSettle();
      await capture(
        binding,
        tester,
        '${brightness.name}-late-sections',
        '时间轴滚动至夜间及末节',
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
      testWidgets('原生课表 $state ${brightness.name}', (tester) async {
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
            '读取等待时保留现有课表',
          );
          gate.complete();
          backend.schedulePending = null;
          await tester.pumpAndSettle();
        }
        if (state == 'first-error') await tap(tester, find.text('重试'));
        if (state == 'empty') expect(find.text('本周暂无课程'), findsOneWidget);
        if (state == 'long') {
          await tap(tester, find.text(backend.title('合成教学第4周')));
          await chooseWeek(tester, backend.title('合成教学第5周'));
          expect(find.text('9-14'), findsOneWidget);
        }
        if ([
          'no-current',
          'ambiguous-term',
          'no-current-week',
          'duplicate-week',
        ].contains(state)) {
          expect(backend.scheduleReads, isEmpty);
          if (state == 'no-current' || state == 'ambiguous-term') {
            await tap(tester, find.byTooltip('选择学期'));
            await tap(tester, find.text('合成本学期'));
          }
          if (state == 'ambiguous-term') {
            expect(backend.scheduleReads.single.week, 4);
          } else {
            await tap(tester, find.widgetWithText(FilledButton, '选择教学周'));
            if (state == 'duplicate-week') {
              expect(
                find.descendant(
                  of: find.byType(AlertDialog),
                  matching: find.text('合成教学第4周'),
                ),
                findsNothing,
              );
            }
            await chooseWeek(tester, '合成教学第3周');
            expect(backend.scheduleReads.single.week, 3);
          }
        }
        if (state == 'gapped') {
          expect(backend.scheduleReads.single.week, 7);
          await tap(tester, find.byTooltip('上一周'));
          expect(backend.scheduleReads.last.week, 3);
          await tap(tester, find.byTooltip('下一周'));
          await tap(tester, find.byTooltip('下一周'));
          expect(backend.scheduleReads.last.week, 12);
        }
        if (state == 'options-error') {
          backend.failOptions = FeatureQueryView.scheduleWeeks;
          await tap(tester, find.text('合成教学第4周'));
          backend.failOptions = null;
          await tap(tester, find.text('重新获取'));
          await chooseWeek(tester, '合成教学第5周');
          expect(backend.scheduleReads.last.week, 5);
        }
        await capture(
          binding,
          tester,
          '${brightness.name}-$state',
          '原生边界状态及对应选择/恢复操作',
        );
      });
    }
  }
}

/// 人工巡检只使用合成课表，不连接学校服务。
Future<void> runInspection() async {
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
      initialDestination: UiDestination.academic,
    ),
  );
}
