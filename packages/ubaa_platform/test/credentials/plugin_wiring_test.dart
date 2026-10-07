import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('生产凭据与缓存材料共用插件，旧通道即使宣称可用也不得选中', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    const legacy = MethodChannel('cn.edu.buaa.ubaa/platform');
    const plugin = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(
      paths,
      (_) async => '/synthetic/app-support',
    );
    addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
    final values = <String, String>{};
    final legacyCalls = <String>[];
    messenger.setMockMethodCallHandler(legacy, (call) async {
      if (call.method.startsWith('credentials.')) {
        legacyCalls.add(call.method);
        if (call.method == 'credentials.capability') return true;
        throw PlatformException(code: 'credentials_unavailable');
      }
      return false;
    });
    messenger.setMockMethodCallHandler(plugin, (call) async {
      final args = call.arguments as Map<Object?, Object?>;
      final key = args['key']! as String;
      switch (call.method) {
        case 'write':
          values[key] = args['value']! as String;
        case 'read':
          return values[key];
        case 'delete':
          values.remove(key);
      }
      return null;
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(legacy, null);
      messenger.setMockMethodCallHandler(plugin, null);
    });
    final capabilities = await createDefaultPlatformCapabilities();
    expect(legacyCalls, isEmpty);
    expect(capabilities.credentialVault.isAvailable, isTrue);
    expect(await capabilities.credentialVault.read(), isNull);
    const credential = Credential(
      username: 'fixture-user',
      password: 'fixture-secret',
      autoLogin: false,
    );
    await capabilities.credentialVault.write(credential);
    expect(await capabilities.credentialVault.read(), credential);
    expect(values.keys.single, startsWith('ubaa.material.v2.credentials.'));
    expect(jsonDecode(values.values.single)['autoLogin'], false);
    await capabilities.secureMaterials!.write(
      'cache-key.fixture',
      'fixture-key',
    );
    await capabilities.credentialVault.clear();
    expect(await capabilities.credentialVault.read(), isNull);
    expect(
      await capabilities.secureMaterials!.read('cache-key.fixture'),
      'fixture-key',
    );
    expect(legacyCalls, isEmpty);
  });

  test('安全存储异常使用明确本机提示且诊断识别类型', () {
    const cause = CredentialVaultException(
      CredentialVaultErrorCode.storageFailure,
    );
    final error = const UiErrorMapper().fromException(cause);
    expect(error.title, '本机安全存储不可用');
    expect(error.message, contains('手动登录'));
    expect(error.message, isNot(contains('应用内部错误')));
    final diagnostics = LocalDiagnostics();
    diagnostics.record(
      operation: DiagnosticOperation.initialization,
      error: error,
      cause: cause,
    );
    expect(
      jsonDecode(diagnostics.exportText())['events'][0]['cause'],
      'credentialStorage',
    );
  });

  test('OHOS沿通用插件接口发送固定加密选项且禁止错误重置', () async {
    const plugin = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    const removed = MethodChannel('cn.edu.buaa.ubaa/secure-material');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(
      removed,
      (_) async => fail('不得调用已移除的宿主通道'),
    );
    messenger.setMockMethodCallHandler(plugin, (call) async {
      calls.add(call.method);
      final args = call.arguments as Map<Object?, Object?>;
      final options = args['options']! as Map<Object?, Object?>;
      expect(options['resetOnError'], 'false');
      expect(options['ohosStorageCipherAlgorithm'], 'AES_GCM_NoPadding');
      expect(
        options['ohosKeyCipherAlgorithm'],
        'RSA_ECB_OAEPwithSHA_256andMGF1Padding',
      );
      expect(args['key'], 'fixture-key');
      return call.method == 'read' ? 'fixture-value' : null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(plugin, null);
      messenger.setMockMethodCallHandler(removed, null);
    });
    const transport = PlatformSecureMaterialTransport(operatingSystem: 'ohos');
    await transport.write('fixture-key', 'fixture-value');
    expect(await transport.read('fixture-key'), 'fixture-value');
    await transport.delete('fixture-key');
    expect(calls, ['write', 'read', 'delete']);
  });
}
