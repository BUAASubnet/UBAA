import 'package:integration_test/integration_test.dart';
import 'package:flutter/material.dart';
import '../../../../../packages/ubaa_host/test/cache/settings_test.dart'
    as scenarios;

// 使用明确合成 backend 与内存安全材料；不读取真实账号，不发送学校请求。
Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  scenarios.main();
}

/// 人工巡检专用构造；自动测试入口不读取巡检模式开关。
Future<void> runInspection() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(await scenarios.buildSyntheticCacheInspection());
  return;
}
