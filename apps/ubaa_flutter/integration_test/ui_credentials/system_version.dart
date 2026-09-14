import 'dart:io';

import 'package:ubaa_platform/ubaa_platform.dart';

/// 从系统自带工具独立取得版本，不以待测的照片 capability 推导期望。
Future<String> readMacOSProductVersion() async {
  final result = await Process.run(
    '/usr/bin/sw_vers',
    const <String>['-productVersion'],
    environment: const <String, String>{'SYSTEM_VERSION_COMPAT': '0'},
  );
  if (result.exitCode != 0) throw StateError('无法取得 macOS 系统版本');
  return (result.stdout as String).trim();
}

({bool available, PlatformPermissionStatus permission})
photoExpectationForMacOS(String productVersion) {
  final version = RegExp(
    r'^(\d+)\.(\d+)(?:\.\d+)?$',
  ).firstMatch(productVersion);
  if (version == null) throw const FormatException('macOS 系统版本格式无效');
  final available = int.parse(version.group(1)!) >= 11;
  return (
    available: available,
    permission: available
        ? PlatformPermissionStatus.granted
        : PlatformPermissionStatus.unavailable,
  );
}
