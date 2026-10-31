import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../support/host/fakes.dart' show fixtureCapabilities;

void _registerBootstrapTests() {
  test('共享 bootstrap 严格按初始化顺序启动同一宿主', () async {
    final events = <String>[];
    final vault = MemoryCredentialVault();
    final picker = MemoryPhotoPicker();
    final permissions = MemoryPermissionGateway();
    final locations = MemoryLocationProvider();
    Widget? launched;

    await bootstrapUbaaHost(
      readThemeMode: () async => ThemeMode.system,
      ensureFlutterInitialized: () => events.add('binding'),
      initializeSdk: () async {
        events.add('sdk:start');
        await Future<void>.delayed(Duration.zero);
        events.add('sdk:end');
      },
      debugHello: () {
        events.add('hello');
        return 'UBAA FRB 2.13.0 ready';
      },
      createCapabilities: () async {
        events.add('capabilities:start');
        await Future<void>.delayed(Duration.zero);
        events.add('capabilities:end');
        return PlatformCapabilities(
          credentialVault: vault,
          photoPicker: picker,
          permissionGateway: permissions,
          locationProvider: locations,
        );
      },
      runApplication: (app) {
        events.add(app is UbaaAppHost ? 'host' : 'splash');
        launched = app;
      },
    );

    expect(events, <String>[
      'binding',
      'splash',
      'sdk:start',
      'sdk:end',
      'hello',
      'capabilities:start',
      'capabilities:end',
      'host',
    ]);
    final host = launched! as UbaaAppHost;
    expect(host.credentialVault, same(vault));
    expect(host.photoPicker, same(picker));
    expect(host.permissionGateway, same(permissions));
    expect(host.locationProvider, same(locations));
  });

  test('SDK 初始化失败时不探测 hello、不创建能力并向上传播', () async {
    final events = <String>[];
    final failure = StateError('脱敏 SDK 初始化失败');

    await expectLater(
      bootstrapUbaaHost(
        readThemeMode: () async => ThemeMode.system,
        ensureFlutterInitialized: () => events.add('binding'),
        initializeSdk: () async {
          events.add('sdk');
          throw failure;
        },
        debugHello: () {
          events.add('hello');
          return 'UBAA FRB 2.13.0 ready';
        },
        createCapabilities: () async {
          events.add('capabilities');
          return fixtureCapabilities();
        },
        runApplication: (_) => events.add('runApp'),
      ),
      throwsA(same(failure)),
    );
    expect(events, <String>['binding', 'runApp', 'sdk', 'runApp']);
  });

  test('debug hello 失败时不创建能力并向上传播', () async {
    final events = <String>[];

    await expectLater(
      bootstrapUbaaHost(
        readThemeMode: () async => ThemeMode.system,
        ensureFlutterInitialized: () => events.add('binding'),
        initializeSdk: () async => events.add('sdk'),
        debugHello: () {
          events.add('hello');
          return 'unexpected';
        },
        createCapabilities: () async {
          events.add('capabilities');
          return fixtureCapabilities();
        },
        runApplication: (_) => events.add('runApp'),
      ),
      throwsA(isA<AssertionError>()),
    );
    expect(events, <String>['binding', 'runApp', 'sdk', 'hello', 'runApp']);
  });
}

void main() {
  _registerBootstrapTests();
  testWidgets('SDK 等待期间启动页可绘制，完成后才装配宿主', (tester) async {
    final gate = Completer<void>();
    Widget? current;
    var capabilities = 0;
    final pending = bootstrapUbaaHost(
      readThemeMode: () async => ThemeMode.system,
      ensureFlutterInitialized: () {},
      initializeSdk: () => gate.future,
      debugHello: () => 'UBAA FRB 2.13.0 ready',
      createCapabilities: () async {
        capabilities++;
        return fixtureCapabilities();
      },
      runApplication: (app) => current = app,
    );
    await tester.pump();
    await tester.pumpWidget(current!);
    expect(find.byType(UbaaSplashView), findsOneWidget);
    expect(capabilities, 0);
    gate.complete();
    await pending;
    expect(current, isA<UbaaAppHost>());
    expect(capabilities, 1);
  });
  for (final phase in ['SDK 初始化', 'Bridge 自检', '平台能力初始化']) {
    testWidgets('$phase 失败有安全诊断和重启指引，保留原始错误', (tester) async {
      final failure = StateError('/private/secret=fixture');
      final apps = <Widget>[];
      await expectLater(
        bootstrapUbaaHost(
          readThemeMode: () async => ThemeMode.system,
          ensureFlutterInitialized: () {},
          initializeSdk: () async {
            if (phase == 'SDK 初始化') throw failure;
          },
          debugHello: () {
            if (phase == 'Bridge 自检') throw failure;
            return 'UBAA FRB 2.13.0 ready';
          },
          createCapabilities: () async {
            if (phase == '平台能力初始化') throw failure;
            return fixtureCapabilities();
          },
          runApplication: apps.add,
        ),
        throwsA(same(failure)),
      );
      await tester.pumpWidget(apps.last);
      expect(find.text('请关闭应用后重新打开。'), findsOneWidget);
      expect(find.textContaining('诊断编号：UBAA-'), findsOneWidget);
      expect(find.text('失败阶段：$phase'), findsOneWidget);
      expect(find.textContaining('/private'), findsNothing);
      expect(apps.whereType<UbaaAppHost>(), isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
