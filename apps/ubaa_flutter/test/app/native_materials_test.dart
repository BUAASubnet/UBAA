import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ubaa_platform/shared_accounts.dart';

import '../support/platform/native_materials.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final targetExists in [false, true]) {
    test('原生测试隔离默认域B与备份，原target存在=$targetExists', () async {
      final root = await Directory.systemTemp.createTemp('ubaa_native_domain_');
      addTearDown(() => root.delete(recursive: true));
      final defaults = Directory('${root.path}/synthetic-default');
      await defaults.create();
      final state = File('${defaults.path}/transaction.v1');
      await state.writeAsString('UBAA1:B');
      final backup = File('${defaults.path}/old.previous');
      final old = Uint8List.fromList([
        1,
        ...utf8.encode(jsonEncode({'old-alias': 'old-key'})),
      ]);
      await backup.writeAsBytes(old);
      final target = File('${defaults.path}/synthetic-materials.dat');
      if (targetExists) await target.writeAsBytes(old);
      var defaultCalls = 0;
      final materials = await createNativeTestMaterials(
        domain: Directory('${root.path}/private'),
        operatingSystem: 'windows',
        windowsCodec: const _Codec(),
        windowsReplace: (pending, target) async {
          await pending.rename(target.path);
        },
        nativeTransport: () {
          defaultCalls++;
          return WindowsFileMaterials(
            file: () async => target,
            codec: const _Codec(),
          );
        },
      );
      await materials.probe();
      if (targetExists) {
        expect(await target.readAsBytes(), old);
      } else {
        expect(await target.exists(), isFalse);
      }
      expect(defaultCalls, 0);
      expect(materials.isAvailable, isTrue);
      await materials.write('fixture-private', 'synthetic-private');
      final reopened = await createNativeTestMaterials(
        domain: Directory('${root.path}/private'),
        operatingSystem: 'windows',
        windowsCodec: const _Codec(),
        windowsReplace: (pending, target) async {
          await pending.rename(target.path);
        },
      );
      await reopened.probe();
      expect(await reopened.read('fixture-private'), 'synthetic-private');
      await reopened.delete('fixture-private');
      expect(await materials.read('fixture-private'), isNull);
      if (targetExists) {
        expect(await target.readAsBytes(), old);
      } else {
        expect(await target.exists(), isFalse);
      }
      expect(await backup.readAsBytes(), old);
      expect(await state.readAsString(), 'UBAA1:B');
    });
  }
  for (final packageName in ['cn.edu.ubaa', '', 'cn.edu.ubaa.synthetic']) {
    test('Android拒绝未隔离包名=$packageName且默认配置和key不变', () async {
      _packageIdentity(packageName);
      final root = await Directory.systemTemp.createTemp('ubaa_android_guard_');
      addTearDown(() => root.delete(recursive: true));
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      // 模拟锁定插件的固定配置、包装key与按包名分配的alias，不访问设备。
      final defaults = <String, String>{
        'FlutterSecureStorageConfiguration': 'synthetic-no-algorithm-marker',
        'FlutterSecureKeyStorage': 'synthetic-wrapped-key',
        'cn.edu.ubaa.keystore-alias': 'synthetic-alias',
      };
      final before = Map<String, String>.of(defaults);
      var pluginCalls = 0;
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            pluginCalls++;
            defaults['FlutterSecureStorageConfiguration'] = 'algorithm-written';
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      try {
        final materials = await Future.sync(
          () => createNativeTestMaterials(
            domain: root,
            operatingSystem: 'android',
          ),
        );
        await materials.probe();
      } on StateError {
        // 允许在创建辅助对象时直接拒绝未隔离环境。
      }
      expect(pluginCalls, 0);
      expect(defaults, before);
    });
  }
  test('Android独立包身份通过后插件Mock通道可写读重开删除', () async {
    _packageIdentity('cn.edu.ubaa.synthetic.materials');
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final root = await Directory.systemTemp.createTemp('ubaa_android_private_');
    addTearDown(() => root.delete(recursive: true));
    final values = <String, String>{};
    var calls = 0;
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls++;
          final args = Map<String, Object?>.from(call.arguments as Map);
          final key = args['key']! as String;
          final options = Map<String, Object?>.from(args['options']! as Map);
          expect(options['storageNamespace'], startsWith('ubaa.synthetic.'));
          expect(options['resetOnError'], 'true');
          expect(options['migrateOnAlgorithmChange'], 'true');
          switch (call.method) {
            case 'write':
              values[key] = args['value']! as String;
            case 'read':
              return values[key];
            case 'delete':
              values.remove(key);
            default:
              throw StateError('非预期材料调用');
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final first = await createNativeTestMaterials(
      domain: root,
      operatingSystem: 'android',
    );
    await first.probe();
    expect(first.isAvailable, isTrue);
    await first.write('fixture', 'synthetic');
    final reopened = await createNativeTestMaterials(
      domain: root,
      operatingSystem: 'android',
    );
    await reopened.probe();
    expect(await reopened.read('fixture'), 'synthetic');
    await reopened.delete('fixture');
    expect(await first.read('fixture'), isNull);
    expect(values, isEmpty);
    expect(calls, greaterThan(0));
  });
  test('通用原生测试入口在Linux缺少专用隔离会话时零传输调用', () async {
    final root = await Directory.systemTemp.createTemp('ubaa_native_guard_');
    addTearDown(() => root.delete(recursive: true));
    var calls = 0;
    await expectLater(
      createNativeTestMaterials(
        domain: root,
        operatingSystem: 'linux',
        nativeTransport: () {
          calls++;
          throw StateError('不得访问默认会话');
        },
      ),
      throwsStateError,
    );
    expect(calls, 0);
  });
}

class _Codec implements WindowsMaterialCodec {
  const _Codec();
  @override
  Uint8List decrypt(Uint8List bytes) => Uint8List.fromList(bytes.sublist(1));
  @override
  Uint8List encrypt(Uint8List bytes) => Uint8List.fromList([1, ...bytes]);
}

void _packageIdentity(String name) {
  PackageInfo.setMockInitialValues(
    appName: 'synthetic',
    packageName: name,
    version: '1',
    buildNumber: '1',
    buildSignature: 'synthetic',
  );
}
