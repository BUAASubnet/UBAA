import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_flutter/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('宿主集成流程从登录进入详情并传递 typed 查询', (tester) async {
    final backend = _IntegrationBackend();
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('UBAA 登录'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '2020000000');
    await tester.enterText(find.byType(TextField).at(1), 'fixture-password');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    expect(find.byType(UbaaMainShell), findsOneWidget);

    expect(find.text('课表查询'), findsOneWidget);
    await tester.tap(find.text('课表查询'));
    await tester.pumpAndSettle();
    expect(find.text('集成测试课程'), findsOneWidget);

    final queryMenu = find.byType(DropdownButton<FeatureQueryView>);
    expect(queryMenu, findsOneWidget);
    await tester.tap(queryMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('周课表').last);
    await tester.pumpAndSettle();

    final termField = find.widgetWithText(TextField, '学期编码（可选）');
    final weekField = find.widgetWithText(TextField, '周次（可选）');
    expect(termField, findsOneWidget);
    expect(weekField, findsOneWidget);
    await tester.enterText(termField, '2026-2027-1');
    await tester.enterText(weekField, '3');
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();

    expect(backend.lastQuery?.view, FeatureQueryView.scheduleWeek);
    expect(backend.lastQuery?.term, '2026-2027-1');
    expect(backend.lastQuery?.week, 3);
    expect(find.text('查询后的课程'), findsOneWidget);

    await tester.tap(find.text('返回功能列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.text('直连'), findsOneWidget);
  });

  testWidgets('宿主集成流程写入只提交一次并刷新签到状态', (tester) async {
    final backend = _WriteIntegrationBackend();
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '2020000001');
    await tester.enterText(find.byType(TextField).at(1), 'fixture-password');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课堂签到'));
    await tester.pumpAndSettle();
    expect(find.text('未签到'), findsOneWidget);

    await tester.tap(find.text('准备签到'));
    await tester.pumpAndSettle();
    expect(find.text('确认课堂签到'), findsNWidgets(2));
    expect(backend.commitCalls, 0);

    final confirm = find.widgetWithText(FilledButton, '确认提交');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(backend.commitCalls, 1);
    expect(backend.preparedCourse, 'course-integration');
    expect(backend.signinLoads, greaterThanOrEqualTo(2));
    expect(find.text('签到结果已提交，请刷新确认'), findsOneWidget);
    expect(find.text('已签到'), findsOneWidget);
  });

  testWidgets('宿主集成流程提交异常时不刷新也不暴露业务上下文', (tester) async {
    final backend = _WriteIntegrationBackend(throwOnCommit: true);
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '2020000004');
    await tester.enterText(find.byType(TextField).at(1), 'fixture-password');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课堂签到'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('准备签到'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();

    expect(backend.commitCalls, 1);
    expect(backend.signinLoads, 1);
    expect(find.text('提交结果不确定，请先刷新相关状态，不要重复提交。'), findsOneWidget);
    expect(find.text('相关课程状态'), findsNothing);
    expect(find.text('已签到'), findsNothing);
  });

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

