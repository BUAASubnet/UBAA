import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

import 'app_flow_test.dart' show createInspectionApp;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('原生 iPad 同页面草稿跨方向及明暗主题保留', (tester) async {
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
    final card = find.widgetWithText(Card, FeatureId.schedule.title);
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<FeatureQueryView>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('周课表').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '学期编码'),
      '2026-2027-1',
    );
    await tester.enterText(find.widgetWithText(TextField, '周次'), '7');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final shell = tester.state(find.byType(UbaaMainShell));
    final originalRatio = tester.view.devicePixelRatio;

    void checkDraft() {
      expect(tester.state(find.byType(UbaaMainShell)), same(shell));
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
      const samples = [
        ('title-1', '数据结构与算法'),
        ('subtitle-1', 'CS-DEMO-01'),
        ('title-2', '大学物理实验'),
        ('subtitle-2', 'PH-DEMO-02'),
      ];
      final result = <Map<String, Object?>>[];
      for (final sample in samples) {
        final finder = find.text(sample.$2);
        expect(finder, findsOneWidget);
        final text = tester.widget<Text>(finder);
        final context = tester.element(finder);
        final theme = Theme.of(context);
        expect(
          text.style?.color,
          sample.$1.startsWith('title')
              ? theme.textTheme.titleMedium?.color
              : theme.textTheme.bodySmall?.color,
          reason: '已打开详情的文字必须使用当前主题颜色',
        );
        result.add({
          'role': sample.$1,
          'textColorArgb': text.style?.color?.toARGB32(),
          'foregroundColorArgb': text.style?.foreground?.color.toARGB32(),
          'defaultTextColorArgb': DefaultTextStyle.of(
            context,
          ).style.color?.toARGB32(),
          'themeBrightness': theme.brightness.name,
          'themeTitleMediumColorArgb': theme.textTheme.titleMedium?.color
              ?.toARGB32(),
          'themeBodySmallColorArgb': theme.textTheme.bodySmall?.color
              ?.toARGB32(),
          'fontSize': text.style?.fontSize,
        });
      }
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
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, width >= 1000);
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
        'scene': 'schedule-unapplied-draft-native-rotation',
        'steps': 'XCUIDevice方向变化后读取真实窗口；同页面草稿与侧栏断言',
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
        await tester.tap(find.byIcon(Icons.person_outline));
        await tester.pumpAndSettle();
        final themeMenu = find.byType(DropdownButton<ThemeMode>);
        await tester.ensureVisible(themeMenu);
        await tester.tap(themeMenu);
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(brightness == Brightness.dark ? '深色' : '浅色').last,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.home_outlined));
        await tester.pumpAndSettle();
        final scheduleCard = find.widgetWithText(
          Card,
          FeatureId.schedule.title,
        );
        await tester.ensureVisible(scheduleCard);
        await tester.tap(scheduleCard);
        await tester.pumpAndSettle();
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
      await tester.tap(find.text('返回功能列表'));
      await tester.pumpAndSettle();
      await capture(
        '${brightness.name}-rotation-home',
        brightness,
        verifyDraft: false,
      );
      final homeCard = find.widgetWithText(Card, FeatureId.schedule.title);
      await tester.ensureVisible(homeCard);
      await tester.tap(homeCard);
      await tester.pumpAndSettle();
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
