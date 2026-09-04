import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

part 'ubaa_app_host/bootstrap.dart';
part 'ubaa_app_host/callbacks.dart';
part 'ubaa_app_host/capability_gates.dart';
part 'ubaa_app_host/fakes.dart';
part 'ubaa_app_host/recording_backend.dart';

void main() {
  _registerBootstrapTests();
  _registerCallbackTests();
  _registerCapabilityGateTests();
}
