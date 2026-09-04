import 'package:flutter/services.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

/// 宿主可能需要向系统申请的能力；具体平台插件不得把令牌或原始路径
/// 暴露给应用层。
enum PlatformPermission { camera, photos, files, foregroundLocation }

/// 系统能力申请的稳定结果。
enum PlatformPermissionStatus { granted, denied, restricted, unavailable }

/// 平台能力暂不可用时的稳定错误，不携带系统异常正文。
class PlatformCapabilityException implements Exception {
  const PlatformCapabilityException(this.permission, this.status);

  final PlatformPermission permission;
  final PlatformPermissionStatus status;

  @override
  String toString() =>
      'PlatformCapabilityException(${permission.name}, ${status.name})';
}

/// 相机、相册、文件和前台位置权限的最小注入边界。
abstract interface class PlatformPermissionGateway {
  Future<PlatformPermissionStatus> request(PlatformPermission permission);
}

/// 原生权限插件的 typed 回调适配器。
///
/// 宿主只需把平台 SDK 的结果转换为 [PlatformPermissionStatus]；异常会被
/// 收敛为 `unavailable`，不会把系统异常正文、路径或令牌带入 Dart/UI。
final class CallbackPermissionGateway implements PlatformPermissionGateway {
  CallbackPermissionGateway({required PlatformPermissionRequester request})
    : _request = request;

  final PlatformPermissionRequester _request;

  @override
  Future<PlatformPermissionStatus> request(
    PlatformPermission permission,
  ) async {
    try {
      final status = await _request(permission);
      return status;
    } on Object {
      return PlatformPermissionStatus.unavailable;
    }
  }
}

