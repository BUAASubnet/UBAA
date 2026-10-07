import 'dart:io';
import 'package:flutter/foundation.dart';

import 'credentials.dart';
import 'secure_material.dart';
import 'location.dart';
import 'media.dart';
import 'paths.dart';

/// 生产宿主的默认平台能力组合。
///
/// 图片、安全材料和目录均交给注册插件；平台策略只在此组合。
/// 尚未接通的位置能力明确不可用，不向业务层泄露插件细节。
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
  const locationProvider = UnavailableLocationProvider();
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
  if (target == TargetPlatform.windows ||
      target == TargetPlatform.linux ||
      target == TargetPlatform.macOS) {
    return PhotoCapabilities(
      DesktopFilePhotoPicker(),
      const PickerPermissionGateway(),
    );
  }
  final camera =
      Platform.operatingSystem != 'ohos' && target == TargetPlatform.android;
  final picker = PluginPhotoPicker(canCapturePhoto: camera);
  if (camera) {
    try {
      await picker.discardLostPhotos();
    } on Object {
      /* 旧结果不附回新表单。 */
    }
  }
  return PhotoCapabilities(picker, PickerPermissionGateway(camera: camera));
}
