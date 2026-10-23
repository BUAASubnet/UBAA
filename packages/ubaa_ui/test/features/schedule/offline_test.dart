import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../../support/navigation.dart';

void main() {
  for (final status in [FeatureLoadStatus.loading, FeatureLoadStatus.stale]) {
    testWidgets('$status已有完整离线索引不等待网络，直接进入已保存周课表', (tester) async {
      final queries = <FeatureQuery>[];
      await _show(tester, queries, status: status);
      await openFeature(tester, FeatureId.schedule);
      expect(queries.map((q) => q.view), [
        FeatureQueryView.scheduleTerms,
        FeatureQueryView.scheduleWeeks,
        FeatureQueryView.scheduleWeek,
      ]);
      expect(queries.last.term, 'term');
      expect(queries.last.week, 4);
      expect(find.text('合成已保存课程'), findsOneWidget);
      expect(find.text('第 4 周'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('部分离线学期索引不能自动选为当前学期', (tester) async {
    final queries = <FeatureQuery>[];
    await _show(
      tester,
      queries,
      status: FeatureLoadStatus.stale,
      complete: false,
    );
    await openFeature(tester, FeatureId.schedule);
    expect(queries.map((q) => q.view), [FeatureQueryView.scheduleTerms]);
  });
}

Future<void> _show(
  WidgetTester tester,
  List<FeatureQuery> queries, {
  required FeatureLoadStatus status,
  bool complete = true,
}) async {
  FeatureSnapshot snapshot = const FeatureSnapshot(feature: FeatureId.schedule);
  final evidence = DataEvidence(
    accountId: 'synthetic',
    origin: DataOrigin.persisted,
    fetchedAt: DateTime.utc(2026, 9, 7),
    complete: complete,
    savedForOffline: true,
  );
  List<FeatureDetail> details(FeatureQuery q) => switch (q.view) {
    FeatureQueryView.scheduleTerms => const [
      FeatureDetail(
        title: '合成学期',
        presentation: TermPresentation(code: 'term', selected: true, index: 1),
      ),
    ],
    FeatureQueryView.scheduleWeeks => const [
      FeatureDetail(
        title: '第 4 周',
        presentation: WeekPresentation(
          requestTerm: 'term',
          responseTerm: 'term',
          number: 4,
          current: true,
          startDate: '2026-09-07',
          endDate: '2026-09-13',
        ),
      ),
    ],
    _ => const [
      FeatureDetail(
        title: '合成已保存课程',
        presentation: ScheduleCoursePresentation(
          courseCode: 'c',
          dayOfWeek: 1,
          beginSection: 1,
          endSection: 2,
        ),
      ),
    ],
  };
  await tester.pumpWidget(
    MaterialApp(
      home: StatefulBuilder(
        builder: (context, update) => UbaaMainShell(
          user: const UserSummary(username: 'synthetic'),
          initialDestination: UiDestination.academic,
          snapshots: {
            for (final feature in FeatureId.values)
              feature: feature == FeatureId.schedule
                  ? snapshot
                  : FeatureSnapshot(feature: feature),
          },
          routePolicy: RoutePolicy.direct,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
          onLoadAcademicWeeks: (term, _) async => FeatureResult.success(
            details: details(
              FeatureQuery(view: FeatureQueryView.scheduleWeeks, term: term),
            ),
            resolvedRoute: ConnectionMode.direct,
            evidence: evidence,
          ),
          onFeatureQuery: (_, query) async {
            queries.add(query);
            update(
              () => snapshot = FeatureSnapshot(
                feature: FeatureId.schedule,
                status: status,
                details: details(query),
                readContext: FeatureReadContext(
                  query: query,
                  requestRevision: queries.length,
                ),
                resolvedRoute: ConnectionMode.direct,
                evidence: evidence,
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
