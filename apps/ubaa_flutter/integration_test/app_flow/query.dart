part of '../app_flow_test.dart';

Future<void> _openFeature(WidgetTester tester, FeatureId feature) async {
  final ordinary = ordinaryFeatureIds.contains(feature);
  final selected = find.byIcon(ordinary ? Icons.apps : Icons.auto_awesome);
  final tab = selected.evaluate().isNotEmpty
      ? selected
      : find.byIcon(
          ordinary ? Icons.apps_outlined : Icons.auto_awesome_outlined,
        );
  await tester.tap(tab);
  await tester.pumpAndSettle();
  await tester.tap(await _scrollToQueryFeature(tester, feature));
  await tester.pumpAndSettle();
  final landing = find.byKey(ValueKey(('feature-landing', feature)));
  if (landing.evaluate().isNotEmpty) {
    final title = switch (feature) {
      FeatureId.bykc => '选择课程',
      FeatureId.libbook => '预约座位',
      FeatureId.cgyy => '预约研讨室',
      _ => throw StateError('意外子菜单'),
    };
    await tester.tap(
      find.descendant(of: landing, matching: find.widgetWithText(Card, title)),
    );
    await tester.pumpAndSettle();
  }
  expect(find.byTooltip('返回'), findsOneWidget);
}

Future<void> _leaveFeature(WidgetTester tester) async {
  // 详情和子菜单各返回一层，直到重新显示功能分组。
  for (
    var depth = 0;
    depth < 3 && find.byTooltip('返回').evaluate().isNotEmpty;
    depth++
  ) {
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
  }
  expect(find.byTooltip('返回'), findsNothing);
  expect(find.byType(CustomScrollView), findsOneWidget);
}

Future<void> _openQueryPanel(WidgetTester tester) async {
  await tester.tap(find.byTooltip('搜索与筛选'));
  await tester.pumpAndSettle();
  final more = find.widgetWithText(ExpansionTile, '更多查询');
  if (more.evaluate().isNotEmpty) {
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();
  }
}

Future<void> _closeQueryPanel(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(TextButton, '完成'));
  await tester.pumpAndSettle();
}

void _registerQueryFlowTests() {
  testWidgets('宿主集成流程可打开全部十二项功能详情', (tester) async {
    await tester.pumpWidget(
      UbaaFlutterApp(
        key: const ValueKey<String>('advanced-smoke'),
        backend: _IntegrationBackend(),
        credentialVault: MemoryCredentialVault(),
        initialTab: 1,
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
        find.text(feature == FeatureId.schedule ? '第3周' : feature.title),
        findsAtLeastNWidgets(1),
      );
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      UbaaFlutterApp(
        key: const ValueKey<String>('advanced-smoke-replacement'),
        backend: _IntegrationBackend(),
        credentialVault: MemoryCredentialVault(),
        initialTab: 2,
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
      expect(find.text(feature.title), findsAtLeastNWidgets(1));
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('宿主集成流程覆盖全部领域的 typed 查询入口', (tester) async {
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

    Future<void> openFeature(FeatureId feature) async {
      await _openFeature(tester, feature);
      await _openQueryPanel(tester);
    }

    Future<void> chooseView(String label) async {
      final menu = find.byType(DropdownButton<FeatureQueryView>);
      expect(menu, findsOneWidget);
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(find.text(label), findsWidgets, reason: '查询选项 $label 必须可见');
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    Future<void> apply() async {
      await tester.tap(find.text('应用筛选'));
      await tester.pumpAndSettle();
      expect(backend.lastQuery, isNotNull);
      await _closeQueryPanel(tester);
    }

    await openFeature(FeatureId.schedule);
    await chooseView('周课表');
    await tester.enterText(
      find.widgetWithText(TextField, '学期编码'),
      '2026-2027-1',
    );
    await tester.enterText(find.widgetWithText(TextField, '周次'), '3');
    await apply();
    expect(backend.lastQuery?.view, FeatureQueryView.scheduleWeek);
    await _leaveFeature(tester);

    final queryCases =
        <(FeatureId, String, FeatureQueryView, Map<String, String>)>[
          (FeatureId.exam, '已安排', FeatureQueryView.examArranged, const {}),
          (FeatureId.grades, '已出成绩', FeatureQueryView.gradesScored, const {}),
          (
            FeatureId.bykc,
            '课程详情',
            FeatureQueryView.bykcDetail,
            const {'课程 ID': '42'},
          ),
          (FeatureId.classroom, '', FeatureQueryView.summary, const {}),
          (
            FeatureId.spoc,
            '作业详情',
            FeatureQueryView.spocDetail,
            const {'作业编号': 'assignment-1'},
          ),
          (
            FeatureId.judge,
            '作业详情',
            FeatureQueryView.judgeDetail,
            const {'课程编号': 'course-1', '作业编号': 'assignment-1'},
          ),
          (
            FeatureId.libbook,
            '预约记录',
            FeatureQueryView.libbookBookings,
            const {},
          ),
          (FeatureId.signin, '可签到', FeatureQueryView.signinPending, const {}),
          (
            FeatureId.cgyy,
            '日期空间',
            FeatureQueryView.cgyyDayInfo,
            const {'站点 ID': '7'},
          ),
          (FeatureId.ygdk, '记录列表', FeatureQueryView.ygdkRecords, const {}),
          (
            FeatureId.evaluation,
            '待评课程',
            FeatureQueryView.evaluationPending,
            const {},
          ),
        ];
    for (final (feature, option, expectedView, fields) in queryCases) {
      await openFeature(feature);
      if (option.isNotEmpty) await chooseView(option);
      for (final MapEntry(key: label, value: value) in fields.entries) {
        await tester.enterText(find.widgetWithText(TextField, label), value);
      }
      await apply();
      expect(backend.lastQuery?.view, expectedView);
      await _leaveFeature(tester);
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
  final features = ordinaryFeatureIds.contains(feature)
      ? ordinaryFeatureIds
      : advancedFeatureIds;
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
