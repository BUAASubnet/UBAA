import 'credentials.dart';
import 'location.dart';
import 'media.dart';

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
  });

  final CredentialVault credentialVault;
  final PlatformPhotoPicker photoPicker;
  final PlatformPermissionGateway permissionGateway;
  final PlatformLocationProvider locationProvider;
}

Future<PlatformCapabilities> createDefaultPlatformCapabilities() async {
  final credentialStore = MethodChannelSecureCredentialStore();
  await credentialStore.probe();
  final photoPicker = MethodChannelPhotoPicker();
  await photoPicker.probe();
  final locationProvider = MethodChannelLocationProvider();
  await locationProvider.probe();
  return PlatformCapabilities(
    credentialVault: PlatformCredentialVault(store: credentialStore),
    photoPicker: photoPicker,
    permissionGateway: MethodChannelPermissionGateway(),
    locationProvider: locationProvider,
  );
}
