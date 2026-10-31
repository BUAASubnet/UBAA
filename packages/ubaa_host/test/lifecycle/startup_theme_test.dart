import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/ubaa_test_support.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

import '../support/host/fakes.dart' show fixtureCapabilities;

Future<void> _bootstrap(
  Future<ThemeMode> Function() read,
  void Function(Widget) launch, {
  Future<void> Function()? initialize,
}) => bootstrapUbaaHost(
  ensureFlutterInitialized: () {},
  readThemeMode: read,
  initializeSdk: initialize ?? () async {},
  debugHello: () => 'UBAA FRB 2.13.0 ready',
  createCapabilities: () async => fixtureCapabilities(),
  runApplication: launch,
);

void main() {
  testWidgets('保存深色时启动页、宿主等待页和登录首帧使用深色', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final preferences = MemoryPreferenceValues();
    final store = ThemePreferenceStore(values: preferences);
    await store.write('dark');
    final apps = <Widget>[];
    await _bootstrap(
      () async => ThemeMode.values.byName(await store.read()),
      apps.add,
    );
    await tester.pumpWidget(apps.first);
    expect(
      Theme.of(tester.element(find.byType(UbaaSplashView))).brightness,
      Brightness.dark,
    );
    final host = apps.last as UbaaAppHost;
    expect(host.initialThemeMode, ThemeMode.dark);
    final backend = Completer<DemoBackend>();
    await tester.pumpWidget(
      UbaaAppHost(
        initialThemeMode: host.initialThemeMode,
        preferenceValues: preferences,
        backendFactory: () => backend.future,
        credentialVault: MemoryCredentialVault(),
      ),
    );
    expect(
      Theme.of(tester.element(find.byType(UbaaSplashView))).brightness,
      Brightness.dark,
    );
    backend.complete(DemoBackend());
    await tester.pump();
    expect(
      Theme.of(tester.element(find.byType(UbaaLoginView))).brightness,
      Brightness.dark,
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });

  testWidgets('偏好挂起至300毫秒回落系统主题，迟到结果不改写启动状态', (tester) async {
    final read = Completer<ThemeMode>();
    final apps = <Widget>[];
    var initialized = false;
    final pending = _bootstrap(
      () => read.future,
      apps.add,
      initialize: () async {
        initialized = true;
      },
    );
    await tester.pump(const Duration(milliseconds: 299));
    expect(apps, isEmpty);
    expect(initialized, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    expect(apps.firstOrNull, isA<UbaaBootSplash>());
    expect((apps.first as UbaaBootSplash).themeMode, ThemeMode.system);
    await pending;
    read.complete(ThemeMode.dark);
    await tester.pump();
    expect((apps.last as UbaaAppHost).initialThemeMode, ThemeMode.system);
  });

  for (final synchronous in [false, true]) {
    testWidgets('偏好${synchronous ? '同步' : '异步'}失败仍启动系统主题', (tester) async {
      final apps = <Widget>[];
      await _bootstrap(() {
        if (synchronous) throw StateError('合成读取失败');
        return Future.error(StateError('合成读取失败'));
      }, apps.add);
      expect((apps.first as UbaaBootSplash).themeMode, ThemeMode.system);
      expect((apps.last as UbaaAppHost).initialThemeMode, ThemeMode.system);
    });
  }

  testWidgets('初始化失败页保留保存的深色主题和原始错误', (tester) async {
    final apps = <Widget>[];
    final failure = StateError('合成初始化失败');
    await expectLater(
      _bootstrap(
        () async => ThemeMode.dark,
        apps.add,
        initialize: () async => throw failure,
      ),
      throwsA(same(failure)),
    );
    await tester.pumpWidget(apps.last);
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );
  });
}
