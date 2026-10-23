import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_ui/src/app/home.dart';

Future<void> mount(
  WidgetTester tester,
  String account,
  Future<List<FeatureId>> Function() load,
  Future<void> Function(List<FeatureId>) save,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: UbaaMainShell(
        user: UserSummary(username: account),
        snapshots: {
          for (final f in FeatureId.values)
            f: FeatureSnapshot(feature: f, status: FeatureLoadStatus.empty),
        },
        routePolicy: RoutePolicy.auto,
        telemetryEnabled: false,
        onRefresh: () async {},
        onRetryFeature: (_) async {},
        onLogout: () async {},
        onLogoutAndClearAccount: () async {},
        onRoutePolicyChanged: (_) {},
        onTelemetryChanged: (_) {},
        onLoadRecentFeatures: load,
        onSaveRecentFeatures: save,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

HomeView home(WidgetTester tester) =>
    tester.widget<HomeView>(find.byType(HomeView, skipOffstage: false));

void main() {
  testWidgets('迟到恢复合并到本轮访问之后，重复入口只保留最近位置', (tester) async {
    final pending = Completer<List<FeatureId>>();
    final saved = <List<FeatureId>>[];
    await mount(
      tester,
      'a',
      () => pending.future,
      (value) async => saved.add(value),
    );
    home(tester).onFeatureTap(FeatureId.exam);
    await tester.pumpAndSettle();
    pending.complete([FeatureId.grades, FeatureId.exam, FeatureId.spoc]);
    await tester.pumpAndSettle();
    expect(home(tester).recentFeatures, [
      FeatureId.exam,
      FeatureId.grades,
      FeatureId.spoc,
    ]);
    expect(saved.last, [FeatureId.exam, FeatureId.grades, FeatureId.spoc]);
  });
  testWidgets('切换账号拒绝旧账号迟到记录，保存失败仍可导航', (tester) async {
    final first = Completer<List<FeatureId>>();
    await mount(tester, 'a', () => first.future, (_) async {});
    await mount(
      tester,
      'b',
      () async => [FeatureId.spoc],
      (_) async => throw StateError('合成失败'),
    );
    first.complete([FeatureId.exam]);
    await tester.pumpAndSettle();
    expect(home(tester).recentFeatures, [FeatureId.spoc]);
    home(tester).onFeatureTap(FeatureId.grades);
    await tester.pumpAndSettle();
    expect(home(tester).recentFeatures, [FeatureId.grades, FeatureId.spoc]);
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
