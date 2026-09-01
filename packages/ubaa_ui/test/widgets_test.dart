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
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
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
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onLogout: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('课表查询'));
    await tester.pumpAndSettle();
    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('主楼 101'), findsOneWidget);
    expect(find.textContaining('只读详情页面将在'), findsNothing);
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
}
