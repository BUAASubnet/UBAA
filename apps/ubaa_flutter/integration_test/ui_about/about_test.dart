import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../ui_coursework/backend.dart';

class _Information implements PlatformAppInformation {
  _Information(this.state);
  final String state;
  final links = <AppLink>[];
  int reads = 0;
  Completer<bool>? pending;
  @override
  Future<String?> version() async {
    reads++;
    if (state == 'system') return SystemAppInformation().version();
    if (state == 'version-error' && reads == 1) return null;
    return '0.1.0+1';
  }

  @override
  Future<bool> open(AppLink link) async {
    links.add(link);
    if (pending case final gate?) return gate.future;
    return state != 'open-error';
  }
}

Widget _app(PlatformAppInformation information) => UbaaFlutterApp(
  backend: CourseworkBackend()..signedIn = true,
  credentialVault: MemoryCredentialVault(),
  appInformation: information,
  initialTab: 1,
);

void main() {
  if (const bool.fromEnvironment('UBAA_UI_INSPECTION')) {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(_app(SystemAppInformation()));
    return;
  }
  WidgetController.hitTestWarningShouldBeFatal = true;
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, PlatformAppInformation info) async {
    await tester.pumpWidget(_app(info));
    await tester.pumpAndSettle();
    await tap(tester, find.byIcon(Icons.menu));
    await tap(tester, find.text('关于'));
  }

  for (final brightness in Brightness.values) {
    for (final state in [
      'normal',
      'version-error',
      'open-error',
      'pending',
      'long',
    ]) {
      testWidgets('关于原生 $state ${brightness.name}', (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        if (state == 'long') {
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        }
        final info = _Information(state);
        await open(tester, info);
        Future<void> shot(String scene, String steps) =>
            _shot(binding, tester, '${brightness.name}-$state-$scene', steps);
        expect(find.text('关于'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(NavigationBar), findsNothing);
        final card = find.ancestor(
          of: find.text('UBAA 应用'),
          matching: find.byType(Card),
        );
        expect(
          tester.getTopLeft(card).dy -
              tester.getBottomLeft(find.byType(AppBar)).dy,
          lessThanOrEqualTo(20),
          reason: '说明卡沿旧版紧随顶栏，不留下半屏空白',
        );
        await shot('about', '原生侧栏关于，单标题与旧说明卡，明暗及1.3字号');
        if (state == 'version-error') {
          expect(find.text('版本信息暂不可用'), findsOneWidget);
          await tap(tester, find.text('重新读取版本'));
          expect(info.reads, 2);
          expect(find.text('版本：0.1.0+1'), findsOneWidget);
          await shot('version-retry', '版本不可用不猜版本号，显式重试恢复');
        }
        if (state == 'pending') {
          info.pending = Completer<bool>();
          await tap(tester, find.text(AppLink.project.label));
          expect(
            tester
                .widget<TextButton>(
                  find.widgetWithText(TextButton, AppLink.project.label),
                )
                .onPressed,
            isNull,
          );
          await shot('opening', '外链打开中不重复请求');
          await tap(tester, find.byTooltip('返回'));
          info.pending!.complete(false);
          await tester.pumpAndSettle();
          expect(find.text('链接未能打开'), findsNothing);
        } else {
          for (final link in AppLink.values) {
            await tap(tester, find.text(link.label));
            if (state == 'open-error') {
              expect(find.text(link.url), findsOneWidget);
              await shot('failed-${link.name}', '打不开时显示准确公开地址与复制入口，不泄露平台原始错误');
              await tap(tester, find.text('关闭'));
            }
          }
          expect(info.links, AppLink.values);
          await tap(tester, find.byTooltip('返回'));
        }
        expect(find.text('UBAA 应用'), findsNothing);
        await shot('back', '返回原三导航功能列表，无学校写入');
      });
    }
  }
  testWidgets('关于读取当前原生安装包版本', (tester) async {
    await open(tester, _Information('system'));
    expect(find.text('版本：0.1.0+1'), findsOneWidget);
    await _shot(
      binding,
      tester,
      'system-version',
      '通过生产平台适配器读取当前安装包版本，业务backend仍为显式内存',
    );
  });
}

Future<void> _shot(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
  String steps,
) async {
  await tester.pump(const Duration(milliseconds: 300));
  expect(tester.takeException(), isNull);
  final size = tester.view.physicalSize, ratio = tester.view.devicePixelRatio;
  final rows =
      (binding.reportData ??= <String, dynamic>{}).putIfAbsent(
            'uiEvidence',
            () => <Object?>[],
          )
          as List;
  rows.add({
    'name': name,
    'steps': steps,
    'backend': 'synthetic-about',
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
    debugPrint('原生关于检查点：$name');
  }
}
