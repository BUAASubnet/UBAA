import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('cn.edu.buaa.ubaa/platform'),
          null,
        );
  });

  test('MethodChannel 权限适配器把稳定状态映射为 typed 枚举', () async {
    final channel = const MethodChannel('cn.edu.buaa.ubaa/platform');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'permission.request');
          expect(call.arguments, 'photos');
          return 'granted';
        });

    final gateway = MethodChannelPermissionGateway(channel: channel);
    expect(
      await gateway.request(PlatformPermission.photos),
      PlatformPermissionStatus.granted,
    );
  });

  test('MethodChannel 位置适配器只接收有效坐标并丢弃额外敏感字段', () async {
    final channel = const MethodChannel('cn.edu.buaa.ubaa/platform');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'location.capability') return true;
          if (call.method == 'location.current') {
            return <String, Object?>{
              'lat': 39.9,
              'lng': 116.3,
              'path': '/private/location/cache',
              'token': 'sensitive-token',
            };
          }
          return null;
        });

    final provider = MethodChannelLocationProvider(channel: channel);
    expect(await provider.probe(), isTrue);
    final location = await provider.currentLocation();
    expect(location?.lat, 39.9);
    expect(location?.lng, 116.3);
    expect(location.toString(), isNot(contains('/private/location/cache')));
    expect(location.toString(), isNot(contains('sensitive-token')));
    expect(calls.map((call) => call.method), <String>[
      'location.capability',
      'location.current',
    ]);
  });

  test('MethodChannel 位置适配器拒绝越界和畸形坐标', () async {
    final channel = const MethodChannel('cn.edu.buaa.ubaa/platform');
    var response = <String, Object?>{'lat': 91, 'lng': 116.3};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'location.capability') return true;
          return response;
        });
    final provider = MethodChannelLocationProvider(channel: channel);

    expect(await provider.probe(), isTrue);
    expect(await provider.currentLocation(), isNull);
    response = <String, Object?>{'lat': '39.9', 'lng': 116.3};
    expect(await provider.currentLocation(), isNull);
  });

  test('MethodChannel 凭据适配器探测失败时保持不可用且不降级明文', () async {
    final channel = const MethodChannel('cn.edu.buaa.ubaa/platform');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'credentials.capability') return true;
          if (call.method == 'credentials.read') {
            return <String, Object?>{
              'username': 'student',
              'password': 'fixture-password',
              'autoLogin': true,
            };
          }
          return null;
        });

    final store = MethodChannelSecureCredentialStore(channel: channel);
    expect(await store.probe(), isTrue);
    final value = await store.read('com.buaa.ubaa.credentials.v1');
    expect(
      value,
      const Credential(
        username: 'student',
        password: 'fixture-password',
        autoLogin: true,
      ),
    );
    expect(store.isAvailable, isTrue);

    await store.write(
      'com.buaa.ubaa.credentials.v1',
      const Credential(
        username: 'student',
        password: 'fixture-password',
        autoLogin: true,
      ),
    );
    await store.clear('com.buaa.ubaa.credentials.v1');
    expect(calls[2].method, 'credentials.write');
    expect(calls[2].arguments, <String, Object?>{
      'namespace': 'com.buaa.ubaa.credentials.v1',
      'username': 'student',
      'password': 'fixture-password',
      'autoLogin': true,
    });
    expect(calls[3].method, 'credentials.clear');
    expect(calls[3].arguments, 'com.buaa.ubaa.credentials.v1');
  });

  test('MethodChannel 凭据适配器拒绝无效输入且不调用原生写入', () async {
    final channel = const MethodChannel('cn.edu.buaa.ubaa/platform');
    var writeCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'credentials.write') writeCalls++;
          return true;
        });

    final store = MethodChannelSecureCredentialStore(channel: channel);
    expect(
      () => store.write(
        'com.buaa.ubaa.credentials.v1',
        const Credential(username: '', password: 'fixture-password'),
      ),
      throwsA(isA<CredentialVaultException>()),
    );
    expect(writeCalls, 0);
  });

  test('MethodChannel 照片适配器在 10 MiB 边界立即复制原始字节', () async {
    final rawBytes = Uint8List(MethodChannelPhotoPicker.maxPhotoBytes);
    rawBytes[0] = 1;
    final channel = _DirectPhotoMethodChannel(<String, Object?>{
      'bytes': rawBytes,
      'fileName': 'fixture.jpg',
      'mimeType': 'image/jpeg',
    });

    final picker = MethodChannelPhotoPicker(channel: channel);
    expect(await picker.probe(), isTrue);
    final photo = await picker.pickPhoto();
    expect(photo, isNotNull);
    expect(photo!.bytes, hasLength(MethodChannelPhotoPicker.maxPhotoBytes));
    expect(photo.bytes, isNot(same(rawBytes)));

    rawBytes[0] = 2;
    expect(photo.bytes.first, 1);
  });

  test('MethodChannel 照片适配器拒绝空超大非整数或越界字节', () async {
    final channel = const MethodChannel('cn.edu.buaa.ubaa/platform');
    Object? rawBytes = const <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'photo.capability') return true;
          return <String, Object?>{
            'bytes': rawBytes,
            'fileName': 'fixture.jpg',
            'mimeType': 'image/jpeg',
          };
        });

    final picker = MethodChannelPhotoPicker(channel: channel);
    expect(await picker.probe(), isTrue);
    for (final invalid in <Object?>[
      const <int>[],
      <Object>[1, '2'],
      const <int>[-1],
      const <int>[256],
      Uint8List(MethodChannelPhotoPicker.maxPhotoBytes + 1),
    ]) {
      rawBytes = invalid;
      expect(await picker.pickPhoto(), isNull, reason: '$invalid');
    }
  });

  test('MethodChannel 照片适配器拒绝非 canonical 原始文件名和 MIME', () async {
    final channel = const MethodChannel('cn.edu.buaa.ubaa/platform');
    var fileName = 'fixture.jpg';
    var mimeType = 'image/jpeg';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'photo.capability') return true;
          return <String, Object?>{
            'bytes': <int>[1],
            'fileName': fileName,
            'mimeType': mimeType,
          };
        });

    final picker = MethodChannelPhotoPicker(channel: channel);
    expect(await picker.probe(), isTrue);
    for (final invalidFileName in <String>[
      '',
      '.',
      '..',
      ' fixture.jpg',
      'fixture.jpg ',
      'folder/fixture.jpg',
      r'folder\fixture.jpg',
      'bad"name.jpg',
      'bad\nname.jpg',
      List<String>.filled(129, 'a').join(),
    ]) {
      fileName = invalidFileName;
      expect(await picker.pickPhoto(), isNull, reason: invalidFileName);
    }

    fileName = 'fixture.jpg';
    for (final invalidMimeType in <String>[
      'IMAGE/JPEG',
      'image/jpeg ',
      'image/',
      'image/a/b',
      'image/图片',
      'image/jpeg; charset=utf-8',
    ]) {
      mimeType = invalidMimeType;
      expect(await picker.pickPhoto(), isNull, reason: invalidMimeType);
    }
  });

  test('Callback 照片适配器拒绝携带路径的文件名', () async {
    final picker = CallbackPhotoPicker(
      pick: () async => const YgdkPhotoInput(
        bytes: <int>[1, 2, 3],
        fileName: 'private/fixture.jpg',
        mimeType: 'image/jpeg',
      ),
    );

    expect(await picker.pickPhoto(), isNull);
  });

  test('Callback 照片适配器在返回前深复制可变字节', () async {
    final rawBytes = Uint8List.fromList(<int>[1, 2, 3]);
    final picker = CallbackPhotoPicker(
      pick: () async => YgdkPhotoInput(
        bytes: rawBytes,
        fileName: 'fixture.jpg',
        mimeType: 'image/jpeg',
      ),
    );

    final photo = await picker.pickPhoto();
    expect(photo, isNotNull);
    expect(photo!.bytes, isNot(same(rawBytes)));
    rawBytes[0] = 9;
    expect(photo.bytes, <int>[1, 2, 3]);
  });
}

final class _DirectPhotoMethodChannel extends MethodChannel {
  const _DirectPhotoMethodChannel(this.photoResult)
    : super('cn.edu.buaa.ubaa/platform/direct-test');

  final Object? photoResult;

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async =>
      (method == 'photo.capability' ? true : photoResult) as T?;
}
