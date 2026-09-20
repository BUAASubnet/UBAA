import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../support/navigation.dart';

void main() {
  testWidgets('研究生成绩显示 Core 统计且不启动本科跨学期统计', (tester) async {
    var undergraduateLoads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: UbaaMainShell(
          user: const UserSummary(username: 'fixture'),
          snapshots: {
            for (final id in FeatureId.values)
              id: FeatureSnapshot(
                feature: id,
                status: FeatureLoadStatus.empty,
                overview: id == FeatureId.grades
                    ? const AcademicApplicationOverview(
                        terms: {'20251': '历史学期'},
                        graduateGrades: true,
                        statisticsLabel: '全部研究生成绩',
                        statistics: GradeStatistics(
                          courseCount: 0,
                          totalCredits: null,
                          gpa: 3.125,
                        ),
                      )
                    : null,
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
          onLoadAllGrades: (_) async {
            undergraduateLoads++;
            return const GradesAggregate();
          },
        ),
      ),
    );
    await openFeature(tester, FeatureId.grades);
    await tester.pumpAndSettle();
    expect(find.text('全部研究生成绩'), findsOneWidget);
    expect(find.text('3.13'), findsOneWidget);
    expect(find.text('暂无成绩'), findsOneWidget);
    expect(undergraduateLoads, 0);
    expect(tester.takeException(), isNull);
  });
}
