import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

part 'widgets/accessibility.dart';
part 'widgets/feature_details.dart';
part 'widgets/goldens.dart';
part 'widgets/queries.dart';
part 'widgets/shell.dart';
part 'widgets/signin_writes.dart';
part 'widgets/states.dart';
part 'widgets/writes.dart';

void main() {
  _registerGoldenTests();
  _registerResponsiveAccessibilityTests();
  _registerShellTests();
  _registerFeatureRenderingTests();
  _registerInitialWriteTests();
  _registerSigninWriteResultTests();
  _registerBykcStateTests();
  _registerCgyyCancellationWriteTest();
  _registerCgyyStateTest();
  _registerLibbookCancellationWriteTest();
  _registerLibbookStateTest();
  _registerFeatureInputTests();
  _registerRemainingWriteTests();
  _registerFeatureCollectionTests();
  _registerQueryTests();
  _registerSharedStateTests();
  _registerFeatureCardSemanticsTest();
}
