import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../support/navigation.dart';

void main() {
  testWidgets('十二个领域沿展示分组进入且不新增查询', (tester) async {
    await _mount(tester);
    expect(find.widgetWithText(AppBar, '首页'), findsOneWidget);
    for (final feature in FeatureId.values) {
      final group = UiDestination.forFeature(feature);
      await openFeature(tester, feature);
      expect(
        find.widgetWithText(
          AppBar,
          feature == FeatureId.schedule ? '课表' : feature.title,
        ),
        findsOneWidget,
      );
      expect(find.text('合成详情-${feature.wireName}'), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, group.label), findsOneWidget);
      expect(find.byTooltip('返回'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('手机横屏高度不足时侧边导航的每个分组仍可点击', (tester) async {
    await _mount(tester);
    tester.view.physicalSize = const Size(874, 402);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    for (final destination in UiDestination.values.take(4)) {
      // 不先滚动：用户看不到被遮住的入口，也不会想到侧边栏可以滚动。
      final target = find.byTooltip(destination.label);
      expect(target.hitTestable(), findsOneWidget, reason: destination.label);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        destination.index,
        reason: destination.label,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('同一导航在599到600到999到1000使用对应形态且标签可读', (tester) async {
    await _mount(tester);
    final state = tester.state(find.byType(UbaaMainShell));
    for (final width in <double>[599, 600, 999, 1000]) {
      tester.view.physicalSize = Size(width, 1000);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(UbaaMainShell)), same(state));
      for (final label in UiDestination.values.map((item) => item.label)) {
        if (label == '我的' || (width < 600 && label == '设置')) {
          await openUtility(tester, label);
          expect(find.widgetWithText(AppBar, label), findsOneWidget);
        } else if (width >= 600 && width < 1000) {
          expect(find.byTooltip(label), findsOneWidget);
        } else {
          expect(find.text(label), findsWidgets);
        }
      }
      if (width < 600) {
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byType(NavigationRail), findsNothing);
      } else if (width < 1000) {
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byType(NavigationRail), findsOneWidget);
        final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
        expect(rail.extended, isFalse);
        expect(rail.labelType, NavigationRailLabelType.none);
      } else {
        expect(find.widgetWithText(ListTile, '校园'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }
  });
}

Future<void> _mount(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(599, 1000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: UbaaTheme.light(),
      home: UbaaMainShell(
        user: const UserSummary(username: 'fixture-student'),
        snapshots: <FeatureId, FeatureSnapshot>{
          for (final feature in FeatureId.values)
            feature: FeatureSnapshot(
              feature: feature,
              status: FeatureLoadStatus.success,
              summary: '合成结果',
              details: <FeatureDetail>[
                FeatureDetail(
                  title: '合成详情-${feature.wireName}',
                  presentation: feature == FeatureId.judge
                      ? JudgeAssignmentPresentation(
                          courseId: 'c',
                          courseName: '合成课程',
                          assignmentId: 'a',
                          status: AssignmentSubmissionStatus.unsubmitted,
                          statusText: '未提交',
                          totalProblems: 1,
                          submittedCount: 0,
                        )
                      : feature == FeatureId.spoc
                      ? const SpocAssignmentPresentation(
                          courseId: 'c',
                          courseName: '合成课程',
                          assignmentId: 'a',
                          status: AssignmentSubmissionStatus.unsubmitted,
                          statusText: '未提交',
                        )
                      : null,
                ),
              ],
            ),
        },
        routePolicy: RoutePolicy.auto,
        onRefresh: () async => fail('导航不能新增刷新'),
        onRetryFeature: (_) async => fail('导航不能新增重试'),
        onFeatureQuery: (_, _) async => fail('导航不能新增业务查询'),
        onCommitWrite: (_) async => fail('功能卡片只能导航，不能提交写入'),
        onLogout: () async {},
        onLogoutAndClearAccount: () async {},
        onRoutePolicyChanged: (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}
