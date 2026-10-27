import '../../navigation.dart';
import 'package:ubaa_ui/ubaa_ui.dart' show UiDestination;
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import 'flow_test.dart' show createInspectionApp;

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final brightness in Brightness.values) {
    testWidgets('共享布局原生逐页与按需面板：${brightness.name}', (tester) async {
      expect(Platform.isIOS || Platform.isMacOS || Platform.isAndroid, isTrue);
      if (const bool.fromEnvironment('UBAA_UI_LANDSCAPE') &&
          (Platform.isIOS || Platform.isAndroid)) {
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        addTearDown(
          () => SystemChrome.setPreferredOrientations(DeviceOrientation.values),
        );
      }
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(
        KeyedSubtree(
          key: ValueKey('shared-${brightness.name}'),
          child: RepaintBoundary(
            key: const ValueKey('native-capture'),
            child: createInspectionApp(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (Platform.isAndroid) {
        await binding.convertFlutterSurfaceToImage();
        await tester.pumpAndSettle();
      }

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
          'imageSource': Platform.isMacOS
              ? 'native-flutter-repaint-boundary'
              : 'integration-test-native-screenshot',
        });
        if (Platform.isIOS || Platform.isAndroid) {
          await binding.takeScreenshot(name);
        } else if (Platform.isMacOS) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('native-capture')),
          );
          final image = await boundary.toImage(pixelRatio: ratio);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          (binding.reportData!.putIfAbsent('nativeRenders', () => <Object?>[])
                  as List)
              .add({
                'name': name,
                'bytes': data!.buffer.asUint8List().toList(),
              });
        }
      }

      final search = find.byKey(const ValueKey<String>('feature-search-field'));
      final filterButton = find.byKey(
        const ValueKey<String>('feature-filter-button'),
      );
      const searchable = {
        FeatureId.exam,
        FeatureId.grades,
        FeatureId.classroom,
        FeatureId.evaluation,
        FeatureId.signin,
        FeatureId.spoc,
        FeatureId.judge,
        FeatureId.ygdk,
      };
      const filterable = {
        FeatureId.exam,
        FeatureId.grades,
        FeatureId.evaluation,
        FeatureId.signin,
        FeatureId.spoc,
        FeatureId.judge,
      };

      Future<void> panel() async {
        await tester.tap(filterButton);
        await tester.pumpAndSettle();
      }

      Future<void> closePanel() async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('关闭筛选'));
        await tester.pumpAndSettle();
      }

      Future<void> tab(int index) async {
        final target = uiDestinationFinder(tester, UiDestination.values[index]);
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
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
      expect(find.textContaining(RegExp(r'^(今日|明日)课表$')), findsOneWidget);
      await capture('home', '合成登录，核对今日课表→待办区');

      const menus = <FeatureId, List<String>>{
        FeatureId.bykc: ['选择课程', '我的课程', '课程统计'],
        FeatureId.libbook: ['预约座位', '我的预约'],
        FeatureId.cgyy: ['预约研讨室', '我的预约', '查看密码'],
      };
      final features = const bool.fromEnvironment('UBAA_UI_LANDING_ONLY')
          ? menus.keys
          : FeatureId.values;
      for (final feature in features) {
        await tab(UiDestination.forFeature(feature).index);
        final card = find.widgetWithText(Card, feature.title);
        if (card.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            card,
            240,
            scrollable: find.descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            ),
          );
        }
        await tester.ensureVisible(card);
        await tester.pumpAndSettle();
        await tester.tap(card);
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(
            AppBar,
            feature == FeatureId.schedule ? '课表' : feature.title,
          ),
          findsOneWidget,
        );
        expect(find.text('返回功能列表'), findsNothing);
        // 结果列表常驻搜索框；有可调条件的列表才在旁边提供筛选按钮。
        expect(
          search,
          searchable.contains(feature) ? findsOneWidget : findsNothing,
        );
        expect(
          filterButton,
          filterable.contains(feature) ? findsOneWidget : findsNothing,
        );
        expect(find.byTooltip('关闭筛选'), findsNothing);
        expect(find.text('已选择 0 门待评课程'), findsNothing);
        if (tester.view.physicalSize.width / tester.view.devicePixelRatio <
            600) {
          expect(find.byType(NavigationBar), findsOneWidget);
        }
        await capture(
          'feature-${feature.name}',
          '从当前功能分组打开${feature.title}，核对单顶栏与正文高度',
        );
        if (feature == FeatureId.schedule) {
          await tester.tap(find.byTooltip('选择学期'));
          await tester.pumpAndSettle();
          await capture('schedule-term-choice', '课表顶栏直接选择学期');
          await tester.tap(find.widgetWithText(TextButton, '取消'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('返回'));
          await tester.pumpAndSettle();
          continue;
        }
        if (filterable.contains(feature)) {
          await panel();
          if (feature == FeatureId.spoc || feature == FeatureId.judge) {
            expect(
              find.text(feature == FeatureId.spoc ? '仅显示未提交' : '仅显示未完成'),
              findsOneWidget,
            );
          } else {
            expect(find.widgetWithText(ChoiceChip, '全部'), findsOneWidget);
          }
          if (feature == FeatureId.grades) {
            final panelBox = find.byWidgetPredicate(
              (w) => w is Material && w.elevation == 8,
            );
            expect(tester.getSize(panelBox).height, lessThan(400));
          }
          await capture('query-${feature.name}', '筛选面板只含点选即生效的状态或排序条件，不含协议参数');
          await closePanel();
        }
        if (feature == FeatureId.grades) {
          await tester.enterText(search, '合成');
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          await panel();
          await closePanel();
          expect(tester.widget<TextField>(search).controller!.text, '合成');
          await tester.tap(find.byTooltip('清除搜索'));
          await tester.pumpAndSettle();
        }
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
            final lockPage = feature == FeatureId.cgyy && index == 2;
            expect(
              find.byTooltip(lockPage ? '实际路线：未确定' : '实际路线：直连'),
              findsOneWidget,
            );
            if (lockPage) {
              expect(find.text('001234'), findsOneWidget);
              expect(
                find.byKey(const ValueKey<String>('feature-filter-button')),
                findsNothing,
              );
            }
            // 博雅选课与我的课程、两处“我的预约”是结果列表；预约流程、统计和密码页不搜索。
            final childSearch =
                (feature == FeatureId.bykc && index < 2) ||
                (feature != FeatureId.bykc && index == 1);
            expect(search, childSearch ? findsOneWidget : findsNothing);
            expect(
              filterButton,
              feature == FeatureId.bykc && index == 0
                  ? findsOneWidget
                  : findsNothing,
            );
            await capture(
              'child-${feature.name}-$index',
              '从子菜单进入$label，检查当前页标题、真实结果路线和正文；未触发写入',
            );
            if (childSearch) {
              await tester.enterText(search, 'draft');
              FocusManager.instance.primaryFocus?.unfocus();
              await tester.pumpAndSettle();
              if (filterButton.evaluate().isNotEmpty) {
                await panel();
                await closePanel();
              }
              expect(
                tester.widget<TextField>(search).controller!.text,
                'draft',
              );
              await capture(
                'child-query-${feature.name}-$index',
                '子页常驻搜索输入后开关筛选，关键字保留',
              );
              await tester.tap(find.byTooltip('清除搜索'));
              await tester.pumpAndSettle();
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
      await tab(UiDestination.settings.index);
      expect(find.text('外观主题'), findsOneWidget);
      await capture('settings', '进入分组设置，保留主题、连接、隐私及账号操作');
      final themePicker = find.byType(DropdownButton<ThemeMode>);
      await tester.tap(themePicker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('浅色').last);
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(themePicker)).brightness,
        Brightness.light,
      );
      await tester.tap(themePicker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('跟随系统').last);
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(themePicker)).brightness, brightness);
      final diagnostics = find.text('本次运行诊断');
      await tester.scrollUntilVisible(
        diagnostics,
        250,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey<String>('feature-pages')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(diagnostics);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await capture('diagnostics', '沿设置进入合成会话的脱敏诊断，主题切换后恢复跟随系统');
      await tester.tap(find.widgetWithText(TextButton, '关闭'));
      await tester.pumpAndSettle();
      await tab(UiDestination.home.index);
    });
  }
}
