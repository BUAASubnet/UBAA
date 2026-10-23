import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../../support/navigation.dart';

void main() {
  testWidgets('评教部分缓存不显示零待评结论，恢复期间仍保留只读课程', (tester) async {
    await tester.pumpWidget(_page(FeatureLoadStatus.stale));
    await tester.pumpAndSettle();
    await openFeature(tester, FeatureId.evaluation);
    expect(find.text('已保存评教课程'), findsOneWidget);
    expect(find.text('待评 0 门'), findsNothing);
    expect(find.textContaining('评教任务尚未核对完整'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('准备评教'), findsNothing);
    await tester.pumpWidget(_page(FeatureLoadStatus.loading));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('已保存评教课程'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _page(FeatureLoadStatus status) => MaterialApp(
  home: UbaaMainShell(
    initialDestination: UiDestination.academic,
    user: const UserSummary(username: 'synthetic'),
    snapshots: {
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: feature == FeatureId.evaluation
              ? status
              : FeatureLoadStatus.success,
          evidence: feature == FeatureId.evaluation
              ? DataEvidence(
                  accountId: 'synthetic',
                  origin: DataOrigin.persisted,
                  fetchedAt: DateTime(2026, 9, 22),
                  complete: false,
                  savedForOffline: true,
                )
              : null,
          overview: feature == FeatureId.evaluation
              ? const EvaluationProgressOverview(
                  totalCourses: 0,
                  evaluatedCourses: 0,
                  pendingCourses: 0,
                )
              : null,
          details: feature == FeatureId.evaluation
              ? [
                  FeatureDetail(
                    title: '已保存评教课程',
                    presentation: const EvaluationCoursePresentation(
                      courseId: 'synthetic',
                      isEvaluated: false,
                    ),
                  ),
                ]
              : const [],
        ),
    },
    routePolicy: RoutePolicy.direct,
    telemetryEnabled: false,
    onRefresh: () async {},
    onRetryFeature: (_) async {},
    onLogout: () async {},
    onLogoutAndClearAccount: () async {},
    onRoutePolicyChanged: (_) {},
    onTelemetryChanged: (_) {},
  ),
);
