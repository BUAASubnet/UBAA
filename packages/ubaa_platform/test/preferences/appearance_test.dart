import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cn.edu.buaa.ubaa/appearance');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('默认只在 Android 发出原生调用，禁用时始终不调用', () async {
    await NativeThemeSync().apply('dark');
    expect(calls.length, Platform.isAndroid ? 1 : 0);
    calls.clear();
    await NativeThemeSync(enabled: false).apply('dark');
    expect(calls, isEmpty);
  });
  test('启用时按顺序发送三个主题值', () async {
    final sync = NativeThemeSync(enabled: true);
    for (final mode in ['dark', 'light', 'system']) {
      await sync.apply(mode);
    }
    expect(calls.map((call) => call.method), everyElement('setThemeMode'));
    expect(calls.map((call) => call.arguments), ['dark', 'light', 'system']);
  });
  test('插件缺失和平台异常均不打断主题切换', () async {
    final sync = NativeThemeSync(enabled: true);
    messenger.setMockMethodCallHandler(channel, null);
    await sync.apply('dark');
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'unavailable'),
    );
    await sync.apply('light');
  });
}
