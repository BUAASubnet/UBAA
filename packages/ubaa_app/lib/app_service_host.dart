/// 安装级应用服务的 GUI 与无窗口命令入口接线。
library;

import 'dart:convert';
import 'dart:io';

import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/telemetry.dart';

import 'src/bridge/app_service.dart';

export 'package:ubaa_bindings/ubaa_bindings.dart' show BridgeAppServiceSurface;

const _serviceUrl = String.fromEnvironment('UBAA_APP_SERVICE_URL');
const _channel = String.fromEnvironment('UBAA_DISTRIBUTION_CHANNEL');

/// 构建缺少配置时不读取版本、不打开共享存储。Core 负责地址和版本校验。
Future<BridgeAppService?> openConfiguredAppService({
  required String configDirectory,
  required BridgeAppServiceSurface surface,
  required bool release,
  required Future<String?> Function() readVersion,
  Duration budget = const Duration(seconds: 2),
}) async {
  if (_serviceUrl.isEmpty || _channel.isEmpty || budget <= Duration.zero) {
    return null;
  }
  final platform = switch (Platform.operatingSystem) {
    'android' => BridgeAppServicePlatform.android,
    'ios' => BridgeAppServicePlatform.ios,
    'ohos' => BridgeAppServicePlatform.ohos,
    'macos' => BridgeAppServicePlatform.macos,
    'windows' => BridgeAppServicePlatform.windows,
    'linux' => BridgeAppServicePlatform.linux,
    _ => null,
  };
  if (platform == null) return null;
  try {
    final elapsed = Stopwatch()..start();
    final version = await readVersion().timeout(budget);
    final remaining = budget - elapsed.elapsed;
    if (version == null || remaining <= Duration.zero) return null;
    var expired = false;
    return await BridgeAppService.open(
          configDir: configDirectory,
          serviceUrl: _serviceUrl,
          channel: _channel,
          appVersion: version,
          platform: platform,
          release: release,
          surface: surface,
          policyVersion: bundledPrivacyPolicy.version,
        )
        .then<BridgeAppService?>((service) {
          if (!expired) return service;
          service.dispose();
          return null;
        })
        .timeout(
          remaining,
          onTimeout: () {
            expired = true;
            return null;
          },
        );
  } on Object {
    // 安装包信息或共享存储不可用时，业务仍可使用。
    return null;
  }
}

/// 命令学校客户端读取共享门控；打开本机句柄不发送启动配置请求。
Future<BridgeClient> openConfiguredCommandClient({
  required String configDirectory,
  required bool release,
  required Future<String?> Function() readVersion,
}) async {
  final service = await openConfiguredAppService(
    configDirectory: configDirectory,
    surface: BridgeAppServiceSurface.command,
    release: release,
    readVersion: readVersion,
  );
  if (service == null) return BridgeClient.open(configDir: configDirectory);
  try {
    return await BridgeClient.openWithAppService(
      configDir: configDirectory,
      appService: service,
    );
  } finally {
    service.dispose();
  }
}

/// Linux 无 Engine 命令读取同一安装包的版本清单。
/// 独立 AOT 产物由构建入口嵌入版本，不依赖 Flutter 插件。
Future<String?> linuxCommandAppVersion() async {
  const standalone = String.fromEnvironment('UBAA_COMMAND_APP_VERSION');
  if (standalone.isNotEmpty) return standalone;
  try {
    final directory = File(Platform.resolvedExecutable).parent.path;
    final manifest = File('$directory/data/flutter_assets/version.json');
    final data =
        jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    final version = data['version'] as String?;
    final build = data['build_number'] as String?;
    if (version == null || version.isEmpty) return null;
    return build == null || build.isEmpty ? version : '$version+$build';
  } on Object {
    return null;
  }
}

/// 命令输出后才打开应用服务；整个过程共用调用方剩余预算。
Future<void> uploadConfiguredCommandAppService({
  required Future<String> Function() resolveDirectory,
  required Duration budget,
  required bool release,
  required Future<String?> Function() readVersion,
  ({BridgeSharedAccount scope, String expectedUsername})? account,
}) async {
  if (_serviceUrl.isEmpty || _channel.isEmpty) return;
  final elapsed = Stopwatch()..start();
  final directory = await resolveDirectory();
  final service = await openConfiguredAppService(
    configDirectory: directory,
    surface: BridgeAppServiceSurface.command,
    release: release,
    readVersion: readVersion,
    budget: budget - elapsed.elapsed,
  );
  if (service == null) return;
  try {
    if (account != null) {
      service.bindAccount(
        scope: account.scope,
        expectedUsername: account.expectedUsername,
      );
    }
    final track = TelemetryClient(
      enabled: true,
      sink: (event) => bridgeRecordAppService(service, event),
    );
    await track
        .track(TelemetryEvents.appStarted)
        .timeout(budget - elapsed.elapsed, onTimeout: () {});
    final remaining = (budget - elapsed.elapsed).inMilliseconds;
    if (remaining > 0) {
      await service.upload(force: false, budgetMillis: remaining);
    }
  } finally {
    service.dispose();
  }
}
