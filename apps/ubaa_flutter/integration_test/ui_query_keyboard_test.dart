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
  setUpAll(() async => _deviceCapture = await _DeviceCapture.start());
  tearDownAll(() => _deviceCapture.close());
  for (final brightness in Brightness.values) {
    testWidgets('原生软键盘与放大文字下完成图书馆只读查询：${brightness.name}', (tester) async {
      await _login(tester, brightness, scale: 1.3);
      await _open(tester, FeatureId.libbook);
      await tester.tap(find.byType(DropdownButton<FeatureQueryView>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('座位查询').last);
      await tester.pumpAndSettle();
      for (final field in const [
        ('分区 ID', 'keyboard-fixture-area'),
        ('时段编号（必填）', 'keyboard-slot-1'),
        ('日期', '2026-09-08'),
      ]) {
        final finder = find.widgetWithText(TextField, field.$1);
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.enterText(finder, field.$2);
      }
      // 先等待完整键盘动画，再滚动到整枚按钮；不改原生窗口或占位。
      await _waitStableKeyboard(tester);
      final apply = find.widgetWithText(FilledButton, '应用筛选');
      await tester.ensureVisible(apply);
      await tester.pumpAndSettle();
      final stable = await _waitStableKeyboard(tester);
      final ratio = tester.view.devicePixelRatio;
      final availableBottom =
          tester.view.physicalSize.height / ratio -
          tester.view.viewInsets.bottom / ratio;
      final buttonBottom = tester.getRect(apply).bottom;
      expect(apply.hitTestable(), findsOneWidget);
      expect(
        buttonBottom,
        lessThanOrEqualTo(availableBottom),
        reason: '应用按钮必须完整位于稳定系统键盘上方',
      );
      final scene = '${brightness.name}-library-keyboard';
      await _capture(
        binding,
        tester,
        scene,
        brightness,
        '原生键盘占位稳定后滚动到应用按钮，字体比例1.3；尚未应用查询',
        keyboardEvidence: {
          ...stable,
          'applyButtonBottomLogical': buttonBottom,
          'keyboardTopLogical': availableBottom,
          'deviceScreenshot': '$scene-device.png',
        },
      );
      await _deviceCapture.pauseForScreenshot(tester, scene);
      expect(
        tester.getRect(apply).bottom,
        lessThanOrEqualTo(
          tester.view.physicalSize.height / ratio -
              tester.view.viewInsets.bottom / ratio,
        ),
      );
      await tester.tap(apply);
      await tester.pumpAndSettle();
      final snapshot = tester
          .widget<UbaaMainShell>(find.byType(UbaaMainShell))
          .snapshots[FeatureId.libbook]!;
      expect(snapshot.status, FeatureLoadStatus.success);
      final action = snapshot.details.single.action<LibbookReserveAction>()!;
      expect(action.areaId, 'keyboard-fixture-area');
      expect(action.segment, 'keyboard-slot-1');
      expect(action.day, '2026-09-08');
      // 检查查询返回的typed上下文；不操作任何预约按钮。
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await _capture(
        binding,
        tester,
        '${brightness.name}-library-query-result',
        brightness,
        '键盘仍开启时滚动并应用只读查询，断言返回的typed上下文，再收起键盘',
      );
    });

    testWidgets('原生刷新失败后保留搜索与上次结果：${brightness.name}', (tester) async {
      await _login(tester, brightness, state: 'stale');
      await _open(tester, FeatureId.grades);
      final search = find.widgetWithText(TextField, '筛选详情');
      await tester.enterText(search, '程序设计');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await _capture(
        binding,
        tester,
        '${brightness.name}-grades-before-refresh',
        brightness,
        '合成成绩中输入本地搜索并收起键盘',
      );
      await tester.tap(find.byTooltip('刷新当前查询'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<UbaaMainShell>(find.byType(UbaaMainShell))
            .snapshots[FeatureId.grades]!
            .status,
        FeatureLoadStatus.stale,
      );
      expect(tester.widget<TextField>(search).controller!.text, '程序设计');
      expect(find.text('程序设计基础'), findsOneWidget);
      await _capture(
        binding,
        tester,
        '${brightness.name}-grades-stale-search',
        brightness,
        '点击当前查询刷新，第二次默认读取失败，旧结果与本地搜索保持',
      );
    });
  }
}

Future<void> _login(
  WidgetTester tester,
  Brightness brightness, {
  double scale = 1,
  String state = 'normal',
}) async {
  expect(Platform.isIOS, isTrue);
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    KeyedSubtree(
      key: ValueKey('$brightness-$state'),
      child: createInspectionApp(state: state),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).at(0), '2020000000');
  await tester.enterText(find.byType(TextField).at(1), 'fixture-password');
  await tester.pump();
  final login = find.widgetWithText(FilledButton, '登录');
  await tester.ensureVisible(login);
  await tester.pumpAndSettle();
  await tester.tap(login);
  await tester.pumpAndSettle();
  expect(find.byType(UbaaMainShell), findsOneWidget);
}

