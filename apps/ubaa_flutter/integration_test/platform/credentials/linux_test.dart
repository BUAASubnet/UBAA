import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Linux 真实安全存储会话可用性与合成材料闭环', (tester) async {
    const expected = bool.fromEnvironment('UBAA_SECURE_STORAGE_AVAILABLE');
    final materials = SecureMaterialStore();
    await materials.probe().timeout(const Duration(seconds: 15));
    expect(materials.isAvailable, expected);
    final key = 'linux-test-${DateTime.now().microsecondsSinceEpoch}';
    if (!expected) {
      await expectLater(
        materials.write(key, 'synthetic-value'),
        throwsA(isA<SecureMaterialException>()),
      );
      return;
    }
    try {
      await materials.write(key, 'synthetic-value');
      final reopened = SecureMaterialStore();
      await reopened.probe();
      expect(await reopened.read(key), 'synthetic-value');
      await reopened.delete(key);
      expect(await materials.read(key), isNull);
    } finally {
      await materials.delete(key);
    }
  }, skip: !Platform.isLinux);
}
