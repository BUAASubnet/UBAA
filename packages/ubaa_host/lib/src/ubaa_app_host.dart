import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

part 'callbacks.dart';
part 'lifecycle.dart';
part 'startup.dart';
part 'session.dart';
part 'local_data.dart';
part 'schedule_widgets.dart';

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
      localAccountStore: capabilities.secureMaterials?.isAvailable == true
          ? SecureLocalAccountStore(capabilities.secureMaterials!)
          : null,
      photoPicker: capabilities.photoPicker,
      permissionGateway: capabilities.permissionGateway,
      locationProvider: capabilities.locationProvider,
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
    this.networkChanges,
    this.credentialVault,
    this.localAccountStore,
    this.photoPicker,
    this.permissionGateway,
    this.locationProvider,
    this.initialDestination = UiDestination.home,
    this.telemetry,
    this.reminderStore,
    this.gradeScoreStore,
    this.bykcFilterStore,
    this.recentFeatureStore,
    this.appInformation,
    this.onReadSchedulerTrace,
    this.onGradeCheckComplete,
    this.scheduleWidgetGateway,
    super.key,
  });

  final UbaaBackend? backend;

  /// 可注入的本地网络变化提示；显式脱敏backend默认不观察真实系统接口。
  final Stream<void>? networkChanges;

  /// 仅在没有显式 [backend] 时使用；同一工厂也负责宿主恢复后的 backend
  /// 重建。为空时使用 [createProductionBackend]。
  final BackendFactory? backendFactory;

  final CredentialVault? credentialVault;
  final LocalAccountStore? localAccountStore;
  final PlatformPhotoPicker? photoPicker;
  final PlatformPermissionGateway? permissionGateway;
  final PlatformLocationProvider? locationProvider;
  final UiDestination initialDestination;
  final TelemetryClient? telemetry;
  final YgdkReminderStore? reminderStore;
  final GradeScoreStore? gradeScoreStore;
  final BykcCourseFilterStore? bykcFilterStore;
  final RecentFeatureStore? recentFeatureStore;
  final PlatformAppInformation? appInformation;
  final void Function(ReadSchedulerTrace trace)? onReadSchedulerTrace;
  final void Function(bool persisted)? onGradeCheckComplete;
  final ScheduleWidgetGateway? scheduleWidgetGateway;

  @override
  State<UbaaAppHost> createState() => _UbaaAppHostState();
}
