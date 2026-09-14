import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cn.edu.buaa.ubaa/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('原生拍照探测独立于相册能力', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'photo.capability') return true;
      if (call.method == 'photo.captureCapability') return true;
      throw MissingPluginException();
    });
    final picker = MethodChannelPhotoPicker(channel: channel);
    await picker.probe();
    expect(picker.canCapturePhoto, isTrue);
  });

  test('不支持拍照的宿主仍可选图且不会调用相机', () async {
    var captureCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'photo.capability') return true;
      if (call.method == 'photo.capture') captureCalls++;
      throw MissingPluginException();
    });
    final picker = MethodChannelPhotoPicker(channel: channel);
    expect(await picker.probe(), isTrue);
    expect(picker.canCapturePhoto, isFalse);
    expect(await picker.capturePhoto(), isNull);
    expect(captureCalls, 0);
  });

  test('拍照请求独立权限且取消不伪造照片', () async {
    var captureCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method.endsWith('Capability') ||
          call.method == 'photo.capability')
        return true;
      if (call.method == 'photo.capture') captureCalls++;
      return null;
    });
    final raw = MethodChannelPhotoPicker(channel: channel);
    await raw.probe();
    final permissions = MemoryPermissionGateway();
    final picker = PermissionedPhotoPicker(
      permissions: permissions,
      picker: raw,
    );
    await expectLater(
      picker.capturePhoto(),
      throwsA(
        isA<PlatformCapabilityException>().having(
          (e) => e.permission,
          '相机权限',
          PlatformPermission.camera,
        ),
      ),
    );
    expect(captureCalls, 0);
    permissions.setStatus(
      PlatformPermission.camera,
      PlatformPermissionStatus.granted,
    );
    expect(await picker.capturePhoto(), isNull);
    expect(captureCalls, 1);
    expect(permissions.requests, [
      PlatformPermission.camera,
      PlatformPermission.camera,
    ]);
  });

  test('拍照复制字节并拒绝路径、超限及原生错误', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    Object? payload = {
      'bytes': bytes,
      'fileName': 'camera.jpg',
      'mimeType': 'image/jpeg',
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method.endsWith('Capability') ||
          call.method == 'photo.capability')
        return true;
      if (payload is PlatformException) throw payload;
      return payload;
    });
    final picker = MethodChannelPhotoPicker(channel: channel);
    await picker.probe();
    final photo = await picker.capturePhoto();
    bytes[0] = 9;
    expect(photo!.bytes, [1, 2, 3]);
    for (final invalid in [
      {
        'bytes': [1],
        'fileName': '/private/camera.jpg',
        'mimeType': 'image/jpeg',
      },
      {
        'bytes': Uint8List(MethodChannelPhotoPicker.maxPhotoBytes + 1),
        'fileName': 'camera.jpg',
        'mimeType': 'image/jpeg',
      },
      PlatformException(code: 'raw', message: '合成敏感路径'),
    ]) {
      payload = invalid;
      await expectLater(
        picker.capturePhoto(),
        throwsA(
          isA<PlatformCapabilityException>().having(
            (e) => e.toString(),
            '不泄露原始错误',
            isNot(contains('合成敏感路径')),
          ),
        ),
      );
    }
  });
}
