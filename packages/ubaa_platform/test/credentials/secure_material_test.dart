import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('macOS 原生层收到真实登录钥匙串参数且不创建数据保护访问控制', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      final arguments = call.arguments as Map<Object?, Object?>;
      final options = arguments['options'] as Map<Object?, Object?>;
      expect(options['useDataProtectionKeyChain'], 'false');
      expect(options.containsKey('accessibility'), isFalse);
      return null;
    });
    await const PlatformSecureMaterialTransport().read(
      'ubaa.material.v2.capability',
    );
  });

  test('凭据与缓存材料使用独立安全键且不进入错误文本', () async {
    final transport = _Transport();
    final store = SecureMaterialStore(transport: transport);
    await store.probe();
    expect(store.isAvailable, isTrue);
    final credentials = MaterialCredentialStore(store);
    await credentials.write(
      'com.buaa.ubaa.credentials.v1',
      const Credential(
        username: 'fixture-user',
        password: 'fixture-only',
        autoLogin: false,
      ),
    );
    final loaded = await credentials.read('com.buaa.ubaa.credentials.v1');
    expect(loaded?.autoLogin, isFalse);
    expect(loaded?.username, 'fixture-user');
    await store.write('cache-key.fixture', 'synthetic-key');
    await credentials.clear('com.buaa.ubaa.credentials.v1');
    expect(await store.read('cache-key.fixture'), 'synthetic-key');
    expect(await credentials.read('com.buaa.ubaa.credentials.v1'), isNull);
    transport.fail = true;
    try {
      await store.read('cache-key.fixture');
      fail('必须明确报告不可用');
    } on SecureMaterialException catch (error) {
      expect(error.toString(), isNot(contains('secret-native-error')));
    }
  });

  test('安全能力不可用不会退回明文或伪造成功', () async {
    final transport = _Transport()..fail = true;
    final store = SecureMaterialStore(transport: transport);
    await store.probe();
    expect(store.isAvailable, isFalse);
    await expectLater(
      store.write('cache-key.fixture', 'synthetic-key'),
      throwsA(isA<SecureMaterialException>()),
    );
    expect(transport.values, isEmpty);
  });

  test('只能读取但不能写入时不报告安全材料可用', () async {
    final store = SecureMaterialStore(transport: _ReadOnlyTransport());
    await store.probe();
    expect(store.isAvailable, isFalse);
  });

  test('损坏凭据不悄悄变成没有保存的密码', () async {
    final transport = _Transport();
    final store = SecureMaterialStore(transport: transport);
    await store.probe();
    await store.write('credentials.com.buaa.ubaa.credentials.v1', '{broken');
    await expectLater(
      MaterialCredentialStore(store).read('com.buaa.ubaa.credentials.v1'),
      throwsA(isA<CredentialVaultException>()),
    );
  });
}

class _Transport implements SecureMaterialTransport {
  final values = <String, String>{};
  bool fail = false;
  void check() {
    if (fail) throw StateError('secret-native-error');
  }

  @override
  Future<String?> read(String key) async {
    check();
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    check();
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    check();
    values.remove(key);
  }
}

final class _ReadOnlyTransport implements SecureMaterialTransport {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {
    throw StateError('write unavailable');
  }

  @override
  Future<void> delete(String key) async {}
}
