import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../write_harness.dart';
import '../navigation.dart';
import '../../features/ygdk/actions_test.dart' show fixtureYgdkSnapshots;

Future<YgdkPhotoInput> fixtureValidYgdkPhoto() async => YgdkPhotoInput(
  bytes: base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
    'AAAADUlEQVQIHWP4z8DwHwAFgAI/ScLZYQAAAABJRU5ErkJggg==',
  ),
  fileName: 'photo.png',
  mimeType: 'image/png',
);

Future<void> fixturePumpYgdkShell(
  WidgetTester tester, {
  required Key key,
  YgdkSubmitPreparer? prepare,
  YgdkPhotoPicker? picker,
  YgdkPhotoPicker? camera,
  Future<WriteCommitResult> Function(String intentId)? commit,
  WriteIntentDiscarder? discard,
  YgdkSubmissionRefresher? refresh,
}) => tester.pumpWidget(
  MaterialApp(
    theme: UbaaTheme.light(),
    home: coordinatedShell(
      key: key,
      user: const UserSummary(username: 'student'),
      snapshots: fixtureYgdkSnapshots(),
      routePolicy: RoutePolicy.auto,
      telemetryEnabled: false,
      onRefresh: () async {},
      onRetryFeature: (_) async {},
      onPrepareYgdkSubmitWrite: prepare,
      onPickYgdkPhoto: picker,
      onCaptureYgdkPhoto: camera,
      onCommitWrite: commit,
      onRefreshYgdkAfterWrite: refresh,
      onDiscardWriteIntent: discard,
      onLogout: () async {},
      onLogoutAndClearAccount: () async {},
      onRoutePolicyChanged: (_) {},
      onTelemetryChanged: (_) {},
    ),
  ),
);

Future<void> fixtureOpenYgdkDetails(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
  await tester.pumpAndSettle();
  await openFeature(tester, FeatureId.ygdk);
  await tester.pumpAndSettle();
}

Future<void> fixtureOpenAndFillYgdkForm(WidgetTester tester) async {
  await fixtureOpenYgdkDetails(tester);
  await tester.tap(find.text('准备阳光打卡'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextField, '开始时间'),
    '2026-09-01 08:00',
  );
  await tester.enterText(
    find.widgetWithText(TextField, '结束时间'),
    '2026-09-01 09:00',
  );
  await tester.ensureVisible(find.text('选择照片'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('选择照片'));
  await tester.pumpAndSettle();
}
