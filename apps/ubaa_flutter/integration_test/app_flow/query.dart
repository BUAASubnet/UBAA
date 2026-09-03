part of '../app_flow_test.dart';

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
      final target = find.text(feature.title).first;
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.text('返回功能列表'), findsOneWidget);
      expect(find.text(feature.title), findsAtLeastNWidgets(1));
      await tester.tap(find.text('返回功能列表'));
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
      final target = find.text(feature.title).first;
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.text('返回功能列表'), findsOneWidget);
      expect(find.text(feature.title), findsAtLeastNWidgets(1));
      await tester.tap(find.text('返回功能列表'));
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
      final selectedIcon = ordinaryFeatureIds.contains(feature)
          ? Icons.apps
          : Icons.auto_awesome;
      final unselectedIcon = ordinaryFeatureIds.contains(feature)
          ? Icons.apps_outlined
          : Icons.auto_awesome_outlined;
      final selectedFinder = find.byIcon(selectedIcon);
      final tabFinder = selectedFinder.evaluate().isNotEmpty
          ? selectedFinder
          : find.byIcon(unselectedIcon);
      await tester.tap(tabFinder.first);
      await tester.pumpAndSettle();
      final target = find.text(feature.title).first;
      final viewportHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      for (var attempt = 0; attempt < 8; attempt++) {
        final rect = tester.getRect(target);
        if (rect.top >= 0 && rect.bottom <= viewportHeight) break;
        final delta = rect.bottom > viewportHeight ? -240.0 : 240.0;
        await tester.drag(find.byType(CustomScrollView), Offset(0, delta));
        await tester.pumpAndSettle();
      }
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.text('返回功能列表'), findsOneWidget);
    }

    Future<void> chooseView(String label) async {
      final menu = find.byType(DropdownButton<FeatureQueryView>);
      expect(menu, findsOneWidget);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    Future<void> apply() async {
      await tester.tap(find.text('应用筛选'));
      await tester.pumpAndSettle();
      expect(backend.lastQuery, isNotNull);
    }

    await openFeature(FeatureId.schedule);
    await chooseView('周课表');
    await tester.enterText(
      find.widgetWithText(TextField, '学期编码（可选）'),
      '2026-2027-1',
    );
    await tester.enterText(find.widgetWithText(TextField, '周次（可选）'), '3');
    await apply();
    expect(backend.lastQuery?.view, FeatureQueryView.scheduleWeek);
    await tester.tap(find.text('返回功能列表'));
    await tester.pumpAndSettle();

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
          (FeatureId.signin, '未签到', FeatureQueryView.signinPending, const {}),
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
      await tester.tap(find.text('返回功能列表'));
      await tester.pumpAndSettle();
    }
  });
}