Future<void> _open(WidgetTester tester, FeatureId feature) async {
  final grid = find.byType(CustomScrollView);
  final card = find.descendant(
    of: grid,
    matching: find.widgetWithText(Card, feature.title),
  );
  await tester.scrollUntilVisible(
    card,
    220,
    scrollable: find.descendant(of: grid, matching: find.byType(Scrollable)),
  );
  await tester.pumpAndSettle();
  await tester.tap(card);
  await tester.pumpAndSettle();
}

Future<void> _capture(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
  Brightness brightness,
  String steps, {
  Map<String, Object?>? keyboardEvidence,
}) async {
  expect(tester.takeException(), isNull);
  await tester.pump(const Duration(milliseconds: 200));
  final size = tester.view.physicalSize;
  final ratio = tester.view.devicePixelRatio;
  final context = tester.element(find.byType(UbaaMainShell));
  final records =
      (binding.reportData ??= <String, dynamic>{}).putIfAbsent(
            'uiEvidence',
            () => <Object?>[],
          )
          as List;
  records.add(<String, Object?>{
    'name': name,
    'scene': name,
    'steps': steps,
    'backend': 'synthetic-inspection',
    'platform': Platform.operatingSystem,
    'system': Platform.operatingSystemVersion,
    'physicalWidth': size.width,
    'physicalHeight': size.height,
    'devicePixelRatio': ratio,
    'logicalWidth': size.width / ratio,
    'logicalHeight': size.height / ratio,
    'nativeKeyboardInsetLogical': tester.view.viewInsets.bottom / ratio,
    'theme': brightness.name,
    'themeSource': 'test-platform-brightness-override',
    'textScale': MediaQuery.textScalerOf(context).scale(14) / 14,
    'textScaleSource': 'test-platform-text-scale',
    'viewportSource': 'native-view-unmodified',
    'captureRunId': _deviceCapture.runId,
    'keyboardEvidence': ?keyboardEvidence,
    'dateUtc': DateTime.now().toUtc().toIso8601String(),
    'sourceSha': const String.fromEnvironment(
      'UBAA_UI_SOURCE_SHA',
      defaultValue: 'unrecorded',
    ),
  });
  await binding.takeScreenshot(name);
}

late _DeviceCapture _deviceCapture;

/// 稳定至少六次采样且持续700ms；总观察不少于1秒，避免接受动画第一帧。
Future<Map<String, Object?>> _waitStableKeyboard(WidgetTester tester) async {
  final elapsed = Stopwatch()..start();
  final stableTime = Stopwatch();
  double? last;
  var samples = 0;
  while (elapsed.elapsed < const Duration(seconds: 15)) {
    await tester.pump(const Duration(milliseconds: 100));
    final inset = tester.view.viewInsets.bottom / tester.view.devicePixelRatio;
    if (inset > 0 && last != null && (inset - last).abs() < 0.5) {
      samples++;
      if (!stableTime.isRunning) stableTime.start();
    } else {
      samples = 0;
      stableTime.reset();
      stableTime.stop();
    }
    last = inset;
    if (samples >= 6 &&
        stableTime.elapsedMilliseconds >= 700 &&
        elapsed.elapsedMilliseconds >= 1000) {
      return {
        'stableInsetLogical': inset,
        'stableSamples': samples,
        'stableDurationMs': stableTime.elapsedMilliseconds,
        'observationDurationMs': elapsed.elapsedMilliseconds,
        'insetSource': 'native-view-unmodified',
      };
    }
  }
  fail('未观察到稳定的真实软键盘占位');
}

/// 仅测试回环服务，双方必须核对本轮runId；不传账号、查询正文或图片字节。
class _DeviceCapture {
  _DeviceCapture(this.server, this.runId);
  final HttpServer server;
  final String runId;
  String? pending;
  String? acknowledged;

  static Future<_DeviceCapture> start() async {
    const runId = String.fromEnvironment('UBAA_KEYBOARD_RUN_ID');
    if (runId.isEmpty) throw StateError('必须提供本轮键盘证据runId');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 48764);
    final bridge = _DeviceCapture(server, runId);
    server.listen((request) async {
      final matchingRun = request.uri.queryParameters['runId'] == runId;
      if (!matchingRun) {
        request.response.statusCode = HttpStatus.forbidden;
      } else if (request.method == 'GET' && request.uri.path == '/status') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'runId': runId,
            'phase': bridge.pending == null ? 'idle' : 'capture',
            'scene': bridge.pending,
          }),
        );
      } else if (request.method == 'POST' &&
          request.uri.path == '/ack' &&
          bridge.pending != null &&
          request.uri.queryParameters['scene'] == bridge.pending) {
        bridge.acknowledged = bridge.pending;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'runId': runId, 'phase': 'accepted'}),
        );
      } else {
        request.response.statusCode = HttpStatus.badRequest;
      }
      await request.response.close();
    });
    return bridge;
  }

  Future<void> pauseForScreenshot(WidgetTester tester, String scene) async {
    acknowledged = null;
    pending = scene;
    final elapsed = Stopwatch()..start();
    while (acknowledged != scene &&
        elapsed.elapsed < const Duration(seconds: 60)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(acknowledged, scene, reason: '整机截图完成并核对runId后才能继续查询');
    pending = null;
  }

  Future<void> close() => server.close(force: true).then((_) {});
}
