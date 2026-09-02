import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:flutter/services.dart';

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
      return await pick();
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
      final rawBytes = result['bytes'];
      final fileName = result['fileName'];
      final mimeType = result['mimeType'];
      if (rawBytes is! List || fileName is! String || mimeType is! String) {
        return null;
      }
      if (rawBytes.isEmpty || rawBytes.length > maxPhotoBytes) return null;
      if (!mimeType.startsWith('image/')) return null;
      final safeFileName = fileName.split(RegExp(r'[/\\]')).last.trim();
      if (safeFileName.isEmpty || safeFileName.length > 128) return null;
      return YgdkPhotoInput(
        bytes: rawBytes.cast<int>(),
        fileName: safeFileName,
        mimeType: mimeType,
      );
    } on Object {
      return null;
    }
  }
}

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
