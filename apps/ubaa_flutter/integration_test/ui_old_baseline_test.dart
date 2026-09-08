import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import 'app_flow_test.dart' show createInspectionApp;

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final brightness in Brightness.values) {
    testWidgets('旧版骨架原生逐页与按需面板：${brightness.name}', (tester) async {
      expect(Platform.isIOS || Platform.isMacOS, isTrue);
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(
        KeyedSubtree(
          key: ValueKey('old-${brightness.name}'),
          child: createInspectionApp(),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> capture(String scene, String steps) async {
        expect(tester.takeException(), isNull);
        final size = tester.view.physicalSize;
        final ratio = tester.view.devicePixelRatio;
        final name = '${brightness.name}-$scene';
        final records =
            (binding.reportData ??= <String, dynamic>{}).putIfAbsent(
                  'uiEvidence',
                  () => <Object?>[],
                )
                as List;
        records.add({
          'name': name,
          'scene': scene,
          'steps': steps,
          'backend': 'synthetic-inspection',
          'platform': Platform.operatingSystem,
          'system': Platform.operatingSystemVersion,
          'logicalWidth': size.width / ratio,
          'logicalHeight': size.height / ratio,
          'devicePixelRatio': ratio,
          'theme': brightness.name,
          'themeSource': 'test-platform-brightness-override',
          'viewportSource': 'native-view-unmodified',
          'dateUtc': DateTime.now().toUtc().toIso8601String(),
          'sourceSha': const String.fromEnvironment('UBAA_UI_SOURCE_SHA'),
        });
        if (Platform.isIOS) await binding.takeScreenshot(name);
      }

      Future<void> panel() async {
        await tester.tap(find.byTooltip('搜索与筛选'));
        await tester.pumpAndSettle();
      }

      Future<void> closePanel() async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, '完成'));
        await tester.pumpAndSettle();
      }

      Future<void> tab(int index) async {
        final narrow =
            tester.view.physicalSize.width / tester.view.devicePixelRatio < 600;
        if (narrow) {
          await tester.tap(find.byType(NavigationDestination).at(index));
        } else {
          final rail = tester.widget<NavigationRail>(
            find.byType(NavigationRail),
          );
          if (rail.selectedIndex != index) {
            final icon = [
              Icons.home_outlined,
              Icons.apps_outlined,
              Icons.auto_awesome_outlined,
            ][index];
            await tester.tap(
              find.descendant(
                of: find.byType(NavigationRail),
                matching: find.byIcon(icon),
              ),
            );
          }
        }
        await tester.pumpAndSettle();
      }

      await capture('login', '打开显式合成宿主');
      await tester.enterText(find.byType(TextField).at(0), '2020000000');
      await tester.enterText(find.byType(TextField).at(1), 'fixture-password');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, '首页'), findsOneWidget);
      expect(find.text('今日课表'), findsOneWidget);
      await capture('home', '合成登录，核对今日课表→待办区');

      const menus = <FeatureId, List<String>>{
        FeatureId.bykc: ['选择课程', '我的课程', '课程统计'],
        FeatureId.libbook: ['预约座位', '我的预约'],
        FeatureId.cgyy: ['预约研讨室', '我的预约', '门锁状态'],
      };
      final features = const bool.fromEnvironment('UBAA_UI_LANDING_ONLY')
          ? menus.keys
          : FeatureId.values;
      for (final feature in features) {
        await tab(ordinaryFeatureIds.contains(feature) ? 1 : 2);
        final card = find.widgetWithText(Card, feature.title);
        await tester.ensureVisible(card);
        await tester.pumpAndSettle();
        await tester.tap(card);
        await tester.pumpAndSettle();
        expect(find.widgetWithText(AppBar, feature.title), findsOneWidget);
        expect(find.text('返回功能列表'), findsNothing);
        expect(find.byType(TextField), findsNothing);
        expect(find.text('已选择 0 门待评课程'), findsNothing);
        if (tester.view.physicalSize.width / tester.view.devicePixelRatio <
            600) {
          expect(find.byType(NavigationBar), findsNothing);
        }
        await capture(
          'feature-${feature.name}',
          '从旧版功能分组打开${feature.title}，核对单顶栏与正文高度',
        );
        await panel();
        expect(
          find.widgetWithText(TextField, '筛选详情'),
          menus.containsKey(feature) ? findsNothing : findsOneWidget,
        );
        expect(find.text('应用筛选'), findsOneWidget);
        if (feature == FeatureId.grades) {
          final panelBox = find.byWidgetPredicate(
            (w) => w is Material && w.elevation == 8,
          );
          expect(tester.getSize(panelBox).height, lessThan(400));
          await tester.enterText(
            find.widgetWithText(TextField, '学期编码'),
            '未应用学期',
          );
          await tester.enterText(find.widgetWithText(TextField, '筛选详情'), '合成');
          await closePanel();
          expect(find.byType(TextField), findsNothing);
          await panel();
          expect(
            tester
                .widget<TextField>(find.widgetWithText(TextField, '学期编码'))
                .controller!
                .text,
            '未应用学期',
          );
          expect(
            tester
                .widget<TextField>(find.widgetWithText(TextField, '筛选详情'))
                .controller!
                .text,
            '合成',
          );
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await capture(
          'query-${feature.name}',
          '顶栏打开完整查询；结果页提供本地搜索，菜单不显示无结果搜索；成绩额外核验草稿',
        );
        await closePanel();
        if (menus.containsKey(feature)) {
          expect(find.byTooltip('实际路线：未确定'), findsOneWidget);
          for (final (index, label) in menus[feature]!.indexed) {
            final menuCard = find.widgetWithText(Card, label);
            await tester.ensureVisible(menuCard);
            await tester.tap(menuCard);
            await tester.pumpAndSettle();
            final pageTitle = feature == FeatureId.libbook && index == 1
                ? '我的座位预约'
                : label;
            expect(find.widgetWithText(AppBar, pageTitle), findsOneWidget);
            expect(find.byTooltip('实际路线：直连'), findsOneWidget);
            expect(find.byType(TextField), findsNothing);
            await capture(
              'child-${feature.name}-$index',
              '从子菜单进入$label，检查当前页标题、真实结果路线和正文；未触发写入',
            );
            if (index == 0) {
              await panel();
              await tester.enterText(
                find.widgetWithText(TextField, '筛选详情'),
                'draft',
              );
              await closePanel();
              await panel();
              expect(
                tester
                    .widget<TextField>(find.widgetWithText(TextField, '筛选详情'))
                    .controller!
                    .text,
                'draft',
              );
              await capture(
                'child-query-${feature.name}',
                '默认子页打开搜索、输入草稿、关闭、重开；草稿保留',
              );
              await closePanel();
            }
            await tester.tap(find.byTooltip('返回'));
            await tester.pumpAndSettle();
            expect(find.widgetWithText(AppBar, feature.title), findsOneWidget);
            expect(find.widgetWithText(Card, label), findsOneWidget);
            expect(find.byTooltip('实际路线：未确定'), findsOneWidget);
          }
        }
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
      }
      await tab(0);
      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
      scaffold.openDrawer();
      await tester.pumpAndSettle();
      await capture('sidebar', '打开侧栏，资料和设置不占主导航');
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(find.text('连接模式'), findsOneWidget);
      await capture('settings', '从侧栏进入设置，保留连接模式与匿名统计');
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
    });
  }
}
