import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('官方 Flutter 入口按固定顺序委托共享宿主', () async {
    final events = <String>[];
    final capabilities = PlatformCapabilities(
      credentialVault: MemoryCredentialVault(),
      photoPicker: MemoryPhotoPicker(),
      permissionGateway: MemoryPermissionGateway(),
      locationProvider: const UnavailableLocationProvider(),
    );
    Widget? launchedApp;

    await bootstrapUbaaFlutterApp(
      ensureInitialized: () {
        events.add('ensureInitialized');
      },
      initializeRust: () async {
        events.add('RustLib.init');
      },
      debugHello: () {
        events.add('bridgeHello');
        return 'UBAA FRB 2.13.0 ready';
      },
      createCapabilities: () async {
        events.add('createCapabilities');
        return capabilities;
      },
      runApplication: (app) {
        events.add('runApp');
        launchedApp = app;
      },
    );

    expect(events, <String>[
      'ensureInitialized',
      'runApp',
      'RustLib.init',
      'bridgeHello',
      'createCapabilities',
      'runApp',
    ]);
    final host = launchedApp! as UbaaFlutterApp;
    expect(host.credentialVault, same(capabilities.credentialVault));
    expect(host.photoPicker, same(capabilities.photoPicker));
    expect(host.permissionGateway, same(capabilities.permissionGateway));
    expect(host.locationProvider, same(capabilities.locationProvider));
  });

  test('安全材料不可用时不把本地账号仓库接入宿主', () async {
    final materials = SecureMaterialStore(
      coordinator: _syntheticCoordinator(),
      transport: _UnavailableTransport(),
    );
    await materials.probe();
    expect(materials.isAvailable, isFalse);
    final capabilities = PlatformCapabilities(
      credentialVault: MemoryCredentialVault(),
      secureMaterials: materials,
      photoPicker: MemoryPhotoPicker(),
      permissionGateway: MemoryPermissionGateway(),
      locationProvider: const UnavailableLocationProvider(),
    );
    Widget? launchedApp;

    await bootstrapUbaaFlutterApp(
      ensureInitialized: () {},
      initializeRust: () async {},
      debugHello: () => 'UBAA FRB 2.13.0 ready',
      createCapabilities: () async => capabilities,
      runApplication: (app) => launchedApp = app,
    );

    expect((launchedApp! as UbaaFlutterApp).localAccountStore, isNull);
  });
}

final class _UnavailableTransport implements SecureMaterialTransport {
  Never _fail() => throw const SecureMaterialException();

  @override
  Future<String?> read(String key) async => _fail();

  @override
  Future<void> write(String key, String value) async => _fail();

  @override
  Future<void> delete(String key) async => _fail();
}

MaterialCoordinator _syntheticCoordinator() {
  final directory = Directory.systemTemp.createTempSync(
    'ubaa_synthetic_materials_',
  );
  // 普通异步用例已等待全部账号/材料操作，此时真实文件锁已释放。
  addTearDown(() => directory.delete(recursive: true));
  return MaterialCoordinator(directory: directory);
}
