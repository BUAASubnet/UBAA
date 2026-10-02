import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cn.edu.buaa.ubaa/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('Android 空环境从原生私有目录启动，不依赖 HOME', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'paths.config');
      return '/data/user/0/synthetic.app/no_backup/UBAA';
    });
    final directory = PrivateConfigDirectory(
      environment: {},
      operatingSystem: 'android',
    );
    await directory.initialize();
    expect(directory.resolve(), '/data/user/0/synthetic.app/no_backup/UBAA');
  });

  test('iOS 空环境从原生私有目录启动，不需要 HOME', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'paths.config');
      expect(call.arguments, isNull);
      calls++;
      return '/private/fixture-container/Library/Application Support/UBAA';
    });
    final directory = PrivateConfigDirectory(
      environment: {},
      operatingSystem: 'ios',
    );
    await directory.initialize();
    expect(
      directory.resolve(),
      '/private/fixture-container/Library/Application Support/UBAA',
    );
    await directory.initialize();
    expect(calls, 1);
  });

  test('原生路径缺失或相对时不能改用公共目录', () async {
    for (final value in [null, '', 'relative/UBAA']) {
      messenger.setMockMethodCallHandler(channel, (_) async => value);
      final directory = PrivateConfigDirectory(
        environment: {},
        operatingSystem: 'ios',
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
