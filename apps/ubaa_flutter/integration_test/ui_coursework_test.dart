import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_flutter/main.dart';
import 'ui_coursework/backend.dart';
import 'ui_coursework/fixture_contract.dart';

part 'ui_coursework/support.dart';
part 'ui_coursework/normal.dart';
part 'ui_coursework/states.dart';

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
  if (const bool.fromEnvironment('UBAA_UI_INSPECTION')) {
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
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerCourseworkFixtureContract();
  _registerNormal(binding);
  if (!const bool.fromEnvironment('UBAA_COURSEWORK_NORMAL_ONLY')) {
    _registerStates(binding);
  }
}
