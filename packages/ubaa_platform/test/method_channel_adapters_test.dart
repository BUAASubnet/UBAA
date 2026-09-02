import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('MethodChannel 照片适配器拒绝畸形或超大返回值', () async {
    final channel = const MethodChannel('cn.edu.buaa.ubaa/platform');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'photo.capability') return true;
          return <String, Object?>{
            'bytes': List<int>.filled(10 * 1024 * 1024 + 1, 1),
            'fileName': 'fixture.jpg',
            'mimeType': 'image/jpeg',
          };
        });

    final picker = MethodChannelPhotoPicker(channel: channel);
    expect(await picker.probe(), isTrue);
    expect(await picker.pickPhoto(), isNull);
  });
}
