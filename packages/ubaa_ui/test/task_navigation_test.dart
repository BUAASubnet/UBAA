import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

const _learning = <FeatureId>[
  FeatureId.schedule,
  FeatureId.exam,
  FeatureId.grades,
  FeatureId.classroom,
  FeatureId.spoc,
  FeatureId.judge,
  FeatureId.evaluation,
];
const _campus = <FeatureId>[
  FeatureId.bykc,
  FeatureId.libbook,
  FeatureId.signin,
  FeatureId.cgyy,
  FeatureId.ygdk,
];

void main() {
  testWidgets('今日十二个领域均能通过实际功能卡进入且不新增查询', (tester) async {
    await _mount(tester);
    expect(find.text('今日'), findsWidgets);
    for (final feature in <FeatureId>[..._learning, ..._campus]) {
      final view = find.byType(CustomScrollView);
      tester
          .state<ScrollableState>(
            find.descendant(of: view, matching: find.byType(Scrollable)),
          )
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      final card = find.descendant(
        of: view,
        matching: find.widgetWithText(Card, feature.title),
      );
      await tester.scrollUntilVisible(
        card,
        220,
        scrollable: find.descendant(
          of: view,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(card.hitTestable(), findsOneWidget);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.text('合成详情-${feature.wireName}'), findsOneWidget);
      await tester.tap(find.text('返回功能列表'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('学习恰有七项校园恰有五项且评教博雅归类正确', (tester) async {
    await _mount(tester);
    for (final group in <(String, List<FeatureId>)>[
      ('学习', _learning),
      ('校园', _campus),
    ]) {
      final destination = find.widgetWithText(NavigationDestination, group.$1);
      expect(destination, findsOneWidget);
      await tester.tap(destination);
      await tester.pumpAndSettle();
      final observed = <FeatureId>{};
      final view = find.byType(CustomScrollView);
      final scrollable = find.descendant(
        of: view,
        matching: find.byType(Scrollable),
      );
      for (var step = 0; step < 20; step++) {
        for (final feature in FeatureId.values) {
          if (find
              .descendant(of: view, matching: find.text(feature.title))
              .evaluate()
              .isNotEmpty) {
            observed.add(feature);
          }
        }
        final position = tester.state<ScrollableState>(scrollable).position;
        if (position.pixels >= position.maxScrollExtent) break;
        await tester.drag(view, const Offset(0, -220));
        await tester.pumpAndSettle();
      }
      expect(observed, unorderedEquals(group.$2));
    }
  });

  testWidgets('同一导航在599到600到999到1000使用对应形态且标签可读', (tester) async {
    await _mount(tester);
    final state = tester.state(find.byType(UbaaMainShell));
    for (final width in <double>[599, 600, 999, 1000]) {
      tester.view.physicalSize = Size(width, 1000);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(UbaaMainShell)), same(state));
      for (final label in <String>['今日', '学习', '校园', '我的']) {
        expect(find.text(label), findsWidgets);
      }
      if (width < 600) {
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byType(NavigationRail), findsNothing);
      } else {
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byType(NavigationRail), findsOneWidget);
        final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
        expect(rail.extended, width >= 1000);
        if (width < 1000)
          expect(rail.labelType, NavigationRailLabelType.selected);
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
                FeatureDetail(title: '合成详情-${feature.wireName}'),
              ],
            ),
        },
        routePolicy: RoutePolicy.auto,
        telemetryEnabled: false,
        onRefresh: () async => fail('导航不能新增刷新'),
        onRetryFeature: (_) async => fail('导航不能新增重试'),
        onFeatureQuery: (_, _) async => fail('导航不能新增业务查询'),
        onLogout: () async {},
        onLogoutAndClearAccount: () async {},
        onRoutePolicyChanged: (_) {},
        onTelemetryChanged: (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}
