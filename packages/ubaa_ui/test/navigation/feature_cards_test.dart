import 'dart:ui' show SemanticsAction;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

const _featureGroups = <int, List<FeatureId>>{
  1: [
    FeatureId.schedule,
    FeatureId.exam,
    FeatureId.grades,
    FeatureId.bykc,
    FeatureId.classroom,
    FeatureId.spoc,
    FeatureId.judge,
    FeatureId.libbook,
  ],
  2: [FeatureId.cgyy, FeatureId.ygdk, FeatureId.evaluation, FeatureId.signin],
};

void main() {
  for (final group in _featureGroups.entries) {
    for (final feature in group.value) {
      if (feature == group.value.first) {
        testWidgets('完整语义标签激活${feature.title}并返回原功能分组', (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            final reads = await _showGroup(tester, group.key);
            await _revealCard(tester, feature);
            final label = '${feature.title}：合成快照摘要。点击查看详情';
            final labeledCard = find.bySemanticsLabel(label);
            final node = tester.getSemantics(labeledCard);
            final data = node.getSemanticsData();
            final tapActions = _countTapActions(node);

            tester
                .renderObject(labeledCard)
                .owner!
                .semanticsOwner!
                .performAction(node.id, SemanticsAction.tap);
            await tester.pumpAndSettle();

            _expectFeaturePage(feature);
            expect(data.label, label);
            expect(data.flagsCollection.isButton, isTrue);
            expect(data.hasAction(SemanticsAction.tap), isTrue);
            expect(tapActions, 1, reason: '一张卡片只暴露一个完整标签的点击动作');
            await _returnToGroup(tester, group.key, feature);
            expect(reads, isEmpty, reason: '入口导航复用合成快照，不新增读取');
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        });
      }

      testWidgets('物理点击${feature.title}后一次返回即可回到原功能分组', (tester) async {
        final reads = await _showGroup(tester, group.key);
        final card = await _revealCard(tester, feature);

        await tester.tap(card);
        await tester.pumpAndSettle();

        _expectFeaturePage(feature);
        await _returnToGroup(tester, group.key, feature);
        expect(reads, isEmpty, reason: '物理点击不额外重试或重新读取');
        expect(tester.takeException(), isNull);
      });
    }
  }
}

int _countTapActions(SemanticsNode node) {
  var count = node.getSemanticsData().hasAction(SemanticsAction.tap) ? 1 : 0;
  node.visitChildren((child) {
    count += _countTapActions(child);
    return true;
  });
  return count;
}

void _expectFeaturePage(FeatureId feature) {
  expect(find.widgetWithText(AppBar, feature.title), findsOneWidget);
  expect(find.byTooltip('返回'), findsOneWidget);
}

Future<void> _returnToGroup(
  WidgetTester tester,
  int tab,
  FeatureId feature,
) async {
  await tester.tap(find.byTooltip('返回'));
  await tester.pumpAndSettle();
  expect(
    find.widgetWithText(AppBar, tab == 1 ? '普通功能' : '高级功能'),
    findsOneWidget,
  );
  expect(find.byTooltip('返回'), findsNothing);
  await _revealCard(tester, feature);
}

Future<Finder> _revealCard(WidgetTester tester, FeatureId feature) async {
  final card = find.widgetWithText(Card, feature.title);
  await tester.scrollUntilVisible(
    card,
    200,
    scrollable: find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  return card;
}

Future<List<FeatureId>> _showGroup(WidgetTester tester, int tab) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 632);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final reads = <FeatureId>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: UbaaTheme.dark(),
      home: UbaaMainShell(
        user: const UserSummary(username: 'synthetic'),
        initialTab: tab,
        snapshots: {
          for (final feature in FeatureId.values)
            feature: FeatureSnapshot(
              feature: feature,
              status: FeatureLoadStatus.success,
              summary: '合成快照摘要',
              resolvedRoute: ConnectionMode.direct,
              details: [FeatureDetail(title: '合成${feature.title}结果')],
            ),
        },
        routePolicy: RoutePolicy.direct,
        telemetryEnabled: false,
        onRefresh: () async {},
        onRetryFeature: (feature) async => reads.add(feature),
        onFeatureQuery: (feature, _) async => reads.add(feature),
        onCommitWrite: (_) async => fail('功能卡片只能导航，不能提交写入'),
        onLogout: () async {},
        onLogoutAndClearAccount: () async {},
        onRoutePolicyChanged: (_) {},
        onTelemetryChanged: (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
  return reads;
}
