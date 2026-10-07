import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('拍照插件返回受限内存图片，清理临时副本且不请求完整元数据', () async {
    final plugin = FakePicker()..file = NamedFile(png);
    var releases = 0;
    final picker = PluginPhotoPicker(
      picker: plugin,
      canCapturePhoto: true,
      releaseFile: (_) async {
        releases++;
      },
    );
    final photo = await picker.capturePhoto();
    expect(photo!.bytes, png);
    expect(plugin.source, ImageSource.camera);
    expect(plugin.metadata, isFalse);
    expect(releases, 1);
  });
  test('取消、重叠调用与插件权限拒绝保持稳定语义，失败后可重新选择', () async {
    final plugin = FakePicker()..gate = Completer<XFile?>();
    final picker = PluginPhotoPicker(picker: plugin, releaseFile: (_) async {});
    final first = picker.pickPhoto();
    expect(await picker.pickPhoto(), isNull);
    plugin.gate!.complete(null);
    expect(await first, isNull);
    plugin.gate = null;
    plugin.error = PlatformException(
      code: 'photo_access_denied',
      message: '合成私有路径',
    );
    await expectLater(
      picker.pickPhoto(),
      throwsA(
        isA<PlatformCapabilityException>().having(
          (e) => e.status,
          '权限',
          PlatformPermissionStatus.denied,
        ),
      ),
    );
    plugin.error = null;
    plugin.file = NamedFile(png);
    expect(await picker.pickPhoto(), isNotNull);
    expect(await picker.capturePhoto(), isNull);
  });
  test('损坏或超限照片被拒绝但仍释放插件副本', () async {
    final plugin = FakePicker();
    var releases = 0;
    final picker = PluginPhotoPicker(
      picker: plugin,
      releaseFile: (_) async {
        releases++;
      },
    );
    for (final bytes in [
      Uint8List.fromList([1, 2, 3]),
      Uint8List(maxPhotoBytes + 1),
    ]) {
      plugin.file = NamedFile(bytes);
      await expectLater(
        picker.pickPhoto(),
        throwsA(isA<PlatformCapabilityException>()),
      );
    }
    expect(releases, 2);
  });
  test('进程遗失结果只清理，不附回新的账号或表单', () async {
    final plugin = FakePicker()
      ..lost = LostDataResponse(
        files: [NamedFile(png)],
        type: RetrieveType.image,
      );
    var releases = 0;
    final picker = PluginPhotoPicker(
      picker: plugin,
      releaseFile: (_) async {
        releases++;
      },
    );
    await picker.discardLostPhotos();
    expect(releases, 1);
    expect(await picker.pickPhoto(), isNull);
  });
}

class FakePicker extends ImagePicker {
  XFile? file;
  Completer<XFile?>? gate;
  PlatformException? error;
  ImageSource? source;
  bool? metadata;
  LostDataResponse lost = LostDataResponse.empty();
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    this.source = source;
    metadata = requestFullMetadata;
    if (error != null) throw error!;
    return gate?.future ?? Future.value(file);
  }

  @override
  Future<LostDataResponse> retrieveLostData() async => lost;
}

class NamedFile extends XFile {
  NamedFile(Uint8List bytes)
    : super.fromData(bytes, path: '/synthetic/photo.png');
  @override
  String get name => '照片.png';
}
