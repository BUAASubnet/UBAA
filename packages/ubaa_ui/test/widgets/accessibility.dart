part of '../widgets_test.dart';

void _registerResponsiveAccessibilityTests() {
  testWidgets('窄屏动态字体、键盘焦点和全部卡片语义可用', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '${feature.title}已加载',
          details: const <FeatureDetail>[],
        ),
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(1.3),
          ),
          child: coordinatedShell(
            user: const UserSummary(username: 'student', displayName: '测试同学'),
            snapshots: snapshots,
            routePolicy: RoutePolicy.auto,
            activeRoutes: const <ConnectionMode>[ConnectionMode.direct],
            initialTab: 1,
            telemetryEnabled: false,
            onRefresh: () async {},
            onRetryFeature: (_) async {},
            onLogout: () async {},
            onLogoutAndClearAccount: () async {},
            onRoutePolicyChanged: (_) {},
            onTelemetryChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    Future<void> checkSemantics(List<FeatureId> features) async {
      for (final feature in features) {
        await tester.scrollUntilVisible(
          find.text(feature.title),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.bySemanticsLabel(RegExp('^${feature.title}：')),
          findsOneWidget,
        );
      }
    }

    await checkSemantics(ordinaryFeatureIds);
    await tester.tap(find.byKey(const ValueKey<String>('tab-高级功能')));
    await tester.pumpAndSettle();
    await checkSemantics(advancedFeatureIds);
    await tester.tap(find.byKey(const ValueKey<String>('tab-普通功能')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课表查询').first);
    await tester.pumpAndSettle();
    expect(find.text('返回功能列表'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final back = find.widgetWithText(OutlinedButton, '返回功能列表');
    expect(back, findsOneWidget);
    await tester.tap(back);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('tab-普通功能')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });
}

void _registerFeatureCardSemanticsTest() {
  testWidgets('功能卡片暴露包含状态和操作提示的无障碍语义', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: feature == FeatureId.schedule
              ? FeatureLoadStatus.success
              : FeatureLoadStatus.idle,
          summary: feature == FeatureId.schedule ? '今日课程' : null,
          details: const <FeatureDetail>[],
        ),
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: coordinatedShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          activeRoutes: const <ConnectionMode>[ConnectionMode.direct],
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('课表查询：今日课程。点击查看详情'), findsOneWidget);
  });
}
