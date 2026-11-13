import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const plugin = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late Map<String, String> values;
  late List<String> calls;
  String? failure;
  var reads = 0;

  SecureMaterialStore open() => SecureMaterialStore(
    coordinator: MaterialCoordinator(directory: directory),
    transport: const PlatformSecureMaterialTransport(
      operatingSystem: 'android',
    ),
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ubaa_android_probe_');
    values = {'ubaa.material.v2.fixture-business': 'synthetic-business'};
    calls = [];
    failure = null;
    reads = 0;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(plugin, (call) async {
      calls.add(call.method);
      final args = call.arguments as Map;
      final key = args['key'] as String;
      switch (call.method) {
        case 'read':
          reads++;
          if (failure == 'readback' && reads == 2) {
            throw PlatformException(code: 'synthetic_read_failure');
          }
          return values[key];
        case 'write':
          if (failure == 'write_before') {
            throw PlatformException(code: 'synthetic_write_failure');
          }
          values[key] = args['value'] as String;
          if (failure == 'write_after') {
            throw PlatformException(code: 'synthetic_write_failure');
          }
        case 'delete':
          if (failure == 'delete') {
            throw PlatformException(code: 'synthetic_delete_failure');
          }
          if (failure != 'verify_delete') values.remove(key);
        default:
          fail('探测只能操作自己的临时键');
      }
      return null;
    });
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(plugin, null);
    await directory.delete(recursive: true);
  });

  for (final marker in [null, 'UBAA1:C']) {
    for (final step in [
      'write_before',
      'write_after',
      'readback',
      'delete',
      'verify_delete',
    ]) {
      test('Android 探测 $step 失败保留事务状态 $marker，重新启动可以恢复', () async {
        final state = File('${directory.path}/transaction.v1');
        if (marker != null) await state.writeAsString(marker, flush: true);
        failure = step;
        final first = open();
        await first.probe();
        expect(first.isAvailable, isFalse);
        expect(calls.where((call) => call == 'write'), hasLength(1));
        expect(
          await state.exists() ? await state.readAsString() : null,
          marker,
        );
        expect(
          values['ubaa.material.v2.fixture-business'],
          'synthetic-business',
        );

        failure = null;
        final reopened = open();
        await reopened.probe();
        expect(reopened.isAvailable, isTrue);
        expect(await reopened.read('fixture-business'), 'synthetic-business');
        await reopened.write('fixture-new', 'synthetic-new');
        expect(await state.readAsString(), 'UBAA1:C');
        expect(await reopened.read('fixture-new'), 'synthetic-new');
      });
    }
  }

  test('Android 业务写入失败后仍保留未完成事务并阻止重新探测', () async {
    final materials = open();
    await materials.probe();
    expect(materials.isAvailable, isTrue);
    failure = 'write_after';
    await expectLater(
      materials.write('fixture-new', 'synthetic-new'),
      throwsA(isA<SecureMaterialException>()),
    );
    final state = File('${directory.path}/transaction.v1');
    expect(await state.readAsString(), 'UBAA1:B');
    expect(values['ubaa.material.v2.fixture-new'], 'synthetic-new');
    final count = calls.length;
    failure = null;
    final reopened = open();
    await reopened.probe();
    expect(reopened.isAvailable, isFalse);
    expect(calls, hasLength(count));
    expect(await state.readAsString(), 'UBAA1:B');
  });

  test('Android 启动探测保留已有未完成业务事务并阻止插件访问', () async {
    final state = File('${directory.path}/transaction.v1');
    await state.writeAsString('UBAA1:B', flush: true);
    final materials = open();
    await materials.probe();
    expect(materials.isAvailable, isFalse);
    expect(calls, isEmpty);
    expect(await state.readAsString(), 'UBAA1:B');
    expect(values, {'ubaa.material.v2.fixture-business': 'synthetic-business'});
  });
}
