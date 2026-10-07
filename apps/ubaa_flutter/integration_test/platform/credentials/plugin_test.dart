import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

import 'system_version.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('macOS 通用插件的真实凭据读写重开与清理', (tester) async {
    final materials = SecureMaterialStore();
    await materials.probe();
    expect(materials.isAvailable, isTrue);
    final first = MaterialCredentialStore(materials);
    final suffix =
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    final namespace = 'com.buaa.ubaa.credentials.test.$suffix';
    const original = Credential(
      username: 'synthetic-student',
      password: 'synthetic-secret',
    );
    const updated = Credential(
      username: 'synthetic-updated-student',
      password: 'synthetic-updated-secret',
      autoLogin: true,
    );

    try {
      expect(await first.read(namespace), isNull);
      await first.clear(namespace);
      await first.write(namespace, original);

      // 新建适配器重新查询系统存储，不能依赖 Dart 实例内缓存。
      final reopenedMaterials = SecureMaterialStore();
      await reopenedMaterials.probe();
      expect(reopenedMaterials.isAvailable, isTrue);
      final restored = MaterialCredentialStore(reopenedMaterials);
      expect(await restored.read(namespace), original);

      await restored.write(namespace, updated);
      expect(await first.read(namespace), updated);

      await expectLater(
        first.write(
          namespace,
          const Credential(username: '', password: 'fixture'),
        ),
        throwsA(isA<CredentialVaultException>()),
      );
      expect(await restored.read(namespace), updated);

      await first.clear(namespace);
      expect(await restored.read(namespace), isNull);
      await restored.clear(namespace);
    } finally {
      // 失败同样只清本次合成 namespace，不读写默认凭据或其他系统条目。
      await first.clear(namespace);
      expect(await first.read(namespace), isNull);
    }
  }, skip: !Platform.isMacOS);

  testWidgets('凭据接线保留原生照片能力与权限探测', (tester) async {
    final systemVersion = await readMacOSProductVersion();
    debugPrint('照片回归独立系统版本：$systemVersion');
    final expectation = photoExpectationForMacOS(systemVersion);
    final capabilities = await createDefaultPhotoCapabilities();
    final picker = capabilities.picker;
    expect(picker.isAvailable, expectation.available);
    expect(
      await capabilities.permissions.request(PlatformPermission.photos),
      expectation.permission,
    );
    // 不打开系统选择器，不读取照片或触发业务请求。
  }, skip: !Platform.isMacOS);
}
