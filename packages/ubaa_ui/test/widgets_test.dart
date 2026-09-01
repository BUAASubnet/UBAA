import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('启动页展示品牌且登录页不猜测验证码流程', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: UbaaTheme.light(), home: const UbaaSplashView()),
    );

    expect(find.text('UBAA'), findsOneWidget);
    expect(find.text('Make BUAA Great Again'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaLoginView(
          username: '',
          password: '',
          captcha: '',
          rememberPassword: false,
          autoLogin: false,
          routePolicy: RoutePolicy.auto,
          error: null,
          isLoading: false,
          credentialPersistenceAvailable: false,
          onUsernameChanged: (_) {},
          onPasswordChanged: (_) {},
          onCaptchaChanged: (_) {},
          onRememberPasswordChanged: (_) {},
          onAutoLoginChanged: (_) {},
          onRoutePolicyChanged: (_) {},
          onSubmit: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('UBAA 登录'), findsOneWidget);
    expect(find.text('验证码'), findsNothing);
    expect(find.textContaining('安全存储'), findsOneWidget);
  });

  testWidgets('功能卡片打开真实详情字段而不是占位页', (tester) async {
    var clearedAccount = false;
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          resolvedRoute: feature == FeatureId.schedule
              ? ConnectionMode.direct
              : null,
          details: feature == FeatureId.schedule
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '高等数学',
                    subtitle: '周一 08:00',
                    fields: <FeatureField>[
                      FeatureField(label: '地点', value: '主楼 101'),
                    ],
                  ),
                ]
              : const <FeatureDetail>[],
        ),
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          activeRoutes: const <ConnectionMode>[ConnectionMode.direct],
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onLogout: () async {},
          onLogoutAndClearAccount: () async => clearedAccount = true,
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('课表查询'));
    await tester.pumpAndSettle();
    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('主楼 101'), findsOneWidget);
    expect(find.text('实际路线：直连'), findsOneWidget);
    expect(find.textContaining('只读详情页面将在'), findsNothing);

    await tester.tap(find.text('返回功能列表'));
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.text('直连'), findsOneWidget);
    await tester.tap(find.text('退出并清除本机账号'));
    await tester.pumpAndSettle();
    expect(find.text('清除本机账号？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(clearedAccount, isFalse);
    await tester.tap(find.text('退出并清除本机账号'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出并清除'));
    await tester.pumpAndSettle();
    expect(clearedAccount, isTrue);
  });

  testWidgets('写入确认显示实际路线并防止过期提交', (tester) async {
    final intent = WriteIntent(
      intentId: 'intent',
      operation: WriteOperation.libbookCancelBooking,
      targetSummary: '取消一条图书馆预约',
      resolvedRoute: ConnectionMode.webvpn,
      warnings: const <String>['取消操作可能不可恢复'],
      expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      requestDigest: 'digest',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: WriteConfirmationView(
          intent: intent,
          onCancel: () {},
          onConfirm: () async {},
        ),
      ),
    );
    expect(find.text('WebVPN'), findsOneWidget);
    expect(find.text('意图已过期'), findsOneWidget);
    final submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '意图已过期'),
    );
    expect(submit.onPressed, isNull);
  });

  testWidgets('长详情列表分页且筛选会回到第一页', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.schedule
              ? List<FeatureDetail>.generate(
                  21,
                  (index) => FeatureDetail(title: '课程 ${index + 1}'),
                )
              : const <FeatureDetail>[],
        ),
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
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
    await tester.tap(find.text('课表查询'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('课程 21'), findsNothing);
    await tester.tap(find.byTooltip('下一页'));
    await tester.pumpAndSettle();
    expect(find.text('课程 21'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '课程 1');
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsNothing);
    expect(find.text('课程 1'), findsNWidgets(2));
  });

  testWidgets('领域查询控件提交日期和校区 typed 参数', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.classroom
              ? const <FeatureDetail>[FeatureDetail(title: '主楼 101')]
              : const <FeatureDetail>[],
        ),
    };
    FeatureQuery? received;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFeatureQuery: (feature, query) async {
            expect(feature, FeatureId.classroom);
            received = query;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('空教室查询'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '2026-09-02');
    await tester.tap(find.text('校区 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('校区 2'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('应用筛选'));
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.date, DateTime(2026, 9, 2));
    expect(received?.campus, 2);
  });

  testWidgets('空教室查询控件提交楼层和节次本地筛选参数', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.classroom
              ? const <FeatureDetail>[FeatureDetail(title: '主楼 101')]
              : const <FeatureDetail>[],
        ),
    };
    FeatureQuery? received;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFeatureQuery: (feature, query) async {
            expect(feature, FeatureId.classroom);
            received = query;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('空教室查询'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), 'F2');
    await tester.enterText(fields.at(2), '3');
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.floorId, 'F2');
    expect(received?.section, '3');
  });

  testWidgets('考试查询控件提交已安排本地派生视图', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.exam
              ? const <FeatureDetail>[FeatureDetail(title: '考试')]
              : const <FeatureDetail>[],
        ),
    };
    FeatureQuery? received;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFeatureQuery: (feature, query) async {
            expect(feature, FeatureId.exam);
            received = query;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('考试查询'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部考试'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已安排'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.examArranged);
  });

  testWidgets('成绩查询控件提交已出成绩本地派生视图', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.grades
              ? const <FeatureDetail>[FeatureDetail(title: '成绩')]
              : const <FeatureDetail>[],
        ),
    };
    FeatureQuery? received;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFeatureQuery: (feature, query) async {
            expect(feature, FeatureId.grades);
            received = query;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('成绩查询'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部成绩'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已出成绩'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.gradesScored);
  });

  testWidgets('博雅查询控件提交课程详情 typed 参数', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.bykc
              ? const <FeatureDetail>[FeatureDetail(title: '课程')]
              : const <FeatureDetail>[],
        ),
    };
    FeatureQuery? received;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFeatureQuery: (feature, query) async {
            expect(feature, FeatureId.bykc);
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
      find.text('博雅课程'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('博雅课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课程列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课程详情'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '12345');
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.bykcDetail);
    expect(received?.courseId, '12345');
  });

  testWidgets('博雅查询控件提交修读统计视图', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.bykc
              ? const <FeatureDetail>[FeatureDetail(title: '课程')]
              : const <FeatureDetail>[],
        ),
    };
    FeatureQuery? received;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFeatureQuery: (feature, query) async {
            expect(feature, FeatureId.bykc);
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
      find.text('博雅课程'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('博雅课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课程列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('修读统计'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.bykcStatistics);
  });

  testWidgets('课表查询控件提交学期和周次 typed 参数', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.schedule
              ? const <FeatureDetail>[FeatureDetail(title: '高等数学')]
              : const <FeatureDetail>[],
        ),
    };
    FeatureQuery? received;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFeatureQuery: (feature, query) async {
            expect(feature, FeatureId.schedule);
            received = query;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('课表查询'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '2026-2027-1');
    await tester.enterText(fields.at(1), '3');
    await tester.ensureVisible(find.text('应用筛选'));
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.term, '2026-2027-1');
    expect(received?.week, 3);
  });

  testWidgets('课表查询控件提交学期列表视图', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.schedule
              ? const <FeatureDetail>[FeatureDetail(title: '课表')]
              : const <FeatureDetail>[],
        ),
    };
    FeatureQuery? received;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFeatureQuery: (feature, query) async {
            expect(feature, FeatureId.schedule);
            received = query;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('课表查询'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今日课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('学期列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.scheduleTerms);
  });

  testWidgets('博雅查询控件提交 1-based 分页参数', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.bykc
              ? const <FeatureDetail>[FeatureDetail(title: '课程')]
              : const <FeatureDetail>[],
        ),
    };
    FeatureQuery? received;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFeatureQuery: (feature, query) async {
            expect(feature, FeatureId.bykc);
            received = query;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('博雅课程'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '2');
    await tester.enterText(fields.at(1), '50');
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.page, 2);
    expect(received?.size, 50);
  });

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
        home: UbaaMainShell(
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

  testWidgets('阳光打卡查询控件提交记录分页 typed 参数', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.ygdk
              ? const <FeatureDetail>[FeatureDetail(title: '打卡概览')]
              : const <FeatureDetail>[],
        ),
    };
    FeatureQuery? received;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFeatureQuery: (feature, query) async {
            expect(feature, FeatureId.ygdk);
            received = query;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('阳光打卡'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('概览'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('记录列表'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, '3');
    await tester.enterText(fields.at(1), '15');
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.ygdkRecords);
    expect(received?.page, 3);
    expect(received?.size, 15);
  });

  testWidgets('场馆查询控件提交日期空间 typed 参数', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.cgyy
              ? const <FeatureDetail>[FeatureDetail(title: '场馆')]
              : const <FeatureDetail>[],
        ),
    };
    FeatureQuery? received;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFeatureQuery: (feature, query) async {
            expect(feature, FeatureId.cgyy);
            received = query;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('场馆预约'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('场馆预约'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('站点列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日期空间'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, '17');
    await tester.enterText(fields.at(1), '2026-09-03');
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.cgyyDayInfo);
    expect(received?.siteId, 17);
    expect(received?.date, DateTime(2026, 9, 3));
  });

  testWidgets('评教查询控件提交待评本地派生视图', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.evaluation
              ? const <FeatureDetail>[FeatureDetail(title: '评教')]
              : const <FeatureDetail>[],
        ),
    };
    FeatureQuery? received;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFeatureQuery: (feature, query) async {
            expect(feature, FeatureId.evaluation);
            received = query;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('教学评教'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('教学评教'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('待评课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.evaluationPending);
  });

  testWidgets('SPOC 查询控件提交作业详情 typed 参数', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.spoc
              ? const <FeatureDetail>[FeatureDetail(title: '作业')]
              : const <FeatureDetail>[],
        ),
    };
    FeatureQuery? received;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFeatureQuery: (feature, query) async {
            expect(feature, FeatureId.spoc);
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
      find.text('SPOC作业'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('SPOC作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('作业列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('作业详情'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'assignment-17');
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.spocDetail);
    expect(received?.assignmentId, 'assignment-17');
  });

  testWidgets('希冀查询控件提交作业详情 typed 参数', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.judge
              ? const <FeatureDetail>[FeatureDetail(title: '作业')]
              : const <FeatureDetail>[],
        ),
    };
    FeatureQuery? received;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFeatureQuery: (feature, query) async {
            expect(feature, FeatureId.judge);
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
      find.text('希冀作业'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('希冀作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('作业列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('作业详情'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'course-3');
    await tester.enterText(fields.at(1), 'assignment-17');
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.judgeDetail);
    expect(received?.courseId, 'course-3');
    expect(received?.assignmentId, 'assignment-17');
    expect(received?.includeExpired, isFalse);
  });

  testWidgets('希冀查询控件可包含已过期作业', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.judge
              ? const <FeatureDetail>[FeatureDetail(title: '作业')]
              : const <FeatureDetail>[],
        ),
    };
    FeatureQuery? received;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFeatureQuery: (feature, query) async {
            expect(feature, FeatureId.judge);
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
      find.text('希冀作业'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('希冀作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('包含已过期作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.includeExpired, isTrue);
  });

  testWidgets('希冀查询控件提交批量作业详情 typed 键', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.judge
              ? const <FeatureDetail>[FeatureDetail(title: '作业')]
              : const <FeatureDetail>[],
        ),
    };
    FeatureQuery? received;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFeatureQuery: (feature, query) async {
            expect(feature, FeatureId.judge);
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
      find.text('希冀作业'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('希冀作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('作业列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('批量详情'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'course-2/assignment-2\ncourse-1/assignment-1',
    );
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.judgeBatchDetails);
    expect(received?.judgeKeys, const <JudgeAssignmentQueryKey>[
      JudgeAssignmentQueryKey(
        courseId: 'course-2',
        assignmentId: 'assignment-2',
      ),
      JudgeAssignmentQueryKey(
        courseId: 'course-1',
        assignmentId: 'assignment-1',
      ),
    ]);
  });
}
