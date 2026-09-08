import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'backend.dart';
part 'support.dart';

void main() {
  if (const bool.fromEnvironment('UBAA_UI_INSPECTION')) {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(
      UbaaFlutterApp(
        backend: GradesOldBackend(),
        credentialVault: MemoryCredentialVault(),
        initialTab: 1,
      ),
    );
    return;
  }
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  for (final brightness in Brightness.values) {
    testWidgets('成绩旧版原生正常与查询保留 ${brightness.name}', (tester) async {
      final backend = GradesOldBackend();
      await mount(tester, backend, brightness);
      Future<void> shot(String name, String steps) =>
          capture(binding, tester, '${brightness.name}-grades-$name', steps);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('本学期'), findsOneWidget);
      expect(find.byTooltip('实际路线：混合'), findsOneWidget);
      await shot('list', '旧版全部统计、本学期、描边课程卡同一滚动区域');
      await tap(tester, find.byTooltip('实际路线：混合'));
      await shot('routes', '同一个图标说明各学期实际路线，默认Auto不冒充结果');
      await tap(tester, find.widgetWithText(TextButton, '关闭'));
      final reads = backend.gradeReads.length;
      await tap(tester, find.byTooltip('搜索与筛选'));
      await tap(tester, find.widgetWithText(TextField, '筛选详情'));
      await tester.enterText(
        find.widgetWithText(TextField, '筛选详情'),
        'GRADE-SAFE',
      );
      await closePanel(tester);
      expect(find.text('合成待出课程'), findsNothing);
      await shot('filtered', '搜索课程号保留完整学期统计，关闭面板无额外读取');
      await tap(tester, find.byTooltip('搜索与筛选'));
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '筛选详情'))
            .controller!
            .text,
        'GRADE-SAFE',
      );
      await shot('draft', '重开搜索面板保留草稿');
      await tap(tester, find.widgetWithText(TextField, '筛选详情'));
      await tester.enterText(find.widgetWithText(TextField, '筛选详情'), '');
      await closePanel(tester);
      expect(backend.gradeReads.length, reads);
      await tap(tester, find.text('合成数学课程'));
      expect(find.text('RAW-KEEP'), findsOneWidget);
      await shot('detail', '完整原始分数绩点保留本地详情，不以统计绩点替换');
      await tap(tester, find.text('更多信息'));
      await shot('detail-more', '课程号、学期和兼容低频字段不丢失');
      await tap(tester, find.widgetWithText(TextButton, '关闭'));
      for (final (label, view) in [
        ('待出成绩', FeatureQueryView.gradesMissing),
        ('已出成绩', FeatureQueryView.gradesScored),
        ('全部成绩', FeatureQueryView.summary),
      ]) {
        await tap(tester, find.byTooltip('搜索与筛选'));
        await tap(tester, find.byType(DropdownButton<FeatureQueryView>));
        await tap(tester, find.text(label).last);
        await tap(tester, find.text('应用筛选'));
        expect(
          tester
              .widget<UbaaMainShell>(find.byType(UbaaMainShell))
              .snapshots[FeatureId.grades]!
              .readContext!
              .query!
              .view,
          view,
        );
        await closePanel(tester);
        await shot('view-${view.name.toLowerCase()}', '成绩三视图保留完整学期统计');
      }
      await tap(tester, find.byTooltip('搜索与筛选'));
      await tap(tester, find.text('选择学期'));
      final pickerSurface = find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Material),
          )
          .first;
      expect(tester.getSize(pickerSurface).height, lessThan(400));
      await shot('term-picker', '少量学期选择按内容收缩，较多选项才滚动');
      await tap(tester, find.text('合成上一学期'));
      await tap(tester, find.text('应用筛选'));
      await closePanel(tester);
      expect(
        tester
            .widget<UbaaMainShell>(find.byType(UbaaMainShell))
            .snapshots[FeatureId.grades]!
            .readContext!
            .query!
            .term,
        '2025-2026-2',
      );
      expect(backend.gradeReads.length, reads);
      await shot('other-term', '通过旧学期入口选择真实选项；本学期统计跟随当前查询');
      expect(backend.commitCalls, 0);
    });
    if (const bool.fromEnvironment('UBAA_UI_GRADES_QUERIES_ONLY')) continue;
    for (final state in [
      'empty',
      'first-error',
      'stale',
      'loading',
      'partial',
      'summary-loading',
      'long',
      'many',
    ]) {
      testWidgets('成绩旧版原生 $state ${brightness.name}', (tester) async {
        final backend = GradesOldBackend(state: state);
        if (state == 'summary-loading') {
          backend.aggregatePending = Completer<void>();
        }
        if (state == 'long') {
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        }
        await mount(tester, backend, brightness);
        Future<void> shot(String name) => capture(
          binding,
          tester,
          '${brightness.name}-grades-$state-$name',
          '显式合成状态，原生视口与系统字体',
        );
        if (state == 'loading' || state == 'stale') {
          backend.failGrades = state == 'stale';
          if (state == 'loading') backend.gradesPending = Completer<void>();
          await tester.tap(find.byTooltip('刷新当前查询'));
          await tester.pump(const Duration(milliseconds: 300));
          await shot('refresh');
          backend.gradesPending?.complete();
          await tester.pumpAndSettle();
        }
        await shot('top');
        if (state == 'summary-loading') {
          expect(find.text('统计中'), findsNWidgets(3));
          backend.aggregatePending!.complete();
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 250));
          expect(find.byTooltip('实际路线：混合'), findsOneWidget);
          await shot('complete');
        } else if (state == 'first-error') {
          await tap(tester, find.text('重试'));
          await tester.pump(const Duration(milliseconds: 250));
          expect(find.byTooltip('实际路线：混合'), findsOneWidget);
          await shot('retry');
        } else if (state == 'partial') {
          expect(find.text('部分统计 · 已读取 1/2 个学期'), findsOneWidget);
        } else if (state == 'long') {
          await tap(tester, find.text(backend.title('合成数学课程')));
          await shot('detail');
          await tap(tester, find.widgetWithText(TextButton, '关闭'));
        } else if (state == 'many') {
          await ensure(tester, find.text('合成更多课程 42'));
          await shot('bottom');
        }
        expect(backend.commitCalls, 0);
      });
    }
  }
}

Future<void> mount(
  WidgetTester tester,
  GradesOldBackend backend,
  Brightness brightness,
) async {
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await tester.pumpWidget(
    UbaaFlutterApp(
      backend: backend,
      credentialVault: MemoryCredentialVault(),
      initialTab: 1,
    ),
  );
  await tester.pumpAndSettle();
  final card = find.descendant(
    of: find.byType(CustomScrollView),
    matching: find.widgetWithText(Card, FeatureId.grades.title),
  );
  await tap(tester, card);
}

Future<void> closePanel(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tap(tester, find.widgetWithText(TextButton, '完成'));
}
