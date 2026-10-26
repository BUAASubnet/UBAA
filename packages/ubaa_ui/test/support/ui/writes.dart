import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../write_harness.dart';
import '../navigation.dart';

Future<int> fixturePumpBykcCommitError(
  WidgetTester tester,
  Object error,
) async {
  var refreshCalls = 0;
  final snapshots = <FeatureId, FeatureSnapshot>{
    for (final feature in FeatureId.values)
      feature: FeatureSnapshot(
        feature: feature,
        status: FeatureLoadStatus.success,
        summary: '已加载',
        details: feature == FeatureId.bykc
            ? const <FeatureDetail>[
                FeatureDetail(
                  title: '课程',
                  actions: <FeatureAction>[
                    BykcSelectAction(
                      courseId: 42,
                      eligibility: ActionEligibility.allowed,
                    ),
                  ],
                ),
              ]
            : const <FeatureDetail>[],
      ),
  };
  final intent = WriteIntent(
    intentId: 'throwing-intent',
    operation: WriteOperation.bykcSelectCourse,
    targetSummary: '选择课程 42',
    resolvedRoute: ConnectionMode.direct,
    warnings: const <String>[],
    expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    requestDigest: 'digest',
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: UbaaTheme.light(),
      home: coordinatedShell(
        user: const UserSummary(username: 'student'),
        snapshots: snapshots,
        routePolicy: RoutePolicy.auto,
        telemetryEnabled: false,
        onRefresh: () async {},
        onRetryFeature: (_) async {},
        onPrepareBykcWrite: (_, __) async => intent,
        onCommitWrite: (_) async => throw error,
        onWriteSuccess: (_, __) async => refreshCalls++,
        onLogout: () async {},
        onLogoutAndClearAccount: () async {},
        onRoutePolicyChanged: (_) {},
        onTelemetryChanged: (_) {},
      ),
    ),
  );
  await openFeature(tester, FeatureId.bykc);
  await tester.pumpAndSettle();
  await tester.tap(find.text('选课'));
  await tester.pumpAndSettle();
  return refreshCalls;
}
