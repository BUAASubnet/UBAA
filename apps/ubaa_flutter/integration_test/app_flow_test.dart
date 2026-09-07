import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_flutter/main.dart';

part 'app_flow/auth.dart';
part 'app_flow/inspection.dart';
part 'app_flow/query.dart';
part 'app_flow/support.dart';
part 'app_flow/write.dart';

void main() {
  // 显式测试入口供原生设备人工巡检，复用全部写入的脱敏 backend。
  // 生产 main.dart 不读取此开关，也不会在失败时切换为演示数据。
  if (const bool.fromEnvironment('UBAA_UI_INSPECTION')) {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(
      UbaaFlutterApp(
        backend: _InspectionBackend(),
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
    return;
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  _registerAuthFlowTests();
  _registerPrimaryWriteFlowTests();
  _registerQueryFlowTests();
  _registerWriteMatrixFlowTest();
}
