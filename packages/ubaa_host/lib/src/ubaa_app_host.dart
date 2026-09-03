import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

part 'callbacks.dart';
part 'lifecycle.dart';

const _expectedBridgeHello = 'UBAA FRB 2.13.0 ready';

/// 按固定顺序初始化平台边界并启动共享宿主。
///
/// SDK 初始化、平台能力创建失败时，错误原样向上传播；debug 构建还会断言
/// hello。失败后不会继续执行，也不会用演示数据伪造可用状态。
Future<void> bootstrapUbaaHost({
  required void Function() ensureFlutterInitialized,
  required Future<void> Function() initializeSdk,
  required String Function() debugHello,
  required Future<PlatformCapabilities> Function() createCapabilities,
  required void Function(Widget app) runApplication,
}) async {
  ensureFlutterInitialized();
  await initializeSdk();
  assert(debugHello() == _expectedBridgeHello);
  final capabilities = await createCapabilities();
  runApplication(
    UbaaAppHost(
      credentialVault: capabilities.credentialVault,
      photoPicker: capabilities.photoPicker,
      permissionGateway: capabilities.permissionGateway,
    ),
  );
}

/// Flutter 与 HarmonyOS 共用的应用组合根。
///
/// 页面、主题、controller 生命周期和 UI callback 均由此处统一接线。生产
/// 默认使用 FRB backend；widget 测试可以显式注入脱敏 backend。
class UbaaAppHost extends StatefulWidget {
  const UbaaAppHost({
    this.backend,
    this.backendFactory,
    this.credentialVault,
    this.photoPicker,
    this.permissionGateway,
    this.initialTab = 0,
    this.telemetry,
    super.key,
  });

  final UbaaBackend? backend;

  /// 仅在没有显式 [backend] 时使用；同一工厂也负责宿主恢复后的 backend
  /// 重建。为空时使用 [createProductionBackend]。
  final BackendFactory? backendFactory;

  final CredentialVault? credentialVault;
  final PlatformPhotoPicker? photoPicker;
  final PlatformPermissionGateway? permissionGateway;
  final int initialTab;
  final TelemetryClient? telemetry;

  @override
  State<UbaaAppHost> createState() => _UbaaAppHostState();
}
