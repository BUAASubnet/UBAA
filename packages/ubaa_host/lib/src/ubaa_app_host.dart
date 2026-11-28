import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:ubaa_app/app_service_host.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_platform/ubaa_platform.dart'
    as platform
    show openExternalUrl;
import 'package:ubaa_ui/ubaa_ui.dart';

import 'crash_handlers.dart';

part 'app_service.dart';
part 'callbacks.dart';
part 'home_card.dart';
part 'lifecycle.dart';
part 'startup.dart';
part 'session.dart';
part 'local_data.dart';
part 'schedule_widgets.dart';
part 'spoc_files.dart';

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
  Future<UbaaAccent> Function()? readAccent,
  PreferenceValues? preferenceValues,
  PlatformAppInformation? appInformation,
  DiagnosticReportExporter reportExporter = const DiagnosticReportExporter(),
  Future<void> Function(HomeCardSnapshot)? publishHomeCard,
}) async {
  ensureFlutterInitialized();
  final preferences = preferenceValues ?? PluginPreferenceValues();
  final information = appInformation ?? SystemAppInformation();
  final diagnostics = _newStartupDiagnostics(preferences);
  unawaited(_readDiagnosticVersion(diagnostics, information));
  // 首帧前有限等待保存的主题，启动页与宿主使用同一初值。
  final themeStore = ThemePreferenceStore(values: preferences);
  final (themeMode, accent) = await (
    _readStartupPreference(
      readThemeMode ??
          () async => ThemeMode.values.byName(await themeStore.read()),
      ThemeMode.system,
    ),
    _readStartupPreference(
      readAccent ?? () async => UbaaAccent.parse(await themeStore.readAccent()),
      UbaaAccent.blue,
    ),
  ).wait;
  var stage = DiagnosticInitializationStage.sdk;
  Future<void> openPlatform() async {
    final capabilities = await createCapabilities();
    runApplication(
      UbaaAppHost(
        credentialVault: capabilities.credentialVault,
        localAccountStore: capabilities.secureMaterials?.isAvailable == true
            ? SecureLocalAccountStore(capabilities.secureMaterials!)
            : null,
        photoPicker: capabilities.photoPicker,
        galleryImageSaver: capabilities.galleryImageSaver,
        videoPlayback: capabilities.videoPlayback,
        permissionGateway: capabilities.permissionGateway,
        locationProvider: capabilities.locationProvider,
        initialThemeMode: themeMode,
        initialAccent: accent,
        preferenceValues: preferences,
        appInformation: information,
        diagnosticReportExporter: reportExporter,
        startupDiagnostics: diagnostics,
        materialRecovery: capabilities.materialRecovery,
        publishHomeCard: publishHomeCard,
      ),
    );
  }

  void showSplash() =>
      runApplication(UbaaBootSplash(themeMode: themeMode, accent: accent));
  void showFailure(Object error, StackTrace stackTrace) {
    final failure = _recordStartupError(diagnostics, stage, error, stackTrace);
    runApplication(
      _startupApplication(
        themeMode: themeMode,
        accent: accent,
        reportExporter: reportExporter,
        openLink: information.open,
        home: _StartupFailure(
          error: failure,
          stage: stage,
          diagnostics: diagnostics,
          showRestartHint: error is! MaterialTransactionUnrecoverable,
          retryLabel: '重试启动',
          onRetry:
              stage == DiagnosticInitializationStage.platformCapabilities &&
                  error is SecureMaterialException &&
                  error is! MaterialTransactionUnrecoverable
              ? () async {
                  showSplash();
                  try {
                    await openPlatform();
                  } on Object catch (error, stackTrace) {
                    showFailure(error, stackTrace);
                  }
                }
              : null,
        ),
      ),
    );
  }

  // 先画启动页再做 SDK 与钥匙串等初始化，避免原生启动图长时间停留。
  showSplash();
  try {
    await initializeSdk();
    stage = DiagnosticInitializationStage.bridgeCheck;
    assert(debugHello() == _expectedBridgeHello);
    stage = DiagnosticInitializationStage.platformCapabilities;
    await openPlatform();
  } on Object catch (error, stackTrace) {
    showFailure(error, stackTrace);
    rethrow;
  }
}

/// 有限等待偏好读取；超时或失败时使用默认外观，继续启动首帧。
Future<T> _readStartupPreference<T>(
  Future<T> Function() read,
  T fallback,
) async {
  try {
    return await Future<T>.sync(
      read,
    ).timeout(const Duration(milliseconds: 300), onTimeout: () => fallback);
  } on Object {
    return fallback;
  }
}

