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
}
