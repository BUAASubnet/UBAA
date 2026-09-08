import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('个人页主题选择在本次宿主运行中保持且导航重建不查询', (tester) async {
    _setSize(tester);
    final backend = _CountingBackend();
    final vault = MemoryCredentialVault();
    Future<void> mount() async {
      await tester.pumpWidget(
        UbaaAppHost(
          key: const ValueKey<String>('same-host'),
          backend: backend,
          credentialVault: vault,
        ),
      );
      await tester.pumpAndSettle();
    }

    await mount();
    await _login(tester);
    final calls = backend.featureLoads;
    final hostState = tester.state(find.byType(UbaaAppHost));
    await _profile(tester);
    final theme = find.byType(DropdownButton<ThemeMode>);
    // 旧宿主没有主题选择；此断言应先产生功能缺失 RED。
    expect(theme, findsOneWidget);
    expect(
      tester.widget<DropdownButton<ThemeMode>>(theme).value,
      ThemeMode.system,
    );
    await _choose(tester, '深色');
    expect(_mode(tester), ThemeMode.dark);
    expect(
      Theme.of(tester.element(find.byType(UbaaMainShell))).brightness,
      Brightness.dark,
    );

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(_mode(tester), ThemeMode.dark);
    await _profile(tester);
    await mount();
    expect(tester.state(find.byType(UbaaAppHost)), same(hostState));
    expect(_mode(tester), ThemeMode.dark);
    expect(
      tester.widget<DropdownButton<ThemeMode>>(theme).value,
      ThemeMode.dark,
    );
    await _choose(tester, '浅色');
    expect(_mode(tester), ThemeMode.light);
    expect(
      Theme.of(tester.element(find.byType(UbaaMainShell))).brightness,
      Brightness.light,
    );
    await _choose(tester, '跟随系统');
    expect(_mode(tester), ThemeMode.system);
    expect(backend.featureLoads, calls);
  });

  testWidgets('销毁并创建全新宿主后主题恢复跟随系统而非持久化深色', (tester) async {
    _setSize(tester);
    await tester.pumpWidget(
      UbaaAppHost(
        key: const ValueKey<String>('first-run'),
        backend: _CountingBackend(),
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();
    await _login(tester);
    await _profile(tester);
    expect(find.byType(DropdownButton<ThemeMode>), findsOneWidget);
    await _choose(tester, '深色');
    expect(_mode(tester), ThemeMode.dark);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      UbaaAppHost(
        key: const ValueKey<String>('second-run'),
        backend: _CountingBackend(),
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(UbaaLoginView), findsOneWidget);
    expect(_mode(tester), ThemeMode.system);
    await _login(tester);
    await _profile(tester);
    expect(
      tester
          .widget<DropdownButton<ThemeMode>>(
            find.byType(DropdownButton<ThemeMode>),
          )
          .value,
      ThemeMode.system,
    );
  });
}

class _CountingBackend extends DemoBackend {
  _CountingBackend() : super(loginDelay: Duration.zero);
  int featureLoads = 0;
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) {
    featureLoads++;
    return super.loadFeature(feature);
  }
}

void _setSize(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(599, 1000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

ThemeMode? _mode(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode;

Future<void> _login(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(0), 'fixture-student');
  await tester.enterText(find.byType(TextField).at(1), 'fixture-password');
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, '登录'));
  await tester.pumpAndSettle();
  expect(find.byType(UbaaMainShell), findsOneWidget);
}

Future<void> _profile(WidgetTester tester) async {
  tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(Drawer), matching: find.text('设置')),
  );
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DropdownButton<ThemeMode>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}
