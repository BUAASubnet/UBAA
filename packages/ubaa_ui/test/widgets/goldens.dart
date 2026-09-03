part of '../widgets_test.dart';

void _registerGoldenTests() {
  testWidgets('主页和详情页保持稳定视觉基线', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
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
          summary: '样例数据已加载',
          details: <FeatureDetail>[
            FeatureDetail(
              title: '样例${feature.title}',
              subtitle: '无签名测试数据',
              fields: const <FeatureField>[
                FeatureField(label: '状态', value: '可查看'),
              ],
            ),
          ],
          resolvedRoute: ConnectionMode.direct,
        ),
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'student', displayName: '测试同学'),
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
    await expectLater(
      find.byType(UbaaMainShell),
      matchesGoldenFile('goldens/main_shell_light.png'),
    );

    await tester.tap(find.text('课表查询'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(UbaaMainShell),
      matchesGoldenFile('goldens/feature_detail_light.png'),
    );
  });

  testWidgets('十二项功能详情分别保持视觉基线', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
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
          summary: '${feature.title}样例已加载',
          details: <FeatureDetail>[
            FeatureDetail(
              title: '${feature.title}样例',
              subtitle: '无签名测试数据',
              fields: <FeatureField>[
                FeatureField(label: '领域', value: feature.name),
                const FeatureField(label: '状态', value: '可查看'),
              ],
            ),
          ],
          resolvedRoute: ConnectionMode.direct,
        ),
    };

    Future<void> pumpShell({required int initialTab}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: UbaaTheme.light(),
          home: UbaaMainShell(
            key: ValueKey<int>(initialTab),
            user: const UserSummary(username: 'student', displayName: '测试同学'),
            snapshots: snapshots,
            routePolicy: RoutePolicy.auto,
            telemetryEnabled: false,
            activeRoutes: const <ConnectionMode>[ConnectionMode.direct],
            initialTab: initialTab,
            onRefresh: () async {},
            onRetryFeature: (_) async {},
            onFeatureQuery: (_, __) async {},
            onLogout: () async {},
            onLogoutAndClearAccount: () async {},
            onRoutePolicyChanged: (_) {},
            onTelemetryChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> capture(FeatureId feature) async {
      final target = find.text(feature.title).first;
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.text('返回功能列表'), findsOneWidget);
      await expectLater(
        find.byType(UbaaMainShell),
        matchesGoldenFile('goldens/feature_${feature.name}_light.png'),
      );
      await tester.tap(find.text('返回功能列表'));
      await tester.pumpAndSettle();
    }

    await pumpShell(initialTab: 1);
    for (final feature in ordinaryFeatureIds) {
      await capture(feature);
    }

    await pumpShell(initialTab: 2);
    for (final feature in advancedFeatureIds) {
      await capture(feature);
    }
  });

  testWidgets('共享壳在手机平板桌面与明暗主题下保持响应式视觉基线', (tester) async {
    const layouts = <({String name, Size size})>[
      (name: 'phone', size: Size(390, 844)),
      (name: 'tablet', size: Size(768, 1024)),
      (name: 'desktop', size: Size(1280, 800)),
    ];
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '${feature.title}示例已加载',
          details: <FeatureDetail>[
            FeatureDetail(
              title: '${feature.title}详情',
              subtitle: '响应式脱敏测试数据',
              fields: const <FeatureField>[
                FeatureField(label: '状态', value: '可查看'),
              ],
            ),
          ],
          resolvedRoute: ConnectionMode.direct,
        ),
    };

    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });

    for (final layout in layouts) {
      tester.view
        ..physicalSize = layout.size
        ..devicePixelRatio = 1;
      for (final dark in <bool>[false, true]) {
        final themeName = dark ? 'dark' : 'light';
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? UbaaTheme.dark() : UbaaTheme.light(),
            home: UbaaMainShell(
              key: ValueKey<String>('${layout.name}-$themeName'),
              user: const UserSummary(username: 'student', displayName: '测试同学'),
              snapshots: snapshots,
              routePolicy: RoutePolicy.auto,
              activeRoutes: const <ConnectionMode>[ConnectionMode.direct],
              telemetryEnabled: false,
              onRefresh: () async {},
              onRetryFeature: (_) async {},
              onFeatureQuery: (_, __) async {},
              onLogout: () async {},
              onLogoutAndClearAccount: () async {},
              onRoutePolicyChanged: (_) {},
              onTelemetryChanged: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          layout.size.width >= 800
              ? find.byType(NavigationRail)
              : find.byType(NavigationBar),
          findsOneWidget,
        );
        await expectLater(
          find.byType(UbaaMainShell),
          matchesGoldenFile(
            'goldens/responsive_${layout.name}_${themeName}_main.png',
          ),
        );

        await tester.tap(find.text('课表查询').first);
        await tester.pumpAndSettle();
        expect(find.text('返回功能列表'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(UbaaMainShell),
          matchesGoldenFile(
            'goldens/responsive_${layout.name}_${themeName}_detail.png',
          ),
        );
      }
    }
  });
}
