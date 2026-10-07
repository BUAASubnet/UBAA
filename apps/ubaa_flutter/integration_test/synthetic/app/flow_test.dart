import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_flutter/main.dart';

part 'flow/auth.dart';
part 'flow/navigation.dart';
part 'flow/inspection.dart';
part 'flow/inspection_lock.dart';
part 'flow/inspection_academic.dart';
part 'flow/inspection_contract.dart';
part 'flow/query.dart';
part 'flow/support.dart';
part 'flow/write.dart';

void main() {
  // 显式测试入口供原生设备人工巡检，复用全部写入的脱敏 backend。
  // 生产 main.dart 不读取此开关，也不会在失败时切换为演示数据。

  WidgetController.hitTestWarningShouldBeFatal = true;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  _registerAuthFlowTests();
  _registerPrimaryWriteFlowTests();
  _registerQueryFlowTests();
  _registerWriteMatrixFlowTest();
}

/// 显式合成巡检宿主；不创建真实客户端，也不读取本机账号。
Widget createInspectionApp({String state = 'normal'}) => UbaaFlutterApp(
  backend: _InspectionBackend(state: state),
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

/// 人工巡检专用构造；自动测试入口不读取巡检模式开关。
Future<void> runInspection() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    createInspectionApp(
      state: const String.fromEnvironment(
        'UBAA_UI_STATE',
        defaultValue: 'normal',
      ),
    ),
  );
  return;
}
