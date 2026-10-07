import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS 各构建配置保留沙箱并允许主动联网', () {
    for (final configuration in ['DebugProfile', 'Release']) {
      final result = Process.runSync('/usr/bin/plutil', [
        '-convert',
        'json',
        '-o',
        '-',
        'macos/Runner/$configuration.entitlements',
      ]);
      expect(result.exitCode, 0, reason: '$configuration 权限文件必须可解析');
      final entitlements = jsonDecode(result.stdout as String) as Map;
      expect(
        entitlements['com.apple.security.app-sandbox'],
        isTrue,
        reason: '$configuration 必须保留 App Sandbox',
      );
      expect(
        entitlements['com.apple.security.network.client'],
        isTrue,
        reason: '$configuration 必须允许主动连接学校服务',
      );
    }
  }, skip: !Platform.isMacOS);
}