/// 启动页使用首帧前读出的主题，与宿主保持一致。
class UbaaBootSplash extends StatelessWidget {
  const UbaaBootSplash({
    super.key,
    this.themeMode = ThemeMode.system,
    this.accent = UbaaAccent.blue,
  });
  final ThemeMode themeMode;
  final UbaaAccent accent;

  @override
  Widget build(BuildContext context) => _startupApplication(
    themeMode: themeMode,
    accent: accent,
    home: const UbaaSplashView(),
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
    this.galleryImageSaver = const UnavailableGalleryImageSaver(),
    this.videoPlayback = const UnavailableVideoPlayback(),
    this.permissionGateway,
    this.locationProvider,
    this.initialDestination = UiDestination.home,
    this.agendaFileSaver = const SystemAgendaFileSaver(),
    this.diagnosticReportExporter = const DiagnosticReportExporter(),
    this.bhpanFilePicker = const SystemBhpanFilePicker(),
    this.bhpanFileSaver = const SystemBhpanFileSaver(),
    this.bhpanFilePreviewer = const SystemBhpanFilePreviewer(),
    this.initialThemeMode = ThemeMode.system,
    this.initialAccent = UbaaAccent.blue,
    this.nativeThemeSync,
    this.telemetry,
    this.reminderStore,
    this.gradeScoreStore,
    this.bykcFilterStore,
    this.cgyyDefaultsStore,
    this.recentFeatureStore,
    this.preferenceValues,
    this.appInformation,
    this.startupDiagnostics,
    this.materialRecovery,
    this.publishHomeCard,
    this.onReadSchedulerTrace,
    this.onGradeCheckComplete,
    this.scheduleWidgetGateway,
    this.widgetLaunchChannel,
    this.urlOpener,
    super.key,
  });

  final UbaaBackend? backend;

  /// 可注入的本地网络变化提示；显式脱敏backend默认不观察真实系统接口。
  final Stream<bool>? networkChanges;

  /// 仅在没有显式 [backend] 时使用；同一工厂也负责宿主恢复后的 backend
  /// 重建。为空时打开生产后端和应用服务。
  final BackendFactory? backendFactory;

  final CredentialVault? credentialVault;
  final LocalAccountStore? localAccountStore;
  final PlatformPhotoPicker? photoPicker;
  final GalleryImageSaver galleryImageSaver;
  final VideoPlaybackCapability videoPlayback;
  final PlatformPermissionGateway? permissionGateway;
  final PlatformLocationProvider? locationProvider;
  final UiDestination initialDestination;
  final AgendaFileSaver agendaFileSaver;
  final DiagnosticReportExporter diagnosticReportExporter;
  final BhpanFilePicker bhpanFilePicker;
  final BhpanFileSaver bhpanFileSaver;
  final BhpanFilePreviewer bhpanFilePreviewer;

  /// 启动时已读出的主题；宿主随后仍会从偏好复核。
  final ThemeMode initialThemeMode;
  final UbaaAccent initialAccent;
  final NativeThemeSync? nativeThemeSync;
  final TelemetryClient? telemetry;
  final YgdkReminderStore? reminderStore;
  final GradeScoreStore? gradeScoreStore;
  final BykcCourseFilterStore? bykcFilterStore;
  final CgyyReservationDefaultsStore? cgyyDefaultsStore;
  final RecentFeatureStore? recentFeatureStore;
  final PreferenceValues? preferenceValues;
  final PlatformAppInformation? appInformation;
  final LocalDiagnostics? startupDiagnostics;
  final MaterialTransactionRecovery? materialRecovery;
  final Future<void> Function(HomeCardSnapshot)? publishHomeCard;
  final void Function(ReadSchedulerTrace trace)? onReadSchedulerTrace;
  final void Function(bool persisted)? onGradeCheckComplete;
  final ScheduleWidgetGateway? scheduleWidgetGateway;
  final WidgetLaunchChannel? widgetLaunchChannel;

  /// 打开更新和公告链接；测试可以注入，默认只接受 HTTPS 并交给系统浏览器。
  final Future<bool> Function(Uri url)? urlOpener;

  Future<bool> openExternalUrl(Uri url) =>
      (urlOpener ?? platform.openExternalUrl)(url);

  @override
  State<UbaaAppHost> createState() => _UbaaAppHostState();
}
