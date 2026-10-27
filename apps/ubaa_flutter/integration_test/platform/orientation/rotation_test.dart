import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

import '../../navigation.dart';
import '../../synthetic/app/flow_test.dart' show createInspectionApp;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('原生 iPad 课表所选周次跨方向及明暗主题保留', (tester) async {
    expect(Platform.isIOS, isTrue);
    // 仅测试进程使用的模拟器回环握手；不连接业务网络或暴露业务内容。
    const runId = String.fromEnvironment('UBAA_ROTATION_RUN_ID');
    const useUserTheme = bool.fromEnvironment('UBAA_ROTATION_USER_THEME');
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    expect(runId, isNotEmpty, reason: '旋转测试必须有本轮唯一运行标识');
    var marker = 'ubaa-rotation-starting';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 48763);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.uri.path != '/rotation-marker') {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'runId': runId, 'phase': marker}));
      }
      await request.response.close();
    });
    await tester.pumpWidget(createInspectionApp());
    await tester.pumpAndSettle();
    expect(find.byType(UbaaLoginView), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '2020000000');
    await tester.enterText(find.byType(TextField).at(1), 'fixture-password');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    Future<void> openSchedule() async {
      await tester.tap(uiDestinationFinder(tester, UiDestination.academic));
      await tester.pumpAndSettle();
      final card = find.widgetWithText(Card, FeatureId.schedule.title);
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();
    }

    // 课表自动定位本周后，沿课表自身选择器换到下一周，作为需跨方向保留的页面状态。
    await openSchedule();
    await tester.tap(find.byTooltip('下一周'));
    await tester.pumpAndSettle();
    final shell = tester.state(find.byType(UbaaMainShell));
    final originalRatio = tester.view.devicePixelRatio;

    void checkDraft() {
      expect(tester.state(find.byType(UbaaMainShell)), same(shell));
      final query = tester
          .widget<UbaaMainShell>(find.byType(UbaaMainShell))
          .snapshots[FeatureId.schedule]!
          .readContext!
          .query!;
      expect(query.view, FeatureQueryView.scheduleWeek);
      expect(query.term, '2026-2027-1');
      expect(query.week, 3);
      expect(find.text('第 3 周'), findsOneWidget);
      expect(tester.view.devicePixelRatio, originalRatio);
      expect(tester.takeException(), isNull);
    }

    Future<void> waitDirection(bool landscape) async {
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
        final size = tester.view.physicalSize;
        if (landscape ? size.width > size.height : size.height > size.width) {
          await tester.pumpAndSettle();
          return;
        }
      }
      final size = tester.view.physicalSize;
      fail('原生方向未变化：${size.width}×${size.height}，期待横屏=$landscape');
    }

    List<Map<String, Object?>> textStyleDiagnostics() {
      const samples = ['数据结构与算法', '大学物理实验'];
      final result = <Map<String, Object?>>[];
      for (final (index, sample) in samples.indexed) {
        final finder = find.text(sample);
        if (finder.evaluate().isEmpty) continue;
        final text = tester.widget<Text>(finder);
        final context = tester.element(finder);
        final foreground = text.style?.foreground?.color ?? text.style?.color;
        final background = context
            .findAncestorWidgetOfExactType<Material>()
            ?.color;
        expect(foreground, isNotNull, reason: '课表课程标题需要可核对的前景色');
        expect(background, isNotNull, reason: '课表课程标题需要对应课程色块');
        final front = foreground!.computeLuminance();
        final back = background!.computeLuminance();
        final contrast = front > back
            ? (front + .05) / (back + .05)
            : (back + .05) / (front + .05);
        // 课表网格用课程色块及黑白前景色；主题切换后旧文字颜色会失去对比度。
        expect(contrast, greaterThanOrEqualTo(4.5));
        result.add({
          'role': 'course-title-${index + 1}',
          'textColorArgb': foreground.toARGB32(),
          'backgroundColorArgb': background.toARGB32(),
          'contrastRatio': contrast,
          'themeBrightness': Theme.of(context).brightness.name,
          'fontSize': text.style?.fontSize,
        });
      }
      expect(result, isNotEmpty, reason: '课表页必须渲染至少一项合成样本');
      // 只记录合成元素角色与样式数值，不记录文本内容、账号或业务数据。
      debugPrint('旋转文字样式：${jsonEncode(result)}');
      return result;
    }

    Future<void> capture(
      String name,
      Brightness brightness, {
      bool verifyDraft = true,
    }) async {
      // 等待主题/导航完成，并让原生渲染器再提交稳定帧后才采集屏幕。
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      if (verifyDraft) checkDraft();
      final physical = tester.view.physicalSize;
      final ratio = tester.view.devicePixelRatio;
      final width = physical.width / ratio;
      if (width >= 1000) {
        final destination = tester.widget<ListTile>(
          uiDestinationFinder(tester, UiDestination.academic),
        );
        expect(destination.selected, isTrue);
        expect(destination.onTap, isNotNull);
      } else {
        final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
        expect(rail.selectedIndex, UiDestination.academic.index);
        expect(rail.onDestinationSelected, isNotNull);
      }
      expect(
        Theme.of(tester.element(find.byType(UbaaMainShell))).brightness,
        brightness,
      );
      final records =
          (binding.reportData ??= <String, dynamic>{}).putIfAbsent(
                'uiEvidence',
                () => <Object?>[],
              )
              as List;
      records.add(<String, Object?>{
        'name': name,
        'scene': 'schedule-selected-week-native-rotation',
        'steps': 'XCUIDevice方向变化后读取真实窗口；所选周次与侧栏断言',
        'backend': 'synthetic-inspection',
        'platform': Platform.operatingSystem,
        'system': Platform.operatingSystemVersion,
        'physicalWidth': physical.width,
        'physicalHeight': physical.height,
        'logicalWidth': width,
        'logicalHeight': physical.height / ratio,
        'devicePixelRatio': ratio,
        'theme': brightness.name,
        'themeSource': useUserTheme
            ? 'user-theme-control'
            : 'test-platform-brightness-override',
        if (verifyDraft) 'textStyleDiagnostics': textStyleDiagnostics(),
        'viewportSource': 'native-view-unmodified',
        'rotationSource': 'XCUIDevice.orientation',
        'rotationRunId': runId,
        'dateUtc': DateTime.now().toUtc().toIso8601String(),
        'sourceSha': const String.fromEnvironment(
          'UBAA_UI_SOURCE_SHA',
          defaultValue: 'unrecorded',
        ),
      });
      await binding.takeScreenshot(name);
    }

    for (final brightness in [Brightness.dark, Brightness.light]) {
      if (useUserTheme) {
        // 使用真实个人页控件切换当前宿主的内存主题，不覆盖平台亮度。
        await uiOpenUtility(tester, '设置');
        final themeMenu = find.byType(DropdownButton<ThemeMode>);
        await tester.ensureVisible(themeMenu);
        await tester.tap(themeMenu);
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(brightness == Brightness.dark ? '深色' : '浅色').last,
        );
        await tester.pumpAndSettle();
        await openSchedule();
        checkDraft();
      } else {
        // 重放原先标题颜色未更新的就地亮度切换路径，不重入详情页面。
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        await tester.pumpAndSettle();
        checkDraft();
      }
      await waitDirection(false);
      await capture('${brightness.name}-rotation-before', brightness);
      marker = 'ubaa-rotation-ready-${brightness.name}';
      await waitDirection(true);
      await capture('${brightness.name}-rotation-landscape', brightness);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await capture(
        '${brightness.name}-rotation-home',
        brightness,
        verifyDraft: false,
      );
      await openSchedule();
      await capture('${brightness.name}-rotation-restored', brightness);
      marker = 'ubaa-rotation-landscape-${brightness.name}';
      await waitDirection(false);
      await capture('${brightness.name}-rotation-portrait', brightness);
      marker = 'ubaa-rotation-portrait-${brightness.name}';
      // 给原生等待器观察本次完成标记的机会，下一主题不重建页面。
      await tester.pump(const Duration(seconds: 2));
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
