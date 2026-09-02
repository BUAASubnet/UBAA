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

  testWidgets('宿主集成流程覆盖十项写操作并验证签到签退分支', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backend = _AllWritesIntegrationBackend();
    final permissionGateway = MemoryPermissionGateway(
      initial: <PlatformPermission, PlatformPermissionStatus>{
        PlatformPermission.photos: PlatformPermissionStatus.granted,
      },
    );
    await tester.pumpWidget(
      UbaaFlutterApp(
        key: const ValueKey<String>('all-writes-smoke'),
        backend: backend,
        credentialVault: MemoryCredentialVault(),
        photoPicker: MemoryPhotoPicker(
          photo: const YgdkPhotoInput(
            bytes: <int>[1, 2, 3],
            fileName: 'integration.jpg',
            mimeType: 'image/jpeg',
          ),
        ),
        permissionGateway: permissionGateway,
        initialTab: 1,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '2020000099');
    await tester.enterText(find.byType(TextField).at(1), 'fixture-password');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(UbaaMainShell), findsOneWidget);

    Future<void> openFeature(FeatureId feature) async {
      final selectedIcon = ordinaryFeatureIds.contains(feature)
          ? Icons.apps
          : Icons.auto_awesome;
      final unselectedIcon = ordinaryFeatureIds.contains(feature)
          ? Icons.apps_outlined
          : Icons.auto_awesome_outlined;
      final tab = find.byIcon(selectedIcon).evaluate().isNotEmpty
          ? find.byIcon(selectedIcon)
          : find.byIcon(unselectedIcon);
      await tester.tap(tab.first);
      await tester.pumpAndSettle();
      final target = find.text(feature.title).first;
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.text('返回功能列表'), findsOneWidget);
    }

    Future<void> leaveFeature() async {
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
    }

    Future<void> confirm(
      String label,
      WriteOperation operation,
      FeatureId readbackFeature,
    ) async {
      await tester.ensureVisible(find.text(label).first);
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      expect(find.text('确认${operation.title}'), findsAtLeastNWidgets(1));
      final before = backend.commitCalls;
      final beforeReadback = backend.featureLoads[readbackFeature] ?? 0;
      await tester.tap(find.widgetWithText(FilledButton, '确认提交'));
      await tester.pumpAndSettle();
      expect(backend.commitCalls, before + 1);
      expect(backend.committedOperations.last, operation);
      expect(
        backend.featureLoads[readbackFeature],
        greaterThan(beforeReadback),
        reason: '${operation.title}提交后必须刷新${readbackFeature.title}核对',
      );
    }

    await openFeature(FeatureId.bykc);
    await confirm(
      '准备选课',
      WriteOperation.bykcSelectCourse,
      FeatureId.bykc,
    );
    await leaveFeature();
    await openFeature(FeatureId.bykc);
    await confirm(
      '准备退选',
      WriteOperation.bykcDeselectCourse,
      FeatureId.bykc,
    );
    await leaveFeature();
    await openFeature(FeatureId.bykc);
    await confirm(
      '准备博雅签到',
      WriteOperation.bykcSignCourse,
      FeatureId.bykc,
    );
    await leaveFeature();
    await openFeature(FeatureId.bykc);
    await confirm(
      '准备博雅签退',
      WriteOperation.bykcSignCourse,
      FeatureId.bykc,
    );
    await leaveFeature();

    await openFeature(FeatureId.signin);
    await confirm(
      '准备签到',
      WriteOperation.signinPerform,
      FeatureId.signin,
    );
    await leaveFeature();

    await openFeature(FeatureId.libbook);
    await confirm(
      '准备预约此座位',
      WriteOperation.libbookReserve,
      FeatureId.libbook,
    );
    await leaveFeature();
    await openFeature(FeatureId.libbook);
    await confirm(
      '准备取消预约',
      WriteOperation.libbookCancelBooking,
      FeatureId.libbook,
    );
    await leaveFeature();

    await openFeature(FeatureId.cgyy);
    await confirm(
      '准备取消订单',
      WriteOperation.cgyyCancelOrder,
      FeatureId.cgyy,
    );
    await leaveFeature();
    await openFeature(FeatureId.cgyy);
    expect(find.text('准备场馆预约'), findsOneWidget);
    await tester.tap(find.text('准备场馆预约').first);
    await tester.pumpAndSettle();
    expect(find.text('填写场馆预约信息'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, '联系电话'),
      '010-00000000',
    );
    await tester.enterText(find.widgetWithText(TextField, '预约主题'), '集成测试');
    await tester.enterText(find.widgetWithText(TextField, '用途编号'), '2');
    await tester.enterText(find.widgetWithText(TextField, '参与人数'), '2');
    await tester.enterText(find.widgetWithText(TextField, '活动内容'), '脱敏集成验证');
    await tester.tap(find.text('继续确认'));
    await tester.pumpAndSettle();
    expect(find.text('填写场馆预约信息'), findsNothing);
    expect(find.text('确认场馆预约'), findsAtLeastNWidgets(1));
    final beforeCgyy = backend.commitCalls;
    final beforeCgyyReadback = backend.featureLoads[FeatureId.cgyy] ?? 0;
    await tester.tap(find.widgetWithText(FilledButton, '确认提交'));
    await tester.pumpAndSettle();
    expect(backend.commitCalls, beforeCgyy + 1);
    expect(
      backend.committedOperations.last,
      WriteOperation.cgyySubmitReservation,
    );
    expect(
      backend.featureLoads[FeatureId.cgyy],
      greaterThan(beforeCgyyReadback),
      reason: '场馆预约提交后必须刷新场馆订单核对',
    );
    await leaveFeature();

    await openFeature(FeatureId.ygdk);
    await tester.tap(find.text('准备阳光打卡').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '开始时间'),
      '2026-09-02 08:00',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '结束时间'),
      '2026-09-02 09:00',
    );
    await tester.tap(find.text('选择照片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续确认'));
    await tester.pumpAndSettle();
    expect(find.text('确认阳光打卡'), findsAtLeastNWidgets(1));
    final beforeYgdk = backend.commitCalls;
    final beforeYgdkReadback = backend.featureLoads[FeatureId.ygdk] ?? 0;
    await tester.tap(find.widgetWithText(FilledButton, '确认提交'));
    await tester.pumpAndSettle();
    expect(backend.commitCalls, beforeYgdk + 1);
    expect(backend.committedOperations.last, WriteOperation.ygdkSubmit);
    expect(
      backend.featureLoads[FeatureId.ygdk],
      greaterThan(beforeYgdkReadback),
      reason: '阳光打卡提交后必须刷新打卡记录核对',
    );
    await leaveFeature();

    await openFeature(FeatureId.evaluation);
    await confirm(
      '准备提交评教',
      WriteOperation.evaluationSubmitCourses,
      FeatureId.evaluation,
    );

    expect(backend.committedOperations, <WriteOperation>[
      WriteOperation.bykcSelectCourse,
      WriteOperation.bykcDeselectCourse,
      WriteOperation.bykcSignCourse,
      WriteOperation.bykcSignCourse,
      WriteOperation.signinPerform,
      WriteOperation.libbookReserve,
      WriteOperation.libbookCancelBooking,
      WriteOperation.cgyyCancelOrder,
      WriteOperation.cgyySubmitReservation,
      WriteOperation.ygdkSubmit,
      WriteOperation.evaluationSubmitCourses,
    ]);
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

