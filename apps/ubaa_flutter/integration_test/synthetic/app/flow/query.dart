part of '../flow_test.dart';

void _registerQueryFlowTests() {
  testWidgets('宿主集成流程可打开全部十二项功能详情', (tester) async {
    await tester.pumpWidget(
      UbaaFlutterApp(
        key: const ValueKey<String>('advanced-smoke'),
        backend: _IntegrationBackend(),
        credentialVault: MemoryCredentialVault(),
        initialDestination: UiDestination.academic,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '2020000002');
    await tester.enterText(find.byType(TextField).at(1), 'fixture-password');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    expect(find.byType(UbaaMainShell), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(CustomScrollView), findsOneWidget);

    for (final feature in ordinaryFeatureIds) {
      final target = await _scrollToQueryFeature(tester, feature);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.byTooltip('返回'), findsOneWidget);
      expect(
        find.widgetWithText(
          AppBar,
          feature == FeatureId.schedule ? '第3周' : feature.title,
        ),
        findsOneWidget,
      );
      await _returnToFeatureRoot(tester);
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      UbaaFlutterApp(
        key: const ValueKey<String>('advanced-smoke-replacement'),
        backend: _IntegrationBackend(),
        credentialVault: MemoryCredentialVault(),
        initialDestination: UiDestination.campus,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '2020000003');
    await tester.enterText(find.byType(TextField).at(1), 'fixture-password');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    expect(find.byType(UbaaMainShell), findsOneWidget);
    for (final feature in advancedFeatureIds) {
      final target = await _scrollToQueryFeature(tester, feature);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.byTooltip('返回'), findsOneWidget);
      expect(
        find.widgetWithText(
          AppBar,
          feature == FeatureId.schedule ? '第3周' : feature.title,
        ),
        findsOneWidget,
      );
      await _returnToFeatureRoot(tester);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('宿主集成流程的状态筛选点选即发出对应查询', (tester) async {
    final backend = _IntegrationBackend();
    await tester.pumpWidget(
      UbaaFlutterApp(
        key: const ValueKey<String>('query-matrix'),
        backend: backend,
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '2020000005');
    await tester.enterText(find.byType(TextField).at(1), 'fixture-password');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.byType(UbaaMainShell), findsOneWidget);

    // 视图切换由菜单、卡片和预约流程承担；筛选只含用户可理解的状态条件。
    final cases = <(FeatureId, String, FeatureQueryView)>[
      (FeatureId.exam, '已安排', FeatureQueryView.examArranged),
      (FeatureId.grades, '已出成绩', FeatureQueryView.gradesScored),
      (FeatureId.signin, '可签到', FeatureQueryView.signinPending),
      (FeatureId.evaluation, '待评课程', FeatureQueryView.evaluationPending),
    ];
    for (final (feature, option, expectedView) in cases) {
      await _openIntegrationFeature(tester, feature, enterLanding: false);
      await _openIntegrationPanel(tester);
      for (final text in ['应用筛选', '学期编码', '课程 ID', '站点 ID']) {
        expect(find.text(text), findsNothing, reason: '筛选面板不应包含“$text”');
      }
      final before = backend.queries.length;
      final chip = find.widgetWithText(ChoiceChip, option);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      final targeted = backend.queries
          .skip(before)
          .where((entry) => entry.$1 == feature)
          .toList();
      expect(
        targeted,
        isNotEmpty,
        reason: '${feature.name} 点选“$option”后必须发出新查询',
      );
      expect(targeted.last.$2.view, expectedView);
      await _closeIntegrationPanel(tester);
      await _returnToFeatureRoot(tester);
      await tester.pumpAndSettle();
    }
  });
}

/// 先实际滚动构建懒加载卡片，再定位点击；不能对尚未构建的 Finder 取 first。
Future<Finder> _scrollToQueryFeature(
  WidgetTester tester,
  FeatureId feature,
) async {
  final grid = find.byType(CustomScrollView);
  expect(grid, findsOneWidget);
  final scrollable = find.descendant(
    of: grid,
    matching: find.byType(Scrollable),
  );
  expect(scrollable, findsOneWidget);
  final features = UiDestination.forFeature(feature).features;
  // 合成摘要可能与标题同名；定位共同的唯一 Card，不对 Text 任取 first。
  Finder featureCard(FeatureId id) =>
      find.descendant(of: grid, matching: find.widgetWithText(Card, id.title));
  // 返回或切换分组后可能保留滚动位置，先滚回组首，再寻找目标。
  await tester.scrollUntilVisible(
    featureCard(features.first),
    -240,
    scrollable: scrollable,
  );
  final target = featureCard(feature);
  await tester.scrollUntilVisible(target, 240, scrollable: scrollable);
  await tester.pumpAndSettle();
  expect(target, findsOneWidget);
  expect(target.hitTestable(), findsOneWidget);
  return target;
}
