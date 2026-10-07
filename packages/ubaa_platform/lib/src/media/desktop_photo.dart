part of '../media.dart';

/// 桌面系统单文件选择；只将受限内存照片交给Host。
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
      return await _readSelectedPhoto(file);
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
