import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'backend.dart';

void main() {
  if (const bool.fromEnvironment('UBAA_UI_INSPECTION')) {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(
      UbaaFlutterApp(
        backend: HomeBackend(
          state: const String.fromEnvironment(
            'UBAA_UI_STATE',
            defaultValue: 'normal',
          ),
        ),
        credentialVault: MemoryCredentialVault(),
      ),
    );
    return;
  }
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  for (final brightness in Brightness.values) {
    testWidgets('首页六来源旧布局直达详情与合成签到取消 ${brightness.name}', (tester) async {
      final backend = HomeBackend();
      await mount(tester, backend, brightness);
      Future<void> shot(String name, String steps) =>
          capture(binding, tester, '${brightness.name}-normal-$name', steps);
      await shot('today', '今日课程按时间排序，名称时间地点和简称');
      await tap(tester, find.byTooltip('实际路线：直连'));
      await shot('routes', '一个图标按已显示来源说明实际路线，不使用默认Auto策略');
      await tap(tester, find.text('关闭'));
      await ensure(tester, find.text('合成签到待办'));
      await shot('todos', '六来源按时间混合排序，旧来源和状态标签');
      await tap(tester, find.widgetWithText(FilledButton, '签到'));
      expect(backend.preparedSignin, ['signin-target']);
      await shot('signin-confirm', '明确合成目标prepare，未执行commit');
      await tap(tester, find.widgetWithText(OutlinedButton, '取消'));
      for (final (title, view) in [
        ('合成博雅待办', FeatureQueryView.bykcDetail),
        ('合成希冀待办', FeatureQueryView.judgeDetail),
        ('合成SPOC待办', FeatureQueryView.spocDetail),
        ('合成研讨室待办', FeatureQueryView.cgyyOrders),
      ]) {
        await tap(tester, find.text(title));
        expect(backend.homeQueries.last.$2.view, view);
        await shot(view.name.toLowerCase(), '待办直接到原只读目标，顶部返回回首页');
        await tap(tester, find.byTooltip('返回'));
      }
      await ensure(tester, find.text('本周阳光打卡未达标'));
      await shot('sunlight', '旧第11到14周提醒规则，只显示真实投影次数');
      await tap(tester, find.text('本周阳光打卡未达标'));
      await shot('reminder-enabled', '阳光旧概要后恢复首页提醒开关');
      await tap(tester, find.widgetWithText(SwitchListTile, '首页提醒'));
      expect(
        tester
            .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '首页提醒'))
            .value,
        isFalse,
      );
      await shot('reminder-disabled', '本地提醒关闭，未提交任何学校写入');
      await tap(tester, find.byTooltip('返回'));
      expect(find.text('本周阳光打卡未达标'), findsNothing);
      await shot('home-reminder-off', '返回首页保留滚动和关闭状态');
      expect(backend.commitCalls, 0);
    });
    for (final state in [
      'empty',
      'partial-error',
      'stale',
      'loading',
      'long',
      'many',
      'mixed',
    ]) {
      testWidgets('首页原生 $state ${brightness.name}', (tester) async {
        final backend = HomeBackend(state: state)
          ..mixedRoutes = state == 'mixed';
        if (state == 'long') {
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        }
        await mount(tester, backend, brightness);
        Future<void> shot(String name) => capture(
          binding,
          tester,
          '${brightness.name}-$state-$name',
          '原生合成首页状态，实际视口不覆盖',
        );
        if (state == 'stale') {
          backend.failFeatures.add(FeatureId.spoc);
          await tester
              .widget<UbaaMainShell>(find.byType(UbaaMainShell))
              .onRefresh();
          await tester.pumpAndSettle();
        } else if (state == 'loading') {
          final gate = Completer<void>();
          backend.pending = gate;
          final pending = tester
              .widget<UbaaMainShell>(find.byType(UbaaMainShell))
              .onRefresh();
          await tester.pump(const Duration(milliseconds: 250));
          await shot('pending');
          gate.complete();
          await pending;
          await tester.pumpAndSettle();
        }
        await shot('top');
        if (state == 'many') {
          await ensure(tester, find.text('合成待办 42'));
        } else if (state == 'mixed') {
          await tap(tester, find.byTooltip('实际路线：混合'));
        } else if (state != 'empty') {
          await ensure(tester, find.text('本周阳光打卡未达标'));
        }
        await shot('result');
        expect(backend.commitCalls, 0);
      });
    }
  }
}

Future<void> mount(
  WidgetTester tester,
  HomeBackend backend,
  Brightness brightness,
) async {
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await tester.pumpWidget(
    UbaaFlutterApp(backend: backend, credentialVault: MemoryCredentialVault()),
  );
  await tester.pumpAndSettle();
}

Future<void> ensure(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final scroll = find
        .byElementPredicate(
          (e) =>
              e.widget is Scrollable &&
              (e.widget as Scrollable).axisDirection == AxisDirection.down &&
              e is StatefulElement &&
              (e.state as ScrollableState).position.viewportDimension > 100,
        )
        .hitTestable()
        .last;
    await tester.drag(scroll, const Offset(0, 30000));
    await tester.pumpAndSettle();
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        240,
        scrollable: scroll,
        maxScrolls: 80,
      );
    }
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await ensure(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> capture(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
  String steps,
) async {
  expect(tester.takeException(), isNull);
  final size = tester.view.physicalSize, ratio = tester.view.devicePixelRatio;
  final records =
      (binding.reportData ??= <String, dynamic>{}).putIfAbsent(
            'uiEvidence',
            () => <Object?>[],
          )
          as List;
  records.add({
    'name': name,
    'steps': steps,
    'backend': 'synthetic-home',
    'platform': Platform.operatingSystem,
    'system': Platform.operatingSystemVersion,
    'logicalWidth': size.width / ratio,
    'logicalHeight': size.height / ratio,
    'devicePixelRatio': ratio,
    'viewportSource': 'native-view-unmodified',
    'dateUtc': DateTime.now().toUtc().toIso8601String(),
    'sourceSha': const String.fromEnvironment('UBAA_UI_SOURCE_SHA'),
  });
  if (Platform.isIOS) {
    await binding.takeScreenshot(name);
  } else {
    debugPrint('原生首页检查点：$name');
  }
}
