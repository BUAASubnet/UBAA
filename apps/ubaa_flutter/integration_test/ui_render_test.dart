import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

import 'app_flow_test.dart' show createInspectionApp;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const landscape = bool.fromEnvironment('UBAA_UI_LANDSCAPE');
  for (final brightness in Brightness.values) {
    testWidgets('原生合成界面逐页截图与草稿连续性：${brightness.name}', (tester) async {
      expect(Platform.isIOS, isTrue, reason: '此入口只用于 iPhone/iPad 原生截图');
      if (landscape) {
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        addTearDown(
          () => SystemChrome.setPreferredOrientations(DeviceOrientation.values),
        );
      }
      // 仅覆盖测试绑定的亮度输入，不修改系统设置，也不伪称系统主题切换。
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(
        KeyedSubtree(
          key: ValueKey<String>('native-${brightness.name}'),
          child: createInspectionApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(UbaaLoginView), findsOneWidget);
      expect(
        Theme.of(tester.element(find.byType(UbaaLoginView))).brightness,
        brightness,
      );

      if (landscape) {
        for (
          var attempt = 0;
          attempt < 30 &&
              tester.view.physicalSize.width < tester.view.physicalSize.height;
          attempt++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          tester.view.physicalSize.width,
          greaterThan(tester.view.physicalSize.height),
          reason: '必须由原生视图实际旋转；不以测试视口替代横屏',
        );
      }

      Future<void> capture(
        String scene,
        String steps, {
        String? actualTheme,
        String? themeSource,
      }) async {
        final name = '${brightness.name}-$scene';
        final physical = tester.view.physicalSize;
        final ratio = tester.view.devicePixelRatio;
        final records =
            (binding.reportData ??= <String, dynamic>{}).putIfAbsent(
                  'uiEvidence',
                  () => <Object?>[],
                )
                as List;
        records.add(<String, Object?>{
          'name': name,
          'scene': scene,
          'steps': steps,
          'backend': 'synthetic-inspection',
          'platform': Platform.operatingSystem,
          'system': Platform.operatingSystemVersion,
          'physicalWidth': physical.width,
          'physicalHeight': physical.height,
          'devicePixelRatio': ratio,
          'logicalWidth': physical.width / ratio,
          'logicalHeight': physical.height / ratio,
          'theme': actualTheme ?? brightness.name,
          'themeSource': themeSource ?? 'test-platform-brightness-override',
          'orientationRequest': landscape ? 'native-landscape' : 'unchanged',
          'viewportSource': 'native-view-unmodified',
          'dateUtc': DateTime.now().toUtc().toIso8601String(),
          'sourceSha': const String.fromEnvironment(
            'UBAA_UI_SOURCE_SHA',
            defaultValue: 'unrecorded',
          ),
        });
        expect(tester.takeException(), isNull);
        // iOS callback 不支持 args；小型元数据单独放 reportData。
        await binding.takeScreenshot(name);
      }

      await capture('login', '打开显式合成宿主，尚未输入凭据');
      await tester.enterText(find.byType(TextField).at(0), '2020000000');
      await tester.enterText(find.byType(TextField).at(1), 'fixture-password');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();
      expect(find.byType(UbaaMainShell), findsOneWidget);
      await capture('home', '合成账号登录进入首页');

      for (final feature in FeatureId.values) {
        final ordinary = learningFeatureIds.contains(feature);
        await _selectTab(
          tester,
          ordinary ? Icons.apps : Icons.auto_awesome,
          ordinary ? Icons.apps_outlined : Icons.auto_awesome_outlined,
        );
        final grid = find.byType(CustomScrollView);
        final card = find.descendant(
          of: grid,
          matching: find.widgetWithText(Card, feature.title),
        );
        await _scroll(tester, card, grid);
        expect(card.hitTestable(), findsOneWidget);
        await tester.tap(card);
        await tester.pumpAndSettle();
        expect(find.text('返回功能列表'), findsOneWidget);
        await capture(
          'feature-${feature.name}',
          '点击${feature.title}功能卡进入默认子视图',
        );

        if (feature == FeatureId.schedule) {
          await tester.tap(find.byType(DropdownButton<FeatureQueryView>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('周课表').last);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.widgetWithText(TextField, '学期编码'),
            '2026-2027-1',
          );
          await tester.enterText(find.widgetWithText(TextField, '周次'), '7');
          // 原生集成不注册 TestTextInput；结束真实焦点以收起输入连接。
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          await _back(tester);
          await _scroll(tester, card, find.byType(CustomScrollView));
          await tester.tap(card);
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<DropdownButton<FeatureQueryView>>(
                  find.byType(DropdownButton<FeatureQueryView>),
                )
                .value,
            FeatureQueryView.scheduleWeek,
          );
          expect(
            tester
                .widget<TextField>(find.widgetWithText(TextField, '学期编码'))
                .controller!
                .text,
            '2026-2027-1',
          );
          expect(
            tester
                .widget<TextField>(find.widgetWithText(TextField, '周次'))
                .controller!
                .text,
            '7',
          );
          await capture(
            'schedule-draft-restored',
            '周课表输入未应用学期和周次，返回列表后重入，断言草稿保留',
          );
        }
        await _back(tester);
      }

      await _selectTab(tester, Icons.person, Icons.person_outline);
      await capture('profile', '实际点击我的导航');
      final themeChoice = find.byType(DropdownButton<ThemeMode>);
      await _scroll(tester, themeChoice, find.byType(ListView));
      await tester.tap(themeChoice);
      await tester.pumpAndSettle();
      final opposite = brightness == Brightness.light
          ? Brightness.dark
          : Brightness.light;
      await tester.tap(
        find.text(opposite == Brightness.dark ? '深色' : '浅色').last,
      );
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(UbaaMainShell))).brightness,
        opposite,
      );
      await capture(
        'profile-theme-switched',
        '在个人页实际选择相反主题，验证宿主主题生效',
        actualTheme: opposite.name,
        themeSource: 'user-theme-control',
      );
      await tester.tap(themeChoice);
      await tester.pumpAndSettle();
      await tester.tap(find.text('跟随系统').last);
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(UbaaMainShell))).brightness,
        brightness,
      );
      final diagnostics = find.text('本次运行诊断');
      await _scroll(tester, diagnostics, find.byType(ListView));
      await tester.tap(diagnostics);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await capture('diagnostics', '从个人页打开合成会话的安全诊断弹窗');
      await tester.tap(find.widgetWithText(TextButton, '关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await _selectTab(tester, Icons.home, Icons.home_outlined);
      await capture('home-return', '关闭诊断并返回首页');
    });
  }
}

Future<void> _selectTab(
  WidgetTester tester,
  IconData selected,
  IconData idle,
) async {
  final icon = find.byIcon(selected).evaluate().isNotEmpty
      ? find.byIcon(selected)
      : find.byIcon(idle);
  expect(icon, findsOneWidget);
  await tester.tap(icon);
  await tester.pumpAndSettle();
}

Future<void> _scroll(
  WidgetTester tester,
  Finder target,
  Finder container,
) async {
  expect(container, findsOneWidget);
  await tester.scrollUntilVisible(
    target,
    220,
    scrollable: find.descendant(
      of: container,
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.text('返回功能列表'));
  await tester.pumpAndSettle();
}
