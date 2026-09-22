import 'package:integration_test/integration_test.dart';
import 'package:flutter/material.dart';
import '../../../../packages/ubaa_host/test/cache_settings_test.dart'
    as scenarios;

// 使用明确合成 backend 与内存安全材料；不读取真实账号，不发送学校请求。
Future<void> main() async {
  if (const bool.fromEnvironment('UBAA_UI_INSPECTION')) {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(await scenarios.buildSyntheticCacheInspection());
    return;
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  scenarios.main();
}