/// 生产宿主使用的 MethodChannel 权限适配器。
///
/// 原生侧只返回固定状态字符串；缺少插件、方法或返回值异常时一律视为
/// `unavailable`，不会把平台异常正文带入 Dart。
final class MethodChannelPermissionGateway
    implements PlatformPermissionGateway {
  MethodChannelPermissionGateway({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('cn.edu.buaa.ubaa/platform');

  final MethodChannel _channel;

  @override
  Future<PlatformPermissionStatus> request(
    PlatformPermission permission,
  ) async {
    try {
      final result = await _channel.invokeMethod<Object?>(
        'permission.request',
        permission.name,
      );
      return switch (result) {
        'granted' => PlatformPermissionStatus.granted,
        'denied' => PlatformPermissionStatus.denied,
        'restricted' => PlatformPermissionStatus.restricted,
        _ => PlatformPermissionStatus.unavailable,
      };
    } on Object {
      return PlatformPermissionStatus.unavailable;
    }
  }
}

/// 平台权限请求回调的稳定类型。
typedef PlatformPermissionRequester =
    Future<PlatformPermissionStatus> Function(PlatformPermission permission);

/// 没有原生插件或权限配置时的安全默认实现。
final class UnavailablePermissionGateway implements PlatformPermissionGateway {
  const UnavailablePermissionGateway();

  @override
  Future<PlatformPermissionStatus> request(
    PlatformPermission permission,
  ) async => PlatformPermissionStatus.unavailable;
}

/// 供 widget/integration 测试使用的确定性权限实现。
final class MemoryPermissionGateway implements PlatformPermissionGateway {
  MemoryPermissionGateway({
    Map<PlatformPermission, PlatformPermissionStatus>? initial,
  }) : _statuses = <PlatformPermission, PlatformPermissionStatus>{...?initial};

  final Map<PlatformPermission, PlatformPermissionStatus> _statuses;
  final List<PlatformPermission> requests = <PlatformPermission>[];

  void setStatus(
    PlatformPermission permission,
    PlatformPermissionStatus status,
  ) {
    _statuses[permission] = status;
  }

  @override
  Future<PlatformPermissionStatus> request(
    PlatformPermission permission,
  ) async {
    requests.add(permission);
    return _statuses[permission] ?? PlatformPermissionStatus.denied;
  }
}

/// 阳光打卡照片选择器的最小 typed 边界。
abstract interface class PlatformPhotoPicker {
  bool get isAvailable;

  Future<YgdkPhotoInput?> pickPhoto();
}

/// 原生照片选择器的 typed 回调适配器。
///
/// 插件异常统一转换为稳定的相册能力错误；回调不得返回原始路径或带令牌
/// 的 URL，照片字节只在当前提交流程的内存中暂存。
final class CallbackPhotoPicker implements PlatformPhotoPicker {
  CallbackPhotoPicker({required this.pick, this.available = true});

  final PlatformPhotoPickerCallback pick;
  final bool available;

  @override
  bool get isAvailable => available;

  @override
  Future<YgdkPhotoInput?> pickPhoto() async {
    if (!available) return null;
    try {
      final photo = await pick();
      if (photo == null) return null;
      return _copyCanonicalPhotoInput(
        bytes: photo.bytes,
        fileName: photo.fileName,
        mimeType: photo.mimeType,
      );
    } on Object {
      throw const PlatformCapabilityException(
        PlatformPermission.photos,
        PlatformPermissionStatus.unavailable,
      );
    }
  }
}

/// 生产宿主使用的 MethodChannel 照片适配器。
///
/// 原生侧返回受限的字节、展示名和 MIME 类型；不会把文件路径或 URL 交给
/// Dart。必须先成功探测能力，且单张照片最多 10 MiB。
final class MethodChannelPhotoPicker implements PlatformPhotoPicker {
  MethodChannelPhotoPicker({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('cn.edu.buaa.ubaa/platform');

  static const maxPhotoBytes = 10 * 1024 * 1024;

  final MethodChannel _channel;
  bool _available = false;

  @override
  bool get isAvailable => _available;

  Future<bool> probe() async {
    try {
      _available =
          await _channel.invokeMethod<bool>('photo.capability') ?? false;
    } on Object {
      _available = false;
    }
    return _available;
  }

  @override
  Future<YgdkPhotoInput?> pickPhoto() async {
    if (!_available) return null;
    try {
      final result = await _channel.invokeMethod<Object?>('photo.pick');
      if (result is! Map) return null;
      return _copyCanonicalPhotoInput(
        bytes: result['bytes'],
        fileName: result['fileName'],
        mimeType: result['mimeType'],
      );
    } on Object {
      return null;
    }
  }
}

YgdkPhotoInput? _copyCanonicalPhotoInput({
  required Object? bytes,
  required Object? fileName,
  required Object? mimeType,
}) {
  if (bytes is! List ||
      fileName is! String ||
      mimeType is! String ||
      bytes.isEmpty ||
      bytes.length > MethodChannelPhotoPicker.maxPhotoBytes ||
      !_isCanonicalPhotoFileName(fileName) ||
      !_isCanonicalPhotoMimeType(mimeType)) {
    return null;
  }
  final copiedBytes = Uint8List(bytes.length);
  for (var index = 0; index < bytes.length; index++) {
    final value = bytes[index];
    if (value is! int || value < 0 || value > 255) return null;
    copiedBytes[index] = value;
  }
  return YgdkPhotoInput(
    bytes: copiedBytes,
    fileName: fileName,
    mimeType: mimeType,
  );
}

bool _isCanonicalPhotoFileName(String value) {
  final characters = value.runes;
  if (value != value.trim() ||
      value == '.' ||
      value == '..' ||
      characters.isEmpty ||
      characters.length > 128) {
    return false;
  }
  return !characters.any(
    (character) =>
        character == 0x2f ||
        character == 0x5c ||
        character == 0x22 ||
        character <= 0x1f ||
        (character >= 0x7f && character <= 0x9f),
  );
}

bool _isCanonicalPhotoMimeType(String value) {
  if (value != value.trim() || !value.startsWith('image/')) return false;
  final subtype = value.substring('image/'.length);
  return subtype.isNotEmpty && subtype.codeUnits.every(_isHttpTokenCodeUnit);
}

bool _isHttpTokenCodeUnit(int value) =>
    (value >= 0x30 && value <= 0x39) ||
    (value >= 0x41 && value <= 0x5a) ||
    (value >= 0x61 && value <= 0x7a) ||
    const <int>{
      0x21,
      0x23,
      0x24,
      0x25,
      0x26,
      0x27,
      0x2a,
      0x2b,
      0x2d,
      0x2e,
      0x5e,
      0x5f,
      0x60,
      0x7c,
      0x7e,
    }.contains(value);

/// 原生照片选择回调的稳定类型。
typedef PlatformPhotoPickerCallback = Future<YgdkPhotoInput?> Function();

/// 没有原生相册/文件选择器时的安全实现；不会伪造照片或写入本地文件。
final class UnavailablePhotoPicker implements PlatformPhotoPicker {
  const UnavailablePhotoPicker();

  @override
  bool get isAvailable => false;

  @override
  Future<YgdkPhotoInput?> pickPhoto() async => null;
}

/// 供 widget/integration 测试使用的内存照片选择器。
final class MemoryPhotoPicker implements PlatformPhotoPicker {
  MemoryPhotoPicker({YgdkPhotoInput? photo}) : _photo = photo;

  YgdkPhotoInput? _photo;
  int pickCount = 0;

  @override
  bool get isAvailable => true;

  void setPhoto(YgdkPhotoInput? photo) {
    _photo = photo;
  }

  @override
  Future<YgdkPhotoInput?> pickPhoto() async {
    pickCount++;
    return _photo;
  }
}

/// 在调用原生照片选择器前强制申请相册权限的组合适配器。
final class PermissionedPhotoPicker implements PlatformPhotoPicker {
  PermissionedPhotoPicker({
    required PlatformPermissionGateway permissions,
    required PlatformPhotoPicker picker,
    this.permission = PlatformPermission.photos,
  }) : _permissions = permissions,
       _picker = picker;

  final PlatformPermissionGateway _permissions;
  final PlatformPhotoPicker _picker;

  /// 移动端通常使用相册权限，桌面文件选择器可传入 [PlatformPermission.files]。
  final PlatformPermission permission;

  @override
  bool get isAvailable => _picker.isAvailable;

  @override
  Future<YgdkPhotoInput?> pickPhoto() async {
    final status = await _permissions.request(permission);
    if (status != PlatformPermissionStatus.granted) {
      throw PlatformCapabilityException(permission, status);
    }
    return _picker.pickPhoto();
  }
}
