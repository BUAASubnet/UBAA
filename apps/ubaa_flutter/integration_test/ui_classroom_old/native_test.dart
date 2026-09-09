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
        backend: ClassroomOldBackend(
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
    testWidgets('原生旧教室表格查询草稿详情 ${brightness.name}', (tester) async {
      final backend = ClassroomOldBackend();
      await mount(tester, backend, brightness);
      expect(find.text('14'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await capture(
        binding,
        tester,
        '${brightness.name}-normal-table',
        '14节表格与楼栋标题，正文无搜索筛选',
      );
      await tap(tester, find.text('合成教室1'));
      expect(find.text('ROOM-SAFE-1'), findsOneWidget);
      expect(find.text('1,3,13'), findsOneWidget);
      await capture(
        binding,
        tester,
        '${brightness.name}-normal-detail',
        '本地详情完整保留编号、原空闲字段和实际查询来源',
      );
      await tap(tester, find.widgetWithText(TextButton, '关闭'));
      final before = backend.classroomReads.length;
      await tap(tester, find.byTooltip('搜索与筛选'));
      await edit(tester, '筛选详情', 'ROOM-SAFE-1');
      await tap(tester, find.widgetWithText(TextButton, '完成'));
      expect(find.text('合成教室1'), findsOneWidget);
      expect(find.text('合成教室2'), findsNothing);
      expect(backend.classroomReads.length, before);
      await tap(tester, find.byTooltip('搜索与筛选'));
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '筛选详情'))
            .controller!
            .text,
        'ROOM-SAFE-1',
      );
      await capture(
        binding,
        tester,
        '${brightness.name}-normal-draft',
        '关闭重开保留本地筛选，未执行学校读取',
      );
      await edit(tester, '筛选详情', '');
      await edit(tester, '日期', '2026-09-10');
      await edit(tester, '楼层', 'F2');
      await edit(tester, '节次', '14');
      await tap(tester, find.byType(DropdownButton<int>));
      await tap(tester, find.text('沙河').last);
      await tap(tester, find.widgetWithText(FilledButton, '应用筛选'));
      expect(backend.classroomReads.last.date, DateTime(2026, 9, 10));
      expect(backend.classroomReads.last.campus, 2);
      expect(backend.classroomReads.last.floorId, 'F2');
      expect(backend.classroomReads.last.section, '14');
      await tap(tester, find.widgetWithText(TextButton, '完成'));
      expect(find.text('合成教室2'), findsOneWidget);
      expect(find.text('合成教室1'), findsNothing);
      await capture(
        binding,
        tester,
        '${brightness.name}-normal-query',
        '明确应用日期校区楼栋节次，原typed参数保留',
      );
    });
    for (final state in [
      'long',
      'many',
      'empty',
      'first-error',
      'stale',
      'loading',
    ]) {
      testWidgets('原生旧教室 $state ${brightness.name}', (tester) async {
        final backend = ClassroomOldBackend(state: state);
        await mount(
          tester,
          backend,
          brightness,
          textScale: state == 'long' ? 1.3 : 1,
        );
        if (state == 'stale') {
          backend.fail = true;
          await tap(tester, find.byTooltip('刷新当前查询'));
          expect(find.text('以下为上次成功加载的数据。'), findsWidgets);
        }
        if (state == 'loading') {
          final gate = Completer<void>();
          backend.classroomPending = gate;
          await tester.tap(find.byTooltip('刷新当前查询'));
          await tester.pump();
          await capture(
            binding,
            tester,
            '${brightness.name}-$state-pending',
            '原生加载期间不伪造新结果',
          );
          gate.complete();
          backend.classroomPending = null;
          await tester.pumpAndSettle();
        }
        await capture(
          binding,
          tester,
          '${brightness.name}-$state-top',
          '旧表格原生状态与大字/长名显示',
        );
        if (state == 'long') {
          final title = find.text(backend.title('合成一号楼'));
          final right =
              tester.view.physicalSize.width / tester.view.devicePixelRatio -
              16;
          expect(tester.getRect(title).right, lessThanOrEqualTo(right));
          final horizontal = find.byWidgetPredicate(
            (w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.horizontal,
          );
          await tester.drag(horizontal, const Offset(-500, 0));
          await tester.pumpAndSettle();
          expect(find.text('14').hitTestable(), findsOneWidget);
          expect(find.text('教室').hitTestable(), findsOneWidget);
          expect(
            find.text(backend.title('合成教室1')).hitTestable(),
            findsOneWidget,
          );
          expect(tester.getRect(title).right, lessThanOrEqualTo(right));
          await capture(
            binding,
            tester,
            '${brightness.name}-long-right',
            '大字横滚到第14节，楼栋标题仍在当前可视宽度',
          );
          await tester.drag(horizontal, const Offset(500, 0));
          await tester.pumpAndSettle();
          await tap(tester, find.text(backend.title('合成教室1')));
          expect(find.text('ROOM-SAFE-1'), findsOneWidget);
          await capture(
            binding,
            tester,
            '${brightness.name}-long-detail',
            '大字长名称在本地详情完整可读，不增业务请求',
          );
          await tap(tester, find.widgetWithText(TextButton, '关闭'));
        }
        if (state == 'many') {
          final scroll = find
              .descendant(
                of: find.byKey(const ValueKey('classroom-table-scroll')),
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.scrollUntilVisible(
            find.text('合成教室42'),
            250,
            scrollable: scroll,
            maxScrolls: 60,
          );
          expect(find.text('14').hitTestable(), findsOneWidget);
          expect(find.byTooltip('下一页'), findsNothing);
          await capture(
            binding,
            tester,
            '${brightness.name}-$state-end',
            '42条连续滚动到末项，粘性14节表头仍可见',
          );
        }
        if (state == 'first-error') {
          expect(find.text('重试'), findsOneWidget);
          await tap(tester, find.text('重试'));
          expect(find.text('合成教室1'), findsOneWidget);
          await capture(
            binding,
            tester,
            '${brightness.name}-$state-retry',
            '首次失败明确重试后恢复表格',
          );
        }
      });
    }
  }
}
