part of '../widgets_test.dart';

void _registerLibbookQueryTests() {
  testWidgets('图书馆查询控件提交分区和时段 typed 参数', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.libbook
              ? const <FeatureDetail>[FeatureDetail(title: '图书馆')]
              : const <FeatureDetail>[],
        ),
    };
    FeatureQuery? received;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: coordinatedShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFeatureQuery: (feature, query) async {
            expect(feature, FeatureId.libbook);
            received = query;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('图书馆座位'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('图书馆座位'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('馆列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('馆区列表'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'main-library');
    await tester.enterText(fields.at(1), 'floor-1');
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.libbookAreas);
    expect(received?.premisesId, 'main-library');
    expect(received?.storeyId, 'floor-1');
  });

  testWidgets('图书馆座位查询在时段编号为空时不提交', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.libbook
              ? const <FeatureDetail>[FeatureDetail(title: '图书馆')]
              : const <FeatureDetail>[],
        ),
    };
    var queryCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: coordinatedShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFeatureQuery: (_, _) async => queryCalls++,
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('图书馆座位'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('图书馆座位'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('馆列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('座位查询'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'area-1');
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();

    expect(queryCalls, 0);
    expect(find.text('时段编号不能为空。'), findsOneWidget);
  });
}
