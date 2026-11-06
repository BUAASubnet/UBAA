import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cn.edu.buaa.ubaa/bhpan-preview');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;

  setUp(() async {
    final base = Directory(
      '${Directory.current.path}/../../.ubaa_local/bhpan_delivery/integration/platform_tests',
    );
    await base.create(recursive: true);
    root = await base.createTemp('preview_');
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('iOS 使用可覆盖的私有临时路径，预览关闭后完成并删除临时目录', () async {
    final gate = Completer<void>();
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      expect(call.method, 'preview');
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      expect(args.keys, {'path'});
      expect(args['path'], isA<String>());
      expect((args['path'] as String).startsWith(root.path), true);
      await gate.future;
      return null;
    });

    final previewer = SystemBhpanFilePreviewer(
      operatingSystem: 'ios',
      stagingDirectory: () => root.createTemp('file_'),
    );
    final destination = await previewer.select('报告.pdf', () => true);
    expect(destination, isNotNull);
    expect(destination!.overwrite, true);
    await File(destination.path).writeAsString('synthetic preview body');

    var delivered = false;
    final delivery = destination
        .deliver(() => true)
        .then((_) => delivered = true);
    await Future<void>.delayed(Duration.zero);
    expect(delivered, false);
    expect(calls, hasLength(1));

    gate.complete();
    await delivery;
    expect(delivered, true);
    await destination.discard();
    expect(await File(destination.path).exists(), false);
    expect(await Directory(destination.path).parent.exists(), false);
  });

  test('iOS 以外不提供预览目标，预览后作用域变化返回冲突并可清理', () async {
    expect(
      SystemBhpanFilePreviewer(
        operatingSystem: 'android',
        stagingDirectory: () async => root.createTemp('unused_'),
      ).isAvailable,
      false,
    );

    final previewClosed = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      await previewClosed.future;
      return null;
    });
    final directory = await root.createTemp('file_');
    final previewer = SystemBhpanFilePreviewer(
      operatingSystem: 'ios',
      stagingDirectory: () async => directory,
    );
    final destination = (await previewer.select('报告.pdf', () => true))!;
    await File(destination.path).writeAsString('synthetic preview body');
    var current = true;
    final delivery = destination.deliver(() => current);
    current = false;
    previewClosed.complete();
    await expectLater(
      delivery,
      throwsA(
        isA<UiError>().having(
          (error) => error.code,
          '错误分类',
          UbaaErrorCode.operationConflict,
        ),
      ),
    );
    await destination.discard();
    expect(await directory.exists(), false);
  });

  test('选择期间作用域变化时清理临时目标', () async {
    var current = true;
    Directory? directory;
    final previewer = SystemBhpanFilePreviewer(
      operatingSystem: 'ios',
      stagingDirectory: () async {
        directory = await root.createTemp('file_');
        current = false;
        return directory!;
      },
    );
    expect(await previewer.select('报告.pdf', () => current), isNull);
    expect(await directory!.exists(), false);
  });
}
