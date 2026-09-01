import 'package:test/test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('无原生权限实现安全拒绝，不伪造授权', () async {
    const gateway = UnavailablePermissionGateway();
    expect(
      await gateway.request(PlatformPermission.photos),
      PlatformPermissionStatus.unavailable,
    );
  });

  test('内存权限实现记录申请并允许测试切换结果', () async {
    final gateway = MemoryPermissionGateway(
      initial: <PlatformPermission, PlatformPermissionStatus>{
        PlatformPermission.photos: PlatformPermissionStatus.denied,
      },
    );
    expect(
      await gateway.request(PlatformPermission.photos),
      PlatformPermissionStatus.denied,
    );
    gateway.setStatus(
      PlatformPermission.photos,
      PlatformPermissionStatus.granted,
    );
    expect(
      await gateway.request(PlatformPermission.photos),
      PlatformPermissionStatus.granted,
    );
    expect(gateway.requests, <PlatformPermission>[
      PlatformPermission.photos,
      PlatformPermission.photos,
    ]);
  });

  test('照片选择器只返回 typed 内存输入，不持久化原始路径', () async {
    final picker = MemoryPhotoPicker(
      photo: const YgdkPhotoInput(
        bytes: <int>[1, 2, 3],
        fileName: 'fixture.jpg',
        mimeType: 'image/jpeg',
      ),
    );
    expect(picker.isAvailable, isTrue);
    expect((await picker.pickPhoto())?.fileName, 'fixture.jpg');
    expect(picker.pickCount, 1);
    const unavailable = UnavailablePhotoPicker();
    expect(unavailable.isAvailable, isFalse);
    expect(await unavailable.pickPhoto(), isNull);
  });

  test('照片选择器在权限拒绝时不调用原生 picker', () async {
    final permissions = MemoryPermissionGateway(
      initial: <PlatformPermission, PlatformPermissionStatus>{
        PlatformPermission.photos: PlatformPermissionStatus.denied,
      },
    );
    final picker = MemoryPhotoPicker(
      photo: const YgdkPhotoInput(
        bytes: <int>[9],
        fileName: 'blocked.jpg',
        mimeType: 'image/jpeg',
      ),
    );
    final guarded = PermissionedPhotoPicker(
      permissions: permissions,
      picker: picker,
    );
    await expectLater(
      guarded.pickPhoto(),
      throwsA(
        isA<PlatformCapabilityException>().having(
          (error) => error.status,
          'status',
          PlatformPermissionStatus.denied,
        ),
      ),
    );
    expect(picker.pickCount, 0);
    permissions.setStatus(
      PlatformPermission.photos,
      PlatformPermissionStatus.granted,
    );
    expect((await guarded.pickPhoto())?.fileName, 'blocked.jpg');
    expect(picker.pickCount, 1);
  });

  test('内存凭据保险箱支持单账号覆盖和清除', () async {
    final vault = MemoryCredentialVault();
    expect(await vault.read(), isNull);
    await vault.write(const StoredCredential(username: 'u1', password: 'p1'));
    expect((await vault.read())?.username, 'u1');
    await vault.write(const StoredCredential(username: 'u2', password: 'p2'));
    expect((await vault.read())?.username, 'u2');
    await vault.clear();
    expect(await vault.read(), isNull);
  });

  test('遥测关闭时不缓存事件，开启后仅缓存白名单字段', () async {
    final telemetry = InMemoryTelemetryClient();
    await telemetry.recordAppOpen();
    expect(telemetry.events, isEmpty);
    await telemetry.setEnabled(true);
    await telemetry.recordFeatureUsed(
      FeatureId.schedule,
      outcome: TelemetryOutcome.success,
      latency: const Duration(milliseconds: 100),
    );
    expect(telemetry.events.single.properties['feature'], 'schedule');
    expect(telemetry.events.single.properties.containsKey('password'), isFalse);
    await telemetry.setEnabled(false);
    expect(telemetry.events, isEmpty);
  });
}
