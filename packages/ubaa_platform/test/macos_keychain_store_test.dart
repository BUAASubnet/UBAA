import 'dart:io';

import 'package:test/test.dart';

void main() {
  for (final nativeTest in <String, String>{
    'macOS 原生凭据边界在注入系统调用下保持精确寻址与稳定失败': 'macos_keychain_credential_test.swift',
    'macOS legacy 交互策略在所有返回路径恢复且跨实例同步': 'macos_keychain_interaction_test.swift',
  }.entries) {
    test(
      nativeTest.key,
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ubaa-keychain-contract-',
        );
        try {
          final executable = '${directory.path}/credential-test';
          final compile = await Process.run('xcrun', <String>[
            'swiftc',
            'native/macos/KeychainCredentialStore.swift',
            'native/macos/LegacyKeychainAPI.swift',
            'test/native/${nativeTest.value}',
            '-o',
            executable,
          ]);
          expect(
            compile.exitCode,
            0,
            reason: '${compile.stdout}\n${compile.stderr}',
          );
          final check = await Process.run(executable, const <String>[]);
          expect(check.exitCode, 0, reason: '${check.stdout}\n${check.stderr}');
        } finally {
          await directory.delete(recursive: true);
        }
      },
      skip: !Platform.isMacOS,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
