import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

part 'app_controller/auth.dart';
part 'app_controller/evaluation.dart';
part 'app_controller/fakes.dart';
part 'app_controller/lifecycle.dart';
part 'app_controller/race.dart';
part 'app_controller/read.dart';
part 'app_controller/overview.dart';
part 'app_controller/read_context.dart';
part 'app_controller/academic_terms.dart';
part 'app_controller/academic_weeks.dart';
part 'app_controller/cgyy_purposes.dart';
part 'app_controller/grades.dart';
part 'app_controller/grade_watch.dart';
part 'app_controller/home_sources.dart';
part 'app_controller/write.dart';
part 'app_controller/ygdk.dart';

void main() {
  _registerOverviewTests();
  _registerAuthTests();
  _registerReadTests();
  _registerReadContextTests();
  _registerAcademicTermsTests();
  _registerAcademicWeeksTests();
  _registerCgyyPurposeTests();
  _registerGradesTests();
  _registerGradeWatchTests();
  _registerHomeSourceTests();
  _registerLifecycleTests();
  _registerRaceTests();
  _registerEvaluationTests();
  _registerWriteTests();
  _registerYgdkWriteTests();
}
