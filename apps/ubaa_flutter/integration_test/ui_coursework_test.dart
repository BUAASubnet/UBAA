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
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerCourseworkFixtureContract();
  _registerNormal(binding);
  if (!const bool.fromEnvironment('UBAA_COURSEWORK_NORMAL_ONLY')) {
    _registerStates(binding);
  }
}
