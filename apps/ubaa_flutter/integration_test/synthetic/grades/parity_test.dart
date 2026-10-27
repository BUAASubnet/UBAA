import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'parity/backend.dart';
part 'parity/support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  for (final brightness in Brightness.values) {
    testWidgets('成绩旧版原生正常与查询保留 ${brightness.name}', (tester) async {
      final backend = GradesOldBackend();
      await mount(tester, backend, brightness);
      Future<void> shot(String name, String steps) =>
          capture(binding, tester, '${brightness.name}-grades-$name', steps);
      final search = find.byKey(const ValueKey<String>('feature-search-field'));
      final filterButton = find.byKey(
        const ValueKey<String>('feature-filter-button'),
      );
      expect(search, findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('本学期'), findsOneWidget);
      expect(find.byTooltip('实际路线：混合'), findsOneWidget);
      await shot('list', '旧版全部统计、本学期、描边课程卡同一滚动区域');
      await tap(tester, find.byTooltip('实际路线：混合'));
      await shot('routes', '同一个图标说明各学期实际路线，默认Auto不冒充结果');
      await tap(tester, find.widgetWithText(TextButton, '关闭'));
      final reads = backend.gradeReads.length;
      await tap(tester, search);
      await tester.enterText(search, 'GRADE-SAFE');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(find.text('合成待出课程'), findsNothing);
      await shot('filtered', '常驻搜索课程号保留完整学期统计，无额外读取');
      await tap(tester, filterButton);
      await closePanel(tester);
      expect(tester.widget<TextField>(search).controller!.text, 'GRADE-SAFE');
      await shot('draft', '开关筛选面板不清除常驻搜索');
      await tap(tester, find.byTooltip('清除搜索'));
      expect(tester.widget<TextField>(search).controller!.text, isEmpty);
      expect(backend.gradeReads.length, reads);
      await tap(tester, find.text('合成数学课程'));
      expect(find.text('RAW-KEEP'), findsOneWidget);
      await shot('detail', '完整原始分数绩点保留本地详情，不以统计绩点替换');
      await tap(tester, find.text('更多信息'));
      await shot('detail-more', '课程号、学期和兼容低频字段不丢失');
      await tap(tester, find.widgetWithText(TextButton, '关闭'));
      // 状态标签点选即发出派生视图查询，无需“应用”。
      for (final (label, view) in [
        ('待出成绩', FeatureQueryView.gradesMissing),
        ('已出成绩', FeatureQueryView.gradesScored),
        ('全部', FeatureQueryView.summary),
      ]) {
        await tap(tester, filterButton);
        await tap(tester, find.widgetWithText(ChoiceChip, label));
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
      // 学期切换器位于页面顶部，在已读取的全部学期间本地切换，不发新查询。
      final termReads = backend.gradeReads.length;
      await tap(tester, find.byTooltip('选择学期'));
      await shot('term-picker', '页面顶部学期切换器列出已读取学期');
      await tap(tester, find.text('合成上一学期').last);
      expect(
        find.descendant(
          of: find.byTooltip('选择学期'),
          matching: find.text('合成上一学期'),
        ),
        findsOneWidget,
      );
      expect(backend.gradeReads.length, termReads);
      await shot('other-term', '通过页面学期切换器查看上一学期；本学期统计不被覆盖');
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
          expect(find.byType(CircularProgressIndicator), findsWidgets);
          expect(
            backend.gradeReads.any((q) => q.term == '2025-2026-2'),
            isTrue,
          );
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
      initialDestination: UiDestination.academic,
    ),
  );
  await tester.pumpAndSettle();
  final card = find.descendant(
    of: find.byType(CustomScrollView),
    matching: find.widgetWithText(Card, FeatureId.grades.title),
  );
  await ensure(tester, card);
  await tester.tap(card);
  if (backend.aggregatePending == null) {
    await tester.pumpAndSettle();
  } else {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!backend.gradeReads.any((q) => q.term == '2025-2026-2') &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(backend.gradeReads.any((q) => q.term == '2025-2026-2'), isTrue);
    await tester.pump();
  }
}

Future<void> closePanel(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tap(tester, find.byTooltip('关闭筛选'));
}

/// 人工巡检专用构造；自动测试入口不读取巡检模式开关。
Future<void> runInspection() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    UbaaFlutterApp(
      backend: GradesOldBackend(),
      credentialVault: MemoryCredentialVault(),
      initialDestination: UiDestination.academic,
    ),
  );
  return;
}
