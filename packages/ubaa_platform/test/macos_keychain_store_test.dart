import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'macOS 原生凭据边界在注入系统调用下保持精确寻址与稳定失败',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ubaa-keychain-contract-',
      );
      try {
        final executable = '${directory.path}/credential-test';
        final compile = await Process.run('xcrun', <String>[
          'swiftc',
          'native/macos/KeychainCredentialStore.swift',
          'test/native/macos_keychain_credential_test.swift',
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
