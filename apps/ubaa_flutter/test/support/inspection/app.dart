part of 'backend.dart';

/// 显式合成巡检宿主；不创建真实客户端，也不读取本机账号。
Widget createInspectionApp({
  String state = 'normal',
  Set<FeatureId>? failingReads,
  Future<void> Function()? beforeRead,
}) => UbaaFlutterApp(
  backend: _InspectionBackend(
    state: state,
    failingReads: failingReads,
    beforeRead: beforeRead,
  ),
  credentialVault: MemoryCredentialVault(),
  permissionGateway: MemoryPermissionGateway(
    initial: <PlatformPermission, PlatformPermissionStatus>{
      PlatformPermission.photos: PlatformPermissionStatus.granted,
    },
  ),
  photoPicker: MemoryPhotoPicker(
    photo: YgdkPhotoInput(
      bytes: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=',
      ),
      fileName: 'inspection.png',
      mimeType: 'image/png',
    ),
  ),
);
