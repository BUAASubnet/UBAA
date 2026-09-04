import 'package:test/test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('平台坐标只接受有限且位于经纬度范围内的数值', () {
    final location = PlatformLocation(lat: 39.9, lng: 116.3);

    expect(location.lat, 39.9);
    expect(location.lng, 116.3);
    expect(location.toString(), isNot(contains('39.9')));
    expect(location.toString(), isNot(contains('116.3')));
    expect(PlatformLocation(lat: -90, lng: -180).lat, -90);
    expect(PlatformLocation(lat: 90, lng: 180).lng, 180);
    expect(
      () => PlatformLocation(lat: double.nan, lng: 116.3),
      throwsArgumentError,
    );
    expect(() => PlatformLocation(lat: 91, lng: 116.3), throwsArgumentError);
    expect(() => PlatformLocation(lat: -91, lng: 116.3), throwsArgumentError);
    expect(
      () => PlatformLocation(lat: 39.9, lng: double.infinity),
      throwsArgumentError,
    );
    expect(() => PlatformLocation(lat: 39.9, lng: -181), throwsArgumentError);
    expect(() => PlatformLocation(lat: 39.9, lng: 181), throwsArgumentError);
  });

  test('位置权限包装器拒绝时不读取位置，允许后只返回 typed 坐标', () async {
    final permissions = MemoryPermissionGateway(
      initial: <PlatformPermission, PlatformPermissionStatus>{
        PlatformPermission.foregroundLocation: PlatformPermissionStatus.denied,
      },
    );
    final provider = MemoryLocationProvider(
      location: PlatformLocation(lat: 39.9, lng: 116.3),
    );
    final guarded = PermissionedLocationProvider(
      permissions: permissions,
      provider: provider,
    );

    await expectLater(
      guarded.currentLocation(),
      throwsA(
        isA<PlatformCapabilityException>().having(
          (error) => error.status,
          'status',
          PlatformPermissionStatus.denied,
        ),
      ),
    );
    expect(provider.requestCount, 0);

    permissions.setStatus(
      PlatformPermission.foregroundLocation,
      PlatformPermissionStatus.granted,
    );
    final location = await guarded.currentLocation();
    expect(location?.lat, 39.9);
    expect(location?.lng, 116.3);
    expect(provider.requestCount, 1);
    expect(permissions.requests, <PlatformPermission>[
      PlatformPermission.foregroundLocation,
      PlatformPermission.foregroundLocation,
    ]);
  });

  test('位置权限包装器不透传权限网关的路径或令牌异常', () async {
    final guarded = PermissionedLocationProvider(
      permissions: _ThrowingPermissionGateway(),
      provider: MemoryLocationProvider(
        location: PlatformLocation(lat: 39.9, lng: 116.3),
      ),
    );

    await expectLater(
      guarded.currentLocation(),
      throwsA(
        isA<PlatformCapabilityException>()
            .having(
              (error) => error.status,
              'status',
              PlatformPermissionStatus.unavailable,
            )
            .having(
              (error) => error.toString(),
              'safe message',
              allOf(isNot(contains('/private')), isNot(contains('token'))),
            ),
      ),
    );
  });

  test('不可用位置实现安全返回空值且不伪造坐标', () async {
    const provider = UnavailableLocationProvider();

    expect(provider.isAvailable, isFalse);
    expect(await provider.currentLocation(), isNull);
  });

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

  test('回调权限适配器隐藏异常并返回稳定不可用状态', () async {
    final gateway = CallbackPermissionGateway(
      request: (_) async => throw StateError('platform secret: token'),
    );
    expect(
      await gateway.request(PlatformPermission.photos),
      PlatformPermissionStatus.unavailable,
    );
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

  test('照片适配器可显式使用桌面文件权限', () async {
    final permissions = MemoryPermissionGateway(
      initial: <PlatformPermission, PlatformPermissionStatus>{
        PlatformPermission.files: PlatformPermissionStatus.granted,
      },
    );
    final picker = MemoryPhotoPicker(
      photo: const YgdkPhotoInput(
        bytes: <int>[7],
        fileName: 'desktop.jpg',
        mimeType: 'image/jpeg',
      ),
    );
    final guarded = PermissionedPhotoPicker(
      permissions: permissions,
      picker: picker,
      permission: PlatformPermission.files,
    );
    expect((await guarded.pickPhoto())?.fileName, 'desktop.jpg');
    expect(permissions.requests, <PlatformPermission>[
      PlatformPermission.files,
    ]);
  });

  test('回调照片适配器在平台异常时返回稳定能力错误', () async {
    final picker = CallbackPhotoPicker(
      pick: () async => throw StateError('private path'),
    );
    expect(
      picker.pickPhoto,
      throwsA(
        isA<PlatformCapabilityException>().having(
          (error) => error.status,
          'status',
          PlatformPermissionStatus.unavailable,
        ),
      ),
    );
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

final class _ThrowingPermissionGateway implements PlatformPermissionGateway {
  @override
  Future<PlatformPermissionStatus> request(
    PlatformPermission permission,
  ) async => throw StateError('/private/location token=secret');
}
