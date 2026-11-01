import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('最小工厂隔离图片与位置初始化，GUI沿用同一账号和缓存密钥', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    const materials = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    const photos = MethodChannel('plugins.flutter.io/image_picker');
    const permissions = MethodChannel(
      'flutter.baseflow.com/permissions/methods',
    );
    const location = MethodChannel('flutter.baseflow.com/geolocator');
    final values = <String, String>{};
    var photoCalls = 0, locationCalls = 0;
    messenger.setMockMethodCallHandler(
      paths,
      (_) async => '/synthetic/app-support',
    );
    messenger.setMockMethodCallHandler(materials, (call) async {
      final args = call.arguments as Map<Object?, Object?>;
      final key = args['key']! as String;
      switch (call.method) {
        case 'read':
          return values[key];
        case 'write':
          values[key] = args['value']! as String;
        case 'delete':
          values.remove(key);
      }
      return null;
    });
    messenger.setMockMethodCallHandler(photos, (call) async {
      expect(call.method, 'retrieve');
      photoCalls++;
      return null;
    });
    for (final channel in [permissions, location]) {
      messenger.setMockMethodCallHandler(channel, (_) async {
        locationCalls++;
        fail('初始化不得申请定位或权限');
      });
    }
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      for (final channel in [paths, materials, photos, permissions, location]) {
        messenger.setMockMethodCallHandler(channel, null);
      }
    });
    final minimal = await createDefaultSessionPlatformCapabilities();
    expect(photoCalls, 0);
    expect(locationCalls, 0);
    const saved = Credential(
      username: 'synthetic-user',
      password: 'synthetic-only',
      autoLogin: true,
    );
    await minimal.credentialVault.write(saved);
    final accounts = minimal.createAccountStore()!;
    final before = (await accounts.retain(
      saved.username,
      retainSession: true,
    )).account!;
    final key = await accounts.cacheKey(before);
    final gui = await createDefaultPlatformCapabilities();
    expect(photoCalls, 1);
    expect(locationCalls, 0);
    expect(gui.locationProvider.isAvailable, isFalse);
    expect(await gui.credentialVault.read(), saved);
    final reopened = SecureLocalAccountStore(gui.secureMaterials!);
    final after = (await reopened.read())!.account!;
    expect(after.id, before.id);
    expect(after.username, before.username);
    expect(await reopened.cacheKey(after), key);
    final again = (await reopened.retain(
      saved.username,
      retainSession: true,
    )).account!;
    expect(again.id, before.id);
    expect(await reopened.cacheKey(again), key);
  });
}