/// 覆盖全部写入口的脱敏宿主后端；只记录操作枚举，不保存请求正文。
final class _AllWritesIntegrationBackend
    implements
        UbaaBackend,
        FeatureQueryBackend,
        RouteSettingsBackend,
        BykcWriteBackend,
        SigninWriteBackend,
        CancellationWriteBackend,
        LibbookWriteBackend,
        YgdkWriteBackend,
        CgyyWriteBackend,
        EvaluationWriteBackend {
  bool _signedIn = false;
  bool _bykcSelected = false;
  int _nextIntent = 0;
  final Map<String, WriteOperation> _pending = <String, WriteOperation>{};
  final List<WriteOperation> committedOperations = <WriteOperation>[];
  final Map<FeatureId, int> featureLoads = <FeatureId, int>{};
  int commitCalls = 0;

  @override
  Future<AuthStatus> authStatus() async =>
      _signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;

  @override
  Future<UserSummary?> userInfo() async =>
      _signedIn ? const UserSummary(username: '2020000099') : null;

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {
    _signedIn = true;
  }

  @override
  Future<void> logout() async {
    _signedIn = false;
    _pending.clear();
  }

  @override
  Future<BackendRouteSettings> routeSettings() async => BackendRouteSettings(
    defaultPolicy: RoutePolicy.auto,
    activeRoutes: _signedIn
        ? const <ConnectionMode>[ConnectionMode.direct]
        : const <ConnectionMode>[],
  );

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    if (!_signedIn) {
      throw const BackendException(UbaaErrorCode.authenticationRequired);
    }
    featureLoads.update(
      feature,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    final details = switch (feature) {
      FeatureId.bykc => <FeatureDetail>[
        FeatureDetail(
          title: '集成课程',
          fields: <FeatureField>[
            const FeatureField(label: '课程 ID', value: '42'),
            FeatureField(label: '已选', value: _bykcSelected ? '是' : '否'),
            FeatureField(label: '状态', value: _bykcSelected ? '已选' : '可选'),
            const FeatureField(label: '可签到', value: '是'),
            const FeatureField(label: '可签退', value: '是'),
          ],
        ),
      ],
      FeatureId.signin => const <FeatureDetail>[
        FeatureDetail(
          title: '课堂集成课程',
          fields: <FeatureField>[
            FeatureField(label: '课程 ID', value: 'signin-course'),
            FeatureField(label: '签到状态', value: '未签到'),
          ],
        ),
      ],
      FeatureId.libbook => const <FeatureDetail>[
        FeatureDetail(
          title: '集成座位',
          fields: <FeatureField>[
            FeatureField(label: '分区 ID', value: 'area-1'),
            FeatureField(label: '座位 ID', value: 'seat-1'),
            FeatureField(label: '日期', value: '2026-09-02'),
            FeatureField(label: '时段', value: '3'),
            FeatureField(label: '开始时间', value: '10:00'),
            FeatureField(label: '结束时间', value: '12:00'),
            FeatureField(label: '可预约', value: '是'),
            FeatureField(label: '预约 ID', value: 'booking-1'),
            FeatureField(label: '状态码', value: '1'),
            FeatureField(label: '状态', value: '有效'),
          ],
        ),
      ],
      FeatureId.cgyy => const <FeatureDetail>[
        FeatureDetail(
          title: '集成场馆时段',
          fields: <FeatureField>[
            FeatureField(label: '站点 ID', value: '3'),
            FeatureField(label: '日期', value: '2026-09-03'),
            FeatureField(label: '空间 ID', value: '4'),
            FeatureField(label: '空间组 ID', value: '9'),
            FeatureField(label: '时段 ID', value: '5'),
            FeatureField(label: '可预约', value: '是'),
          ],
        ),
        FeatureDetail(
          title: '集成场馆订单',
          fields: <FeatureField>[
            FeatureField(label: '订单编号', value: '17'),
            FeatureField(label: '订单状态', value: '1'),
            FeatureField(label: '审核状态', value: '1'),
            FeatureField(label: '开始', value: '2099-01-01 10:00:00'),
            FeatureField(label: '结束', value: '2099-01-01 11:00:00'),
          ],
        ),
      ],
      FeatureId.ygdk => const <FeatureDetail>[
        FeatureDetail(
          title: '集成跑步项目',
          fields: <FeatureField>[FeatureField(label: '项目编号', value: '7')],
        ),
      ],
      FeatureId.evaluation => const <FeatureDetail>[
        FeatureDetail(
          title: '集成评教课程',
          fields: <FeatureField>[
            FeatureField(label: '状态', value: '待评'),
            FeatureField(label: '课程 ID', value: 'course-evaluation'),
            FeatureField(label: '任务 ID', value: 'task-evaluation'),
            FeatureField(label: '问卷 ID', value: 'questionnaire-evaluation'),
            FeatureField(label: '课程代码', value: 'K-EVAL'),
            FeatureField(label: '模型 ID', value: 'M-EVAL'),
          ],
        ),
      ],
      _ => <FeatureDetail>[FeatureDetail(title: feature.title)],
    };
    return FeatureResult.success(
      summary: feature.title,
      details: details,
      resolvedRoute: ConnectionMode.direct,
    );
  }

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) => loadFeature(feature);

  @override
  Future<WriteIntent> prepareBykcSelectCourse({required int courseId}) =>
      _prepare(WriteOperation.bykcSelectCourse);

  @override
  Future<WriteIntent> prepareBykcDeselectCourse({required int courseId}) =>
      _prepare(WriteOperation.bykcDeselectCourse);

  @override
  Future<WriteIntent> prepareBykcSignCourse({
    required int courseId,
    double? lat,
    double? lng,
    required int signType,
  }) => _prepare(WriteOperation.bykcSignCourse);

  @override
  Future<WriteIntent> prepareSigninPerform({required String courseId}) =>
      _prepare(WriteOperation.signinPerform);

  @override
  Future<WriteIntent> prepareLibbookCancelBooking({required String id}) =>
      _prepare(WriteOperation.libbookCancelBooking);

  @override
  Future<WriteIntent> prepareCgyyCancelOrder({required int id}) =>
      _prepare(WriteOperation.cgyyCancelOrder);

  @override
  Future<WriteIntent> prepareLibbookReserve({
    required String areaId,
    required String seatId,
    required String day,
    required String segment,
    required String startTime,
    required String endTime,
  }) => _prepare(WriteOperation.libbookReserve);

  @override
  Future<WriteIntent> prepareYgdkSubmit(YgdkSubmitInput input) =>
      _prepare(WriteOperation.ygdkSubmit);

  @override
  Future<WriteIntent> prepareCgyySubmitReservation(CgyySubmitInput input) =>
      _prepare(WriteOperation.cgyySubmitReservation);

  @override
  Future<WriteIntent> prepareEvaluationSubmitCourses(
    List<EvaluationCourseInput> courses,
  ) => _prepare(WriteOperation.evaluationSubmitCourses);

  Future<WriteIntent> _prepare(WriteOperation operation) {
    final intentId = 'all-writes-${_nextIntent++}';
    _pending[intentId] = operation;
    return Future<WriteIntent>.value(
      WriteIntent(
        intentId: intentId,
        operation: operation,
        targetSummary: '脱敏集成测试目标',
        resolvedRoute: ConnectionMode.direct,
        warnings: const <String>['集成测试不访问真实账号'],
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        requestDigest: 'all-writes-digest',
      ),
    );
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    final operation = _pending.remove(intentId);
    if (operation == null) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    commitCalls++;
    committedOperations.add(operation);
    if (operation == WriteOperation.bykcSelectCourse) _bykcSelected = true;
    if (operation == WriteOperation.bykcDeselectCourse) _bykcSelected = false;
    return WriteCommitResult(
      operation: operation,
      success: true,
      message: '${operation.title}结果已提交，请刷新确认',
      outcomeUnknown: false,
      resolvedRoute: ConnectionMode.direct,
    );
  }
}
