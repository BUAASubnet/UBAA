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
      'RustLib.init',
      'bridgeHello',
      'createCapabilities',
      'runApp',
    ]);
    final host = launchedApp! as UbaaFlutterApp;
    expect(host.credentialVault, same(capabilities.credentialVault));
    expect(host.photoPicker, same(capabilities.photoPicker));
    expect(host.permissionGateway, same(capabilities.permissionGateway));
  });
}
