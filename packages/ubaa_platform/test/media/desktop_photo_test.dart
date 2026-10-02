import 'dart:async';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

final _png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0]);
void main() {
  test('文件在长度检查后增长仍不能超过10MiB', () async {
    final picker = DesktopFilePhotoPicker(
      selectFile: () async => _GrowingFile(),
    );
    await expectLater(
      picker.pickPhoto(),
      throwsA(isA<PlatformCapabilityException>()),
    );
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  test('生产桌面能力组合只为系统文件选择配对权限，不冒充相机', () async {
    for (final target in [TargetPlatform.windows, TargetPlatform.linux]) {
      final capabilities = await createDefaultPhotoCapabilities(
        targetPlatform: target,
      );
      expect(capabilities.picker, isA<DesktopFilePhotoPicker>());
      expect(
        await capabilities.permissions.request(PlatformPermission.photos),
        PlatformPermissionStatus.granted,
      );
      expect(
        await capabilities.permissions.request(PlatformPermission.camera),
        PlatformPermissionStatus.unavailable,
      );
    }
  });

  test('桌面选图返回限定字节而不把路径传给Host，MIME优先文件头', () async {
    final picker = DesktopFilePhotoPicker(
      selectFile: () async => _MemoryFile(_png, name: '示例.jpg'),
    );
    expect(picker.isAvailable, isTrue);
    final photo = await picker.pickPhoto();
    expect(photo!.bytes, _png);
    expect(photo.mimeType, 'image/png');
    expect(photo.fileName, '示例.jpg');
    expect(picker, isNot(isA<PlatformPhotoCapture>()));
  });
  test('选择取消不产生照片，重叠选择不打开第二个窗口', () async {
    var calls = 0;
    final gate = Completer<XFile?>();
    final picker = DesktopFilePhotoPicker(
      selectFile: () {
        calls++;
        return gate.future;
      },
    );
    final first = picker.pickPhoto();
    expect(await picker.pickPhoto(), isNull);
    expect(calls, 1);
    gate.complete(null);
    expect(await first, isNull);
  });
  test('超限或读取失败只给安全错误且不暴露路径', () async {
    for (final file in [
      _MemoryFile(
        Uint8List(MethodChannelPhotoPicker.maxPhotoBytes + 1),
        name: 'large.png',
      ),
      _BrokenFile(),
    ]) {
      final picker = DesktopFilePhotoPicker(selectFile: () async => file);
      await expectLater(
        picker.pickPhoto(),
        throwsA(isA<PlatformCapabilityException>()),
      );
    }
  });
  test('非图片与不安全basename不进入照片表单', () async {
    for (final file in [
      _MemoryFile(Uint8List.fromList([1, 2, 3]), name: 'file.txt'),
      _MemoryFile(_png, name: '../private.png'),
    ]) {
      final picker = DesktopFilePhotoPicker(selectFile: () async => file);
      await expectLater(
        picker.pickPhoto(),
        throwsA(isA<PlatformCapabilityException>()),
      );
    }
  });
}

class _BrokenFile extends XFile {
  _BrokenFile() : super('/synthetic/private/path');
  @override
  Future<int> length() async => throw StateError('/synthetic/private/path');
}

class _MemoryFile extends XFile {
  _MemoryFile(Uint8List bytes, {required String name})
    : _name = name,
      super.fromData(bytes, path: '/synthetic/fixture');
  final String _name;
  @override
  String get name => _name;
}

class _GrowingFile extends _MemoryFile {
  _GrowingFile()
    : super(
        Uint8List(MethodChannelPhotoPicker.maxPhotoBytes + 1),
        name: 'growing.png',
      );
  @override
  Future<int> length() async => 1;
}
