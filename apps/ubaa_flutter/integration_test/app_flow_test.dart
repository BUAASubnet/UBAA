import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
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
    return FeatureResult.success(
      summary: feature.title,
      details: <FeatureDetail>[
        FeatureDetail(title: feature.title),
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
          fields: <FeatureField>[
            FeatureField(label: '周次', value: '3'),
          ],
        ),
      ],
      resolvedRoute: ConnectionMode.direct,
    );
  }

  @override
  Future<BackendRouteSettings> routeSettings() async =>
      BackendRouteSettings(
        defaultPolicy: RoutePolicy.auto,
        activeRoutes: _signedIn
            ? const <ConnectionMode>[ConnectionMode.direct]
            : const <ConnectionMode>[],
      );
}
