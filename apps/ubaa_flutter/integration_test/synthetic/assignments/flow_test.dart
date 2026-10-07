import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_flutter/main.dart';
import 'backend.dart';
import 'fixture_contract.dart';

part 'support.dart';
part 'normal.dart';
part 'states.dart';

const _features = [
  FeatureId.spoc,
  FeatureId.judge,
  FeatureId.signin,
  FeatureId.evaluation,
];
final _brightnesses = Brightness.values.where((value) {
  const requested = String.fromEnvironment('UBAA_COURSEWORK_BRIGHTNESS');
  return requested.isEmpty || value.name == requested;
});

void main() {
  if (_brightnesses.isEmpty) throw ArgumentError('无效的原生测试主题');
  // 独立合成巡检入口；不读取.env.local或会话，不创建真实客户端。

  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerCourseworkFixtureContract();
  _registerNormal(binding);
  if (!const bool.fromEnvironment('UBAA_COURSEWORK_NORMAL_ONLY')) {
    _registerStates(binding);
  }
}

/// 人工巡检专用构造；自动测试入口不读取巡检模式开关。
Future<void> runInspection() async {
  if (_brightnesses.isEmpty) throw ArgumentError('无效的原生测试主题');

  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    UbaaFlutterApp(
      backend: CourseworkBackend(
        state: const String.fromEnvironment(
          'UBAA_UI_STATE',
          defaultValue: 'normal',
        ),
      )..signedIn = true,
      credentialVault: MemoryCredentialVault(),
    ),
  );
  return;
}
