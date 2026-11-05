import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

class _PartialCopy implements File {
  _PartialCopy(this.target);
  final File target;
  bool wrote = false;

  @override
  Future<File> copy(String newPath) async {
    expect(newPath, target.path);
    expect(await target.exists(), true);
    await target.writeAsString('syn');
    wrote = true;
    throw const FileSystemException('合成复制中断');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cn.edu.buaa.ubaa/agenda-file');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;
  setUp(() async {
    final base = Directory(
      '${Directory.current.path}/../../.ubaa_local/bhpan_delivery/integration/platform_tests',
    );
    await base.create(recursive: true);
    root = await base.createTemp('save_');
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    if (await root.exists()) await root.delete(recursive: true);
  });
  test('移动端只把本机文件路径交给原生通道并在交付后清理正文', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'select') return 'selection';
      if (call.method == 'writeFile') {
        final args = Map<Object?, Object?>.from(call.arguments as Map);
        expect(args.containsKey('bytes'), false);
        expect(
          await File(args['path'] as String).readAsString(),
          'synthetic body',
        );
      }
      return null;
    });
    final folder = await root.createTemp('body_');
    final saver = SystemBhpanFileSaver(
      operatingSystem: 'android',
      stagingDirectory: () async => folder,
    );
    final destination = (await saver.select('report.txt', () => true))!;
    await File(destination.path).writeAsString('synthetic body');
    await destination.deliver(() => true);
    await destination.discard();
    expect(calls.map((call) => call.method), ['select', 'writeFile']);
    expect((calls.first.arguments as Map)['kind'], 'binary');
    expect(await folder.exists(), false);
  });
  test('选择取消与选择期间换号均不创建正文目录', () async {
    var current = true, created = 0, round = 0;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'select') {
        round++;
        if (round == 1) return null;
        current = false;
        return 'selection';
      }
      return null;
    });
    final saver = SystemBhpanFileSaver(
      operatingSystem: 'ios',
      stagingDirectory: () async {
        created++;
        return root.createTemp('body_');
      },
    );
    expect(await saver.select('report.txt', () => current), null);
    expect(await saver.select('report.txt', () => current), null);
    expect(created, 0);
    expect(calls, ['select', 'select', 'discard']);
  });
  test('交付前换号拒绝文件写入且原生丢弃失败仍清理本机正文', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'select') return 'selection';
      if (call.method == 'discard') throw PlatformException(code: 'closed');
      return null;
    });
    final folder = await root.createTemp('body_');
    final destination = (await SystemBhpanFileSaver(
      operatingSystem: 'ohos',
      stagingDirectory: () async => folder,
    ).select('report.txt', () => true))!;
    await File(destination.path).writeAsString('synthetic body');
    await expectLater(
      destination.deliver(() => false),
      throwsA(isA<UiError>()),
    );
    await expectLater(destination.discard(), throwsA(isA<PlatformException>()));
    expect(calls, ['select', 'discard']);
    expect(await folder.exists(), false);
  });
  test('OHOS 文件选择只交付路径并只释放一次缓存副本', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'pickFile')
        return {'path': '/cache/selected', 'name': 'report.txt'};
      return null;
    });
    final file = (await const SystemBhpanFilePicker(
      operatingSystem: 'ohos',
    ).pick())!;
    expect(file.path, '/cache/selected');
    expect(file.name, 'report.txt');
    await file.release();
    await file.release();
    expect(calls, ['pickFile', 'releaseFile']);
  });
  test('原生交付拒绝后清理私有正文并保留不可用错误分类', () async {
    for (final code in [
      'exists',
      'cleanup_failed',
      'unsupported_destination',
    ]) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'select') return 'selection';
        if (call.method == 'resolveFile') throw PlatformException(code: code);
        return null;
      });
      final folder = await root.createTemp('body_');
      final destination = (await SystemBhpanFileSaver(
        operatingSystem: 'ohos',
        stagingDirectory: () async => folder,
      ).select('report.txt', () => true))!;
      await File(destination.path).writeAsString('synthetic body');
      await expectLater(
        destination.deliver(() => true),
        throwsA(
          isA<UiError>().having(
            (error) => error.code,
            '错误分类',
            code == 'unsupported_destination'
                ? UbaaErrorCode.unsupported
                : UbaaErrorCode.invalidInput,
          ),
        ),
      );
      await destination.discard();
      expect(await folder.exists(), false);
    }
  });
  for (final mode in ['success', 'collision', 'partial', 'superseded']) {
    test('OHOS 在授权路径独占创建和交付：$mode', () async {
      final target = File('${root.path}/报告.txt');
      final folder = await root.createTemp('body_');
      var current = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'select') return 'selection';
        if (call.method != 'resolveFile') {
          fail('OHOS 下载应使用系统授权的本机路径');
        }
        expect(call.arguments, {'selection': 'selection'});
        if (mode == 'collision') await target.writeAsString('existing');
        if (mode == 'superseded') current = false;
        return target.path;
      });
      final destination = (await SystemBhpanFileSaver(
        operatingSystem: 'ohos',
        stagingDirectory: () async => folder,
      ).select('报告.txt', () => current))!;
      await File(destination.path).writeAsString('synthetic body');
      try {
        if (mode == 'success') {
          await destination.deliver(() => current);
          expect(await target.readAsString(), 'synthetic body');
        } else if (mode == 'partial') {
          final source = _PartialCopy(target);
          await IOOverrides.runZoned(
            () => expectLater(
              destination.deliver(() => current),
              throwsA(isA<UiError>()),
            ),
            createFile: (path) => path == destination.path
                ? source
                : path == target.path
                ? target
                : throw StateError('意外文件路径'),
          );
          expect(source.wrote, true);
          expect(await target.exists(), false);
        } else {
          await expectLater(
            destination.deliver(() => current),
            throwsA(isA<UiError>()),
          );
          if (mode == 'collision') {
            expect(await target.readAsString(), 'existing');
          } else {
            expect(current, false);
            expect(await target.exists(), false);
          }
        }
      } finally {
        await destination.discard();
      }
      expect(await folder.exists(), false);
    });
  }
}
