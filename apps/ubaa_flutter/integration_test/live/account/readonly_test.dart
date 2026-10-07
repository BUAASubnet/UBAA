import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

/// 真实账号资料仅本地显示验证，禁止截图及输出个人字段，不执行退出或学校写入。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('生产会话恢复与侧栏资料设置只读', (tester) async {
    final config = Platform.environment['UBAA_CONFIG_DIR'];
    const route = String.fromEnvironment('UBAA_EXPECTED_ROUTE');
    if (!const bool.fromEnvironment('UBAA_LIVE_READONLY') ||
        config == null ||
        !Directory(config).isAbsolute ||
        !config.contains('UBAA-ui-readonly-e4-') ||
        !{'direct', 'webvpn'}.contains(route)) {
      throw StateError('必须显式提供本批隔离目录与真实只读路线');
    }
    Widget? app;
    await bootstrapUbaaFlutterApp(runApplication: (value) => app = value);
    await tester.pumpWidget(app!);
    for (
      var i = 0;
      i < 360 && find.byType(UbaaMainShell).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.byType(UbaaLoginView).evaluate().isNotEmpty) break;
    }
    if (find.byType(UbaaLoginView).evaluate().isNotEmpty) {
      debugPrint(
        '账号恢复错误=${tester.widget<UbaaLoginView>(find.byType(UbaaLoginView)).error?.code.name}',
      );
    }
    expect(find.byType(UbaaMainShell).evaluate().isNotEmpty, isTrue);
    await tester.pumpAndSettle();
    UbaaMainShell shell() =>
        tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    final user = shell().user;
    expect(user != null && user.username.isNotEmpty, isTrue);
    expect(shell().routePolicy.name == route, isTrue);
    expect(shell().activeRoutes.any((r) => r.name == route), isTrue);
    Future<void> tap(Finder finder) async {
      if (finder.hitTestable().evaluate().isEmpty) {
        await tester.ensureVisible(finder);
      }
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await tap(find.byIcon(Icons.menu));
    await tap(find.text('我的资料'));
    expect(find.widgetWithText(AppBar, '我的资料').evaluate().isNotEmpty, isTrue);
    await tap(find.text('查看账号资料'));
    var contacts = 0;
    for (final pair in [('邮箱', user!.email), ('手机', user.phone)]) {
      final value = pair.$2;
      if (value == null || value.trim().isEmpty) continue;
      contacts++;
      expect(find.text(value).evaluate().isEmpty, isTrue);
      await tap(find.text('显示${pair.$1}'));
      expect(find.text(value).evaluate().isNotEmpty, isTrue);
      await tap(find.text('隐藏${pair.$1}'));
      expect(find.text(value).evaluate().isEmpty, isTrue);
    }
    await tap(find.byTooltip('返回'));
    await tap(find.byIcon(Icons.menu));
    await tap(find.text('设置'));
    expect(find.widgetWithText(AppBar, '设置').evaluate().isNotEmpty, isTrue);
    expect(
      tester
              .widget<DropdownButton<RoutePolicy>>(
                find.byType(DropdownButton<RoutePolicy>),
              )
              .value
              ?.name ==
          route,
      isTrue,
    );
    expect(find.text('已认证路线').evaluate().isNotEmpty, isTrue);
    await tap(find.byTooltip('返回'));
    await tap(find.byIcon(Icons.menu));
    await tap(find.text('我的资料'));
    expect(find.text('查看账号资料').evaluate().isNotEmpty, isTrue);
    debugPrint(
      '账号只读 route=$route restored=true profile=true contacts=$contacts maskedAgain=true settings=true businessWrites=0',
    );
  });
}
