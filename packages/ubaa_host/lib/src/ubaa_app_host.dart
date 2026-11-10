import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:ubaa_app/app_service_host.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

import 'crash_handlers.dart';

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
  Future<ThemeMode> Function()? readThemeMode,
}) async {
  ensureFlutterInitialized();
  // 首帧前有限等待保存的主题，启动页与宿主使用同一初值。
  final themeMode = await _readStartupThemeMode(readThemeMode);
  // 先画启动页再做 SDK 与钥匙串等初始化，避免原生启动图长时间停留。
  runApplication(UbaaBootSplash(themeMode: themeMode));
  var stage = 'SDK 初始化';
  try {
    await initializeSdk();
    stage = 'Bridge 自检';
    assert(debugHello() == _expectedBridgeHello);
    stage = '平台能力初始化';
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
        initialThemeMode: themeMode,
      ),
    );
  } on Object catch (error, stackTrace) {
    final diagnostics = LocalDiagnostics();
    final safe = error is InitializationException
        ? error
        : const InitializationException(
            InitializationFailure.componentUnavailable,
          );
    final failure = diagnostics.record(
      operation: DiagnosticOperation.initialization,
      error: const UiErrorMapper().fromException(safe),
      cause: error,
      stackTrace: stackTrace,
    );
    runApplication(
      _startupApplication(
        themeMode: themeMode,
        home: _StartupFailure(
          error: failure,
          stage: stage,
          diagnostics: diagnostics.exportText(),
        ),
      ),
    );
    rethrow;
  }
}

/// 有限等待偏好读取；超时或失败时跟随系统，继续启动首帧。
Future<ThemeMode> _readStartupThemeMode(
  Future<ThemeMode> Function()? read,
) async {
  try {
    return await Future<ThemeMode>.sync(
      read ??
          () async =>
              ThemeMode.values.byName(await ThemePreferenceStore().read()),
    ).timeout(
      const Duration(milliseconds: 300),
      onTimeout: () => ThemeMode.system,
    );
  } on Object {
    return ThemeMode.system;
  }
}

/// 启动页使用首帧前读出的主题，与宿主保持一致。
class UbaaBootSplash extends StatelessWidget {
  const UbaaBootSplash({super.key, this.themeMode = ThemeMode.system});
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) =>
      _startupApplication(themeMode: themeMode, home: const UbaaSplashView());
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
    this.agendaFileSaver = const SystemAgendaFileSaver(),
    this.bhpanFilePicker = const SystemBhpanFilePicker(),
    this.bhpanFileSaver = const SystemBhpanFileSaver(),
    this.bhpanFilePreviewer = const SystemBhpanFilePreviewer(),
    this.initialThemeMode = ThemeMode.system,
    this.nativeThemeSync,
    this.telemetry,
    this.reminderStore,
    this.gradeScoreStore,
    this.bykcFilterStore,
    this.cgyyDefaultsStore,
    this.recentFeatureStore,
    this.preferenceValues,
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
  /// 重建。为空时打开生产后端和应用服务。
  final BackendFactory? backendFactory;

  final CredentialVault? credentialVault;
  final LocalAccountStore? localAccountStore;
  final PlatformPhotoPicker? photoPicker;
  final PlatformPermissionGateway? permissionGateway;
  final PlatformLocationProvider? locationProvider;
  final UiDestination initialDestination;
  final AgendaFileSaver agendaFileSaver;
  final BhpanFilePicker bhpanFilePicker;
  final BhpanFileSaver bhpanFileSaver;
  final BhpanFilePreviewer bhpanFilePreviewer;

  /// 启动时已读出的主题；宿主随后仍会从偏好复核。
  final ThemeMode initialThemeMode;
  final NativeThemeSync? nativeThemeSync;
  final TelemetryClient? telemetry;
  final YgdkReminderStore? reminderStore;
  final GradeScoreStore? gradeScoreStore;
  final BykcCourseFilterStore? bykcFilterStore;
  final CgyyReservationDefaultsStore? cgyyDefaultsStore;
  final RecentFeatureStore? recentFeatureStore;
  final PreferenceValues? preferenceValues;
  final PlatformAppInformation? appInformation;
  final void Function(ReadSchedulerTrace trace)? onReadSchedulerTrace;
  final void Function(bool persisted)? onGradeCheckComplete;
  final ScheduleWidgetGateway? scheduleWidgetGateway;

  @override
  State<UbaaAppHost> createState() => _UbaaAppHostState();
}
