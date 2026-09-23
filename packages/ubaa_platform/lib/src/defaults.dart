import 'credentials.dart';
import 'secure_material.dart';
import 'location.dart';
import 'media.dart';
import 'paths.dart';

/// 生产宿主的默认平台能力组合。
///
/// 每个能力都先通过 MethodChannel 探测；没有注册原生插件时返回安全的
/// 不可用实现，不会以回调、内存或明文文件冒充系统能力。
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
  final legacyStore = MethodChannelSecureCredentialStore();
  await legacyStore.probe();
  final materials = SecureMaterialStore();
  await materials.probe();
  // 已存在的原生凭据接线优先，避免升级后隐式迁移密码授权。
  final PlatformSecureCredentialStore credentialStore = legacyStore.isAvailable
      ? legacyStore
      : MaterialCredentialStore(materials);
  final photoPicker = MethodChannelPhotoPicker();
  await photoPicker.probe();
  final locationProvider = MethodChannelLocationProvider();
  await locationProvider.probe();
  return PlatformCapabilities(
    credentialVault: PlatformCredentialVault(store: credentialStore),
    // 探测失败时不把不可用的句柄交给宿主，避免宿主把它误当成可用
    // 的本地账号仓库，随后所有加密缓存写入才会统一返回 unavailable。
    secureMaterials: materials.isAvailable ? materials : null,
    photoPicker: photoPicker,
    permissionGateway: MethodChannelPermissionGateway(),
    locationProvider: locationProvider,
  );
}