/// 仅供宿主集成测试使用的脱敏 typed backend；不访问网络或真实账号。
final class _IntegrationBackend
    implements UbaaBackend, FeatureQueryBackend, RouteSettingsBackend {
  bool _signedIn = false;
  bool get signedIn => _signedIn;
  FeatureQuery? lastQuery;

  @override
  Future<AuthStatus> authStatus() async =>
      _signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;

  @override
  Future<UserSummary?> userInfo() async =>
      _signedIn ? const UserSummary(username: '2020000000') : null;

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {
    _signedIn = true;
  }

  @override
  Future<void> logout() async {
    _signedIn = false;
  }

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    if (!_signedIn) {
      throw const BackendException(UbaaErrorCode.authenticationRequired);
    }
    if (feature == FeatureId.schedule) {
      return const FeatureResult.success(
        summary: '今日课程',
        details: <FeatureDetail>[
          FeatureDetail(
            title: '集成测试课程',
            fields: <FeatureField>[
              FeatureField(label: '时间', value: '周一 08:00'),
            ],
          ),
        ],
        resolvedRoute: ConnectionMode.direct,
      );
    }
    final fields = switch (feature) {
      FeatureId.bykc => const <FeatureField>[
        FeatureField(label: '课程 ID', value: '42'),
      ],
      FeatureId.spoc => const <FeatureField>[
        FeatureField(label: '作业编号', value: 'assignment-1'),
      ],
      FeatureId.judge => const <FeatureField>[
        FeatureField(label: '课程编号', value: 'course-1'),
        FeatureField(label: '作业编号', value: 'assignment-1'),
      ],
      FeatureId.cgyy => const <FeatureField>[
        FeatureField(label: '站点 ID', value: '7'),
      ],
      _ => const <FeatureField>[],
    };
    return FeatureResult.success(
      summary: feature.title,
      details: <FeatureDetail>[
        FeatureDetail(title: feature.title, fields: fields),
      ],
      resolvedRoute: ConnectionMode.direct,
    );
  }

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    lastQuery = query;
    return const FeatureResult.success(
      summary: '指定周课表',
      details: <FeatureDetail>[
        FeatureDetail(
          title: '查询后的课程',
          fields: <FeatureField>[FeatureField(label: '周次', value: '3')],
        ),
      ],
      resolvedRoute: ConnectionMode.direct,
    );
  }

  @override
  Future<BackendRouteSettings> routeSettings() async => BackendRouteSettings(
    defaultPolicy: RoutePolicy.auto,
    activeRoutes: _signedIn
        ? const <ConnectionMode>[ConnectionMode.direct]
        : const <ConnectionMode>[],
  );
}

/// 仅供宿主写入组合测试使用的脱敏 backend；提交后模拟只读状态变化。
final class _WriteIntegrationBackend
    implements
        UbaaBackend,
        FeatureQueryBackend,
        RouteSettingsBackend,
        SigninWriteBackend {
  _WriteIntegrationBackend({this.throwOnCommit = false});

  final bool throwOnCommit;
  bool _signedIn = false;
  bool _completed = false;
  int signinLoads = 0;
  int commitCalls = 0;
  String? preparedCourse;

  @override
  Future<AuthStatus> authStatus() async =>
      _signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;

  @override
  Future<UserSummary?> userInfo() async =>
      _signedIn ? const UserSummary(username: '2020000001') : null;

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {
    _signedIn = true;
  }

  @override
  Future<void> logout() async {
    _signedIn = false;
    _completed = false;
  }

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    if (!_signedIn) {
      throw const BackendException(UbaaErrorCode.authenticationRequired);
    }
    if (feature == FeatureId.signin) {
      signinLoads++;
      return FeatureResult.success(
        summary: _completed ? '今日签到已完成' : '今日有待签到课程',
        details: <FeatureDetail>[
          FeatureDetail(
            title: '宿主集成签到课程',
            fields: <FeatureField>[
              const FeatureField(label: '课程 ID', value: 'course-integration'),
              FeatureField(label: '签到状态', value: _completed ? '已签到' : '未签到'),
            ],
          ),
        ],
        resolvedRoute: ConnectionMode.direct,
      );
    }
    return FeatureResult.success(
      summary: feature.title,
      details: <FeatureDetail>[FeatureDetail(title: feature.title)],
      resolvedRoute: ConnectionMode.direct,
    );
  }

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) => loadFeature(feature);

  @override
  Future<BackendRouteSettings> routeSettings() async => BackendRouteSettings(
    defaultPolicy: RoutePolicy.auto,
    activeRoutes: _signedIn
        ? const <ConnectionMode>[ConnectionMode.direct]
        : const <ConnectionMode>[],
  );

  @override
  Future<WriteIntent> prepareSigninPerform({required String courseId}) async {
    preparedCourse = courseId;
    return WriteIntent(
      intentId: 'signin-integration',
      operation: WriteOperation.signinPerform,
      targetSummary: '宿主集成签到课程',
      resolvedRoute: ConnectionMode.direct,
      warnings: const <String>['提交后请刷新今日签到状态确认结果'],
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      requestDigest: 'integration-digest',
    );
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    commitCalls++;
    if (intentId != 'signin-integration') {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    if (throwOnCommit) {
      throw Exception('测试提交传输失败');
    }
    _completed = true;
    return const WriteCommitResult(
      operation: WriteOperation.signinPerform,
      success: true,
      message: '签到结果已提交，请刷新确认',
      outcomeUnknown: false,
      resolvedRoute: ConnectionMode.direct,
    );
  }
}
