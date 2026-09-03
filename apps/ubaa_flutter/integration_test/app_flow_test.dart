import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_flutter/main.dart';

part 'app_flow/auth.dart';
part 'app_flow/query.dart';
part 'app_flow/support.dart';
part 'app_flow/write.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  _registerAuthFlowTests();
  _registerPrimaryWriteFlowTests();
  _registerQueryFlowTests();
  _registerWriteMatrixFlowTest();
}
