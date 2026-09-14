import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cn.edu.buaa.ubaa/platform');

  testWidgets('macOS 真实 Keychain 的完整凭据生命周期', (tester) async {
    final first = MethodChannelSecureCredentialStore();
    expect(await first.probe(), isTrue, reason: 'macOS 必须注册真实系统凭据能力');
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

    Future<void> reject(String method, Object? arguments) async {
      await expectLater(
        channel.invokeMethod<Object?>(method, arguments),
        throwsA(
          isA<PlatformException>()
              .having(
                (error) => error.code,
                '稳定错误类别',
                'credentials_invalid_input',
              )
              .having((error) => error.details, '无原生错误正文', isNull),
        ),
      );
    }

    try {
      expect(await first.read(namespace), isNull);
      await first.clear(namespace);
      await first.write(namespace, original);

      // 新建适配器重新查询系统存储，不能依赖 Dart 实例内缓存。
      final restored = MethodChannelSecureCredentialStore();
      expect(await restored.probe(), isTrue);
      expect(await restored.read(namespace), original);

      await restored.write(namespace, updated);
      expect(await first.read(namespace), updated);

      final valid = <String, Object?>{
        'namespace': namespace,
        'username': original.username,
        'password': original.password,
        'autoLogin': false,
      };
      for (final field in valid.keys) {
        await reject('credentials.write', {...valid}..remove(field));
      }
      for (final invalid in <Map<String, Object?>>[
        {'namespace': ''},
        {'namespace': 1},
        {'username': ''},
        {'username': ' \t\n'},
        {'username': 1},
        {'password': ''},
        {'password': 1},
        {'autoLogin': 0},
        {'autoLogin': 1},
        {'autoLogin': 'true'},
        {'autoLogin': null},
      ]) {
        await reject('credentials.write', {...valid, ...invalid});
      }
      for (final invalid in <Object?>[
        null,
        '',
        ' \n',
        1,
        <String, Object?>{},
      ]) {
        await reject('credentials.read', invalid);
        await reject('credentials.clear', invalid);
      }
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
    final picker = MethodChannelPhotoPicker();
    expect(await picker.probe(), isTrue);
    expect(
      await MethodChannelPermissionGateway().request(PlatformPermission.photos),
      PlatformPermissionStatus.granted,
    );
    // 不打开系统选择器，不读取照片或触发业务请求。
  }, skip: !Platform.isMacOS);
}
