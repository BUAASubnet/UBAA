import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cn.edu.buaa.ubaa/private-paths');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('Android 空环境从原生私有目录启动，不依赖 HOME', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'configDirectory');
      return '/data/user/0/synthetic.app/no_backup/UBAA';
    });
    final directory = PrivateConfigDirectory(
      environment: {},
      operatingSystem: 'android',
    );
    await directory.initialize();
    expect(directory.resolve(), '/data/user/0/synthetic.app/no_backup/UBAA');
  });

  test('五端和OHOS目录由插件取得，不依赖 HOME，重复初始化只读取一次', () async {
    for (final os in ['ios', 'macos', 'linux', 'windows', 'ohos']) {
      var calls = 0;
      final directory = PrivateConfigDirectory(
        environment: {},
        operatingSystem: os,
        supportDirectory: () async {
          calls++;
          return Directory('/synthetic/app-support');
        },
      );
      await directory.initialize();
      await directory.initialize();
      expect(directory.resolve(), '/synthetic/app-support/UBAA');
      expect(calls, 1);
    }
  });
  test('插件失败或相对目录不退回公共目录', () async {
    for (final fail in [false, true]) {
      final directory = PrivateConfigDirectory(
        environment: {},
        operatingSystem: 'ios',
        supportDirectory: () async {
          if (fail) throw StateError('合成失败');
          return Directory('relative');
        },
      );
      await expectLater(
        directory.initialize(),
        throwsA(isA<FileSystemException>()),
      );
      expect(directory.resolve, throwsA(isA<FileSystemException>()));
    }
  });

  test('显式绝对目录优先，且相对配置不能被原生成功掩盖', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return '/private/fixture-container/UBAA';
    });
    final configured = PrivateConfigDirectory(
      environment: {'UBAA_CONFIG_DIR': '/private/fixture-run'},
      operatingSystem: 'ios',
    );
    await configured.initialize();
    expect(configured.resolve(), '/private/fixture-run');
    final invalid = PrivateConfigDirectory(
      environment: {'UBAA_CONFIG_DIR': 'relative'},
      operatingSystem: 'ios',
    );
    await expectLater(
      invalid.initialize(),
      throwsA(isA<FileSystemException>()),
    );
    expect(calls, 0);
  });
}
