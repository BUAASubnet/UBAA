import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

import '../integration_test/ui_credentials/system_version.dart';

void main() {
  test('macOS 10.15 照片不可用但不排除凭据测试', () {
    final expectation = photoExpectationForMacOS('10.15.7');
    expect(expectation.available, isFalse);
    expect(expectation.permission, PlatformPermissionStatus.unavailable);
  });

  test('macOS 11 及更新系统保留照片正向验收', () {
    for (final version in ['11.0', '11.7.10', '12.0', '26.6.2']) {
      final expectation = photoExpectationForMacOS(version);
      expect(expectation.available, isTrue);
      expect(expectation.permission, PlatformPermissionStatus.granted);
    }
  });

  test('缺失或格式错误的系统版本不能伪装成支持照片', () {
    for (final version in ['', 'unknown', 'Darwin 25', '11', '11.invalid']) {
      expect(
        () => photoExpectationForMacOS(version),
        throwsA(isA<FormatException>()),
      );
    }
  });
}
