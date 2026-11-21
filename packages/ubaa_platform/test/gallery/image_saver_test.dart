import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../support/test_tmp.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final png = Uint8List.fromList([137, 80, 78, 71]);
  const name = 'signin.png';
  const channel = MethodChannel('gal');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  for (final os in ['android', 'ios']) {
    test('$os 先申请仅添加权限，拒绝后不写入', () async {
      var granted = false;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'requestPermission' => granted,
          'putImageBytes' => null,
          _ => throw StateError('意外调用'),
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final saver = createDefaultGalleryImageSaver(operatingSystem: os);
      expect(saver.isAvailable, isTrue);
      await expectLater(
        saver.save(png, name: name),
        throwsA(
          isA<GalleryImageSaveException>().having(
            (error) => error.failure,
            'failure',
            GalleryImageSaveFailure.permissionDenied,
          ),
        ),
      );
      expect(calls.single.method, 'requestPermission');
      expect(calls.single.arguments, {'toAlbum': false});
      granted = true;
      calls.clear();
      expect(await saver.save(png, name: name), GalleryImageSaveResult.saved);
      expect(calls.first.method, 'requestPermission');
      expect(calls.last.method, 'putImageBytes');
      expect(calls.last.arguments, {
        'bytes': png,
        'name': 'signin',
        'album': null,
      });
    });
  }

  test('桌面取消不写入；选择后按原样保存；失败不暴露路径', () async {
    final scratch = createTestTempDirectory('ubaa_platform_gallery');
    addTearDown(() => scratch.delete(recursive: true));
    final file = File('${scratch.path}/$name');
    final cancelled = DesktopGalleryImageSaver(
      selectLocation: (_) async => null,
    );
    expect(
      await cancelled.save(png, name: name),
      GalleryImageSaveResult.cancelled,
    );
    expect(await file.exists(), isFalse);
    final saver = DesktopGalleryImageSaver(
      selectLocation: (suggested) async {
        expect(suggested, name);
        return file.path;
      },
    );
    expect(await saver.save(png, name: name), GalleryImageSaveResult.saved);
    expect(await file.readAsBytes(), png);
    final failing = DesktopGalleryImageSaver(
      selectLocation: (_) async {
        throw FileSystemException('合成异常', file.path);
      },
    );
    await expectLater(
      failing.save(png, name: name),
      throwsA(
        isA<GalleryImageSaveException>().having(
          (error) => error.toString(),
          'message',
          isNot(contains(file.path)),
        ),
      ),
    );
  });

  test('OHOS 使用宿主通道保存图片，取消返回 cancelled', () async {
    const gallery = MethodChannel('cn.edu.buaa.ubaa/gallery-image');
    final calls = <MethodCall>[];
    final results = [true, false];
    messenger.setMockMethodCallHandler(gallery, (call) async {
      calls.add(call);
      return results.removeAt(0);
    });
    addTearDown(() => messenger.setMockMethodCallHandler(gallery, null));
    final saver = createDefaultGalleryImageSaver(operatingSystem: 'ohos');
    expect(saver.isAvailable, isTrue);
    expect(await saver.save(png, name: name), GalleryImageSaveResult.saved);
    expect(await saver.save(png, name: name), GalleryImageSaveResult.cancelled);
    expect(calls.map((call) => call.method), ['saveImage', 'saveImage']);
    for (final call in calls) {
      expect(call.arguments, {'bytes': png, 'name': name});
    }
  });

  test('OHOS 通道故障映射为稳定错误，不带路径', () async {
    const gallery = MethodChannel('cn.edu.buaa.ubaa/gallery-image');
    messenger.setMockMethodCallHandler(gallery, (_) async {
      throw PlatformException(code: 'save_failed', message: '/合成/私有目录');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(gallery, null));
    final saver = createDefaultGalleryImageSaver(operatingSystem: 'ohos');
    await expectLater(
      saver.save(png, name: name),
      throwsA(
        isA<GalleryImageSaveException>()
            .having(
              (error) => error.failure,
              '错误分类',
              GalleryImageSaveFailure.saveFailed,
            )
            .having(
              (error) => error.toString(),
              '安全摘要',
              isNot(contains('/合成/私有目录')),
            ),
      ),
    );
  });
}
