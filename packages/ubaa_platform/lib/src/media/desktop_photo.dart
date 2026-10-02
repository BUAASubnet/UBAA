part of '../media.dart';

/// Windows/Linux系统单文件选择；只将受限内存照片交给Host。
final class DesktopFilePhotoPicker implements PlatformPhotoPicker {
  DesktopFilePhotoPicker({Future<selector.XFile?> Function()? selectFile})
    : _selectFile = selectFile ?? _openDesktopImage;
  final Future<selector.XFile?> Function() _selectFile;
  bool _picking = false;
  @override
  bool get isAvailable => true;
  @override
  Future<YgdkPhotoInput?> pickPhoto() async {
    if (_picking) return null;
    _picking = true;
    try {
      final file = await _selectFile();
      if (file == null) return null;
      final size = await file.length();
      if (size <= 0 || size > MethodChannelPhotoPicker.maxPhotoBytes)
        throw const FormatException();
      final builder = typed.BytesBuilder(copy: false);
      await for (final chunk in file.openRead()) {
        // 文件在长度检查后增长也不能无界分配；提前退出会取消流。
        if (builder.length + chunk.length >
            MethodChannelPhotoPicker.maxPhotoBytes)
          throw const FormatException();
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      final result = _copyCanonicalPhotoInput(
        bytes: bytes,
        fileName: file.name,
        mimeType: mime.lookupMimeType(file.name, headerBytes: bytes),
      );
      if (result == null) throw const FormatException();
      return result;
    } on Object {
      throw const PlatformCapabilityException(
        PlatformPermission.photos,
        PlatformPermissionStatus.unavailable,
      );
    } finally {
      _picking = false;
    }
  }
}

Future<selector.XFile?> _openDesktopImage() => selector.openFile(
  acceptedTypeGroups: const [
    selector.XTypeGroup(
      label: '图片',
      extensions: [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'bmp',
        'heic',
        'heif',
        'tif',
        'tiff',
      ],
    ),
  ],
  confirmButtonText: '选择图片',
);

/// 文件对话框由用户授权单个文件，无移动端相册库权限请求。
final class DesktopFilePermissionGateway implements PlatformPermissionGateway {
  const DesktopFilePermissionGateway(this.fallback);
  final PlatformPermissionGateway fallback;
  @override
  Future<PlatformPermissionStatus> request(PlatformPermission permission) =>
      permission == PlatformPermission.photos ||
          permission == PlatformPermission.files
      ? Future.value(PlatformPermissionStatus.granted)
      : fallback.request(permission);
}
