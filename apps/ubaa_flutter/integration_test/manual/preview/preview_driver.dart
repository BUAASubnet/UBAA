import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_flutter/main.dart';
import 'preview_backend.dart';

/// 全平台人工预览入口，不初始化 FRB，不连接学校服务。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    UbaaFlutterApp(
      backend: PreviewBackend(
        state: const String.fromEnvironment(
          'UBAA_UI_STATE',
          defaultValue: 'normal',
        ),
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
    ),
  );
}
