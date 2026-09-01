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

/// 没有原生插件或权限配置时的安全默认实现。
final class UnavailablePermissionGateway implements PlatformPermissionGateway {
  const UnavailablePermissionGateway();

  @override
  Future<PlatformPermissionStatus> request(
    PlatformPermission permission,
  ) async =>
      PlatformPermissionStatus.unavailable;
}

/// 供 widget/integration 测试使用的确定性权限实现。
final class MemoryPermissionGateway implements PlatformPermissionGateway {
  MemoryPermissionGateway({
    Map<PlatformPermission, PlatformPermissionStatus>? initial,
  }) : _statuses = <PlatformPermission, PlatformPermissionStatus>{
         ...?initial,
       };

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
  }) : _permissions = permissions,
       _picker = picker;

  final PlatformPermissionGateway _permissions;
  final PlatformPhotoPicker _picker;

  @override
  bool get isAvailable => _picker.isAvailable;

  @override
  Future<YgdkPhotoInput?> pickPhoto() async {
    final status = await _permissions.request(PlatformPermission.photos);
    if (status != PlatformPermissionStatus.granted) {
      throw PlatformCapabilityException(PlatformPermission.photos, status);
    }
    return _picker.pickPhoto();
  }
}
