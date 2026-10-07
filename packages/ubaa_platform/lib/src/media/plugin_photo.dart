part of '../media.dart';

/// 系统选图/拍照由 image_picker 管理；业务只接收已验证的内存照片。
final class PluginPhotoPicker
    implements PlatformPhotoPicker, PlatformPhotoCapture {
  PluginPhotoPicker({
    picker_plugin.ImagePicker? picker,
    this.canCapturePhoto = false,
    Future<void> Function(selector.XFile)? releaseFile,
  }) : _picker = picker ?? picker_plugin.ImagePicker(),
       _release = releaseFile ?? _releasePluginPhoto;
  final picker_plugin.ImagePicker _picker;
  final Future<void> Function(selector.XFile) _release;
  bool _picking = false;
  @override
  final bool canCapturePhoto;
  @override
  bool get isAvailable => true;
  @override
  Future<YgdkPhotoInput?> pickPhoto() =>
      _pick(picker_plugin.ImageSource.gallery);
  @override
  Future<YgdkPhotoInput?> capturePhoto() async =>
      canCapturePhoto ? _pick(picker_plugin.ImageSource.camera) : null;
  Future<YgdkPhotoInput?> _pick(picker_plugin.ImageSource source) async {
    if (_picking) return null;
    _picking = true;
    selector.XFile? file;
    try {
      // 沿旧版预览照片用途限制尺寸；系统插件管理相机输出和 Activity 生命周期。
      file = await _picker.pickImage(
        source: source,
        maxWidth: source == picker_plugin.ImageSource.camera ? 320 : null,
        maxHeight: source == picker_plugin.ImageSource.camera ? 320 : null,
        imageQuality: source == picker_plugin.ImageSource.camera ? 92 : null,
        requestFullMetadata: false,
      );
      return file == null ? null : await _readSelectedPhoto(file);
    } on PlatformException catch (error) {
      throw PlatformCapabilityException(
        source == picker_plugin.ImageSource.camera
            ? PlatformPermission.camera
            : PlatformPermission.photos,
        error.code.contains('denied')
            ? PlatformPermissionStatus.denied
            : error.code.contains('restricted')
            ? PlatformPermissionStatus.restricted
            : PlatformPermissionStatus.unavailable,
      );
    } on Object {
      throw PlatformCapabilityException(
        source == picker_plugin.ImageSource.camera
            ? PlatformPermission.camera
            : PlatformPermission.photos,
        PlatformPermissionStatus.unavailable,
      );
    } finally {
      try {
        if (file != null) await _release(file);
      } on Object {
        /* 清理失败不泄露插件原始路径，也不覆盖业务结果。 */
      } finally {
        _picking = false;
      }
    }
  }

  /// 跨进程没有可信表单/账号身份，遗失结果只清理，绝不自动附回新账号。
  Future<void> discardLostPhotos() async {
    final response = await _picker.retrieveLostData();
    for (final file in response.files ?? <selector.XFile>[]) {
      await _release(file);
    }
  }
}

Future<YgdkPhotoInput> _readSelectedPhoto(selector.XFile file) async {
  final size = await file.length();
  if (size <= 0 || size > maxPhotoBytes) throw const FormatException();
  final builder = typed.BytesBuilder(copy: false);
  await for (final chunk in file.openRead()) {
    if (builder.length + chunk.length > maxPhotoBytes)
      throw const FormatException();
    builder.add(chunk);
  }
  final bytes = builder.takeBytes();
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width <= 0 || descriptor.height <= 0)
      throw const FormatException();
  } finally {
    descriptor?.dispose();
    buffer.dispose();
  }
  final result = _copyCanonicalPhotoInput(
    bytes: bytes,
    fileName: file.name,
    mimeType: mime.lookupMimeType(file.name, headerBytes: bytes),
  );
  if (result == null) throw const FormatException();
  return result;
}

Future<void> _releasePluginPhoto(selector.XFile file) async {
  // 仅删除应用临时目录里的插件副本，不删除选择器返回的外部原文件。
  try {
    final temporary = await (await getTemporaryDirectory())
        .resolveSymbolicLinks();
    final selected = File(file.path);
    final resolved = await selected.resolveSymbolicLinks();
    if (paths.isWithin(temporary, resolved)) await selected.delete();
  } on Object {
    /* 系统可能已回收临时副本。 */
  }
}

/// 插件在实际操作时申请权限，不提前要求整库访问。
final class PickerPermissionGateway implements PlatformPermissionGateway {
  const PickerPermissionGateway({this.camera = false});
  final bool camera;
  @override
  Future<PlatformPermissionStatus> request(
    PlatformPermission permission,
  ) async =>
      permission == PlatformPermission.photos ||
          permission == PlatformPermission.files ||
          (permission == PlatformPermission.camera && camera)
      ? PlatformPermissionStatus.granted
      : PlatformPermissionStatus.unavailable;
}
