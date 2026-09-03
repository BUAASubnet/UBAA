import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

part 'app_controller/auth.dart';
part 'app_controller/fakes.dart';
part 'app_controller/lifecycle.dart';
part 'app_controller/race.dart';
part 'app_controller/read.dart';
part 'app_controller/write.dart';

void main() {
  _registerAuthTests();
  _registerReadTests();
  _registerLifecycleTests();
  _registerRaceTests();
  _registerWriteTests();
}
