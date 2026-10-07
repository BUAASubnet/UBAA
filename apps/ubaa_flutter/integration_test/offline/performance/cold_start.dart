import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'backend.dart';
import 'measurement.dart';

/// 此入口单独构建；不替换发布 main，不读取原账号索引或复制既有会话。
Future<void> main() async {
  final enteredAt = DateTime.now().microsecondsSinceEpoch;
  WidgetsFlutterBinding.ensureInitialized();
  await initializePrivateDirectory();
  final environment = Platform.environment;
  final values = <String, String>{};
  for (final key in [
    'UBAA_CONFIG_DIR',
    'UBAA_LIVE_MATERIAL_SCOPE',
    'UBAA_STARTUP_OUTPUT',
    'UBAA_STARTUP_MODE',
    'UBAA_EXPECTED_ROUTE',
    'UBAA_STARTUP_SCENARIO',
  ]) {
    final value = environment[key];
    if (value != null) values[key] = value;
  }
  if (values.length < 5) {
    // simctl launch 在部分宿主版本不会把 SIMCTL_CHILD_ 变量传入 Flutter
    // isolate；run.py 将同样的非敏感入口配置写入应用私有目录，仅供本轮探针读取。
    try {
      final marker = File(
        '${defaultConfigDirectory()}/startup-measurement.json',
      );
      final decoded = jsonDecode(await marker.readAsString());
      if (decoded is Map) {
        for (final key in [
          'UBAA_CONFIG_DIR',
          'UBAA_LIVE_MATERIAL_SCOPE',
          'UBAA_STARTUP_OUTPUT',
          'UBAA_STARTUP_MODE',
          'UBAA_EXPECTED_ROUTE',
          'UBAA_STARTUP_SCENARIO',
        ]) {
          final value = decoded[key];
          if (value is String) values[key] = value;
        }
      }
    } on Object {
      // 下面的统一校验会输出失败状态；不猜测默认目录或路线。
    }
  }
  final config = values['UBAA_CONFIG_DIR'] ?? '';
  final scope = values['UBAA_LIVE_MATERIAL_SCOPE'] ?? '';
  final output = values['UBAA_STARTUP_OUTPUT'] ?? '';
  final mode = values['UBAA_STARTUP_MODE'];
  final route = values['UBAA_EXPECTED_ROUTE'];
  final scenario = values['UBAA_STARTUP_SCENARIO'] ?? 'online';
  stdout.writeln(
    'startup_config_present=${jsonEncode(<String, bool>{'config': environment.containsKey('UBAA_CONFIG_DIR'), 'scope': environment.containsKey('UBAA_LIVE_MATERIAL_SCOPE'), 'output': environment.containsKey('UBAA_STARTUP_OUTPUT'), 'mode': environment.containsKey('UBAA_STARTUP_MODE'), 'route': environment.containsKey('UBAA_EXPECTED_ROUTE'), 'scenario': environment.containsKey('UBAA_STARTUP_SCENARIO')})}',
  );
  if (!Directory(config).isAbsolute ||
      !config.contains('UBAA-ui-readonly-offline-') ||
      !RegExp(r'^offline-live-[a-f0-9]{32}$').hasMatch(scope) ||
      !output.startsWith('$config/') ||
      !output.endsWith('.json') ||
      !{'prepare', 'sample'}.contains(mode) ||
      !{'direct', 'webvpn'}.contains(route) ||
      !{'online', 'recoveryHeld', 'recoveryFailed'}.contains(scenario)) {
    throw StateError('只读进程测量必须使用独立私有目录、材料命名空间及明确路线');
  }
  final measurement = StartupMeasurement(File(output), route!, scenario)
    ..mark('dart_main_us', enteredAt);
  try {
    await measurement.observe('initializeSdk', RustLib.init);
    final capabilities = await measurement.observe(
      'platformCapabilities',
      createDefaultPlatformCapabilities,
    );
    final materials = SecureMaterialStore(transport: _IsolatedMaterials(scope));
    await materials.probe();
    final accounts = SecureLocalAccountStore(materials);
    if (mode == 'prepare') {
      runApp(const MaterialApp(home: Scaffold(body: Text('正在准备只读启动测量'))));
      await _prepare(config, accounts, measurement);
      await measurement.finish('prepared');
      return;
    }
    measurement.watchFrames();
    runApp(
      UbaaAppHost(
        backendFactory: () => MeasuredBackend(config, measurement),
        networkChanges: LocalNetworkMonitor().changes,
        localAccountStore: accounts,
        credentialVault: const NoopCredentialVault(),
        photoPicker: capabilities.photoPicker,
        permissionGateway: capabilities.permissionGateway,
        locationProvider: capabilities.locationProvider,
        reminderStore: PreferencesYgdkReminderStore(scope: config),

        onReadSchedulerTrace: measurement.recordScheduler,
        onGradeCheckComplete: measurement.markGradeCheckComplete,
      ),
    );
  } on Object {
    await measurement.finish('failed');
    rethrow;
  }
}

Future<void> _prepare(
  String config,
  SecureLocalAccountStore accounts,
  StartupMeasurement measurement,
) async {
  final backend = MeasuredBackend(config, measurement);
  try {
    await backend.client.setDefaultRoutePolicy(
      policy: measurement.route == 'direct'
          ? BridgeRoutePolicy.direct
          : BridgeRoutePolicy.webVpn,
    );
    final recovered = await backend.recoverRequiredSession(FeatureId.schedule);
    if (recovered.route.name != measurement.route) {
      throw StateError('只读准备的实际路线不匹配');
    }
    final account = (await accounts.retain(
      recovered.profile.username,
      retainSession: true,
    )).account!;
    final key = await accounts.cacheKey(account);
    try {
      await backend.openOfflineAccount(account, key);
    } finally {
      key.fillRange(0, key.length, 0);
    }
    for (final feature in measuredFeatures) {
      final task = await backend.beginAccountFeatureRead(
        feature,
        null,
        account,
      );
      FeatureResult? result;
      if (task == null) {
        result = await backend.loadFeature(feature);
      } else {
        try {
          while (true) {
            final batch = await task.next();
            if (batch.publish) result = batch.result;
            if (batch.finished) break;
          }
        } finally {
          task.cancel();
        }
      }
      measurement.outcomes[feature.name] = {
        'count': result?.details.length,
        'complete': result?.evidence?.complete,
        'saved': result?.evidence?.savedForOffline,
        'error': result?.error?.code.name,
      };
      if (result?.error != null || result?.evidence?.savedForOffline != true) {
        throw StateError('只读准备未完整保存首页来源');
      }
    }
  } finally {
    await backend.dispose();
  }
}

class _IsolatedMaterials implements SecureMaterialTransport {
  _IsolatedMaterials(this.scope);
  final String scope;
  final _native = const PlatformSecureMaterialTransport();
  String key(String value) => '$scope.$value';
  @override
  Future<String?> read(String value) => _native.read(key(value));
  @override
  Future<void> write(String value, String body) =>
      _native.write(key(value), body);
  @override
  Future<void> delete(String value) => _native.delete(key(value));
}
