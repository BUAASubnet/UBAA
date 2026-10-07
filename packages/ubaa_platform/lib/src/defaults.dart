import 'package:flutter/foundation.dart';

import 'credentials.dart';
import 'secure_material.dart';
import 'location.dart';
import 'media.dart';
import 'paths.dart';

/// 生产宿主的默认平台能力组合。
///
/// 移动端/macOS能力通过现有MethodChannel探测；Windows/Linux选图使用
/// 已注册的系统文件选择插件。缺失能力不以回调、内存或明文文件冒充。
final class PlatformCapabilities {
  const PlatformCapabilities({
    required this.credentialVault,
    required this.photoPicker,
    required this.permissionGateway,
    required this.locationProvider,
    this.secureMaterials,
  });

  final CredentialVault credentialVault;
  final SecureMaterialStore? secureMaterials;
  final PlatformPhotoPicker photoPicker;
  final PlatformPermissionGateway permissionGateway;
  final PlatformLocationProvider locationProvider;
}

Future<PlatformCapabilities> createDefaultPlatformCapabilities() async {
  await initializePrivateDirectory();
  final materials = SecureMaterialStore();
  await materials.probe();
  final credentialStore = MaterialCredentialStore(materials);
  final photos = await createDefaultPhotoCapabilities();
  final locationProvider = MethodChannelLocationProvider();
  await locationProvider.probe();
  return PlatformCapabilities(
    credentialVault: PlatformCredentialVault(store: credentialStore),
    // 探测失败时不把不可用的句柄交给宿主，避免宿主把它误当成可用
    // 的本地账号仓库，随后所有加密缓存写入才会统一返回 unavailable。
    secureMaterials: materials.isAvailable ? materials : null,
    photoPicker: photos.picker,
    permissionGateway: photos.permissions,
    locationProvider: locationProvider,
  );
}

/// 选图与权限需配对，避免桌面入口被不存在的移动相册权限挡住。
final class PhotoCapabilities {
  const PhotoCapabilities(this.picker, this.permissions);
  final PlatformPhotoPicker picker;
  final PlatformPermissionGateway permissions;
}

Future<PhotoCapabilities> createDefaultPhotoCapabilities({
  TargetPlatform? targetPlatform,
}) async {
  final target = targetPlatform ?? defaultTargetPlatform;
  final permissions = MethodChannelPermissionGateway();
  if (target == TargetPlatform.windows || target == TargetPlatform.linux) {
    return PhotoCapabilities(
      DesktopFilePhotoPicker(),
      DesktopFilePermissionGateway(permissions),
    );
  }
  final picker = MethodChannelPhotoPicker();
  await picker.probe();
  return PhotoCapabilities(picker, permissions);
}
