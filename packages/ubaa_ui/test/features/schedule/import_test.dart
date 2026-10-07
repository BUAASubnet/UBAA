import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../../support/navigation.dart';

void main() {
  for (final width in [390.0, 834.0, 1280.0]) {
    testWidgets('$width宽度课表保存进度、取消和失败重试不改变查询', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var state = const ScheduleImportState(
        status: ScheduleImportStatus.cancelled,
      );
      late StateSetter update;
      final starts = <String>[],
          cancellations = <String>[],
          queries = <FeatureQuery>[];
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.3)),
                child: UbaaMainShell(
                  user: const UserSummary(username: 'fixture'),
                  initialTab: 1,
                  snapshots: {
                    for (final feature in FeatureId.values)
                      feature: FeatureSnapshot(
                        feature: feature,
                        status: FeatureLoadStatus.empty,
                        resolvedRoute: ConnectionMode.direct,
                        readContext: feature == FeatureId.schedule
                            ? FeatureReadContext(
                                query: FeatureQuery(
                                  view: FeatureQueryView.scheduleWeek,
                                  term: 'selected',
                                  week: 3,
                                ),
                                requestRevision: 1,
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
                  onFeatureQuery: (feature, query) async {
                    queries.add(query);
                  },
                  onLoadAcademicWeeks: (_, _) async =>
                      const FeatureResult.empty(),
                  scheduleImports: {'selected': state},
                  onSaveScheduleSemester: (term) async {
                    starts.add(term);
                  },
                  onCancelScheduleImport: cancellations.add,
                ),
              );
            },
          ),
        ),
      );
      await openFeature(tester, FeatureId.schedule);
      await tester.tap(find.text('保存整学期'));
      await tester.pump();
      expect(starts, ['selected']);
      update(
        () => state = const ScheduleImportState(
          status: ScheduleImportStatus.running,
          progress: ScheduleImportProgress(
            term: 'selected',
            completedWeeks: 1,
            totalWeeks: 2,
            finished: false,
            route: ConnectionMode.direct,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('正在保存：1 / 2 周'), findsOneWidget);
      await tester.tap(find.text('取消保存'));
      expect(cancellations, ['selected']);
      update(
        () => state = const ScheduleImportState(
          status: ScheduleImportStatus.failed,
          progress: ScheduleImportProgress(
            term: 'selected',
            completedWeeks: 2,
            totalWeeks: 2,
            finished: true,
            route: ConnectionMode.direct,
            saveFailure: CacheMaintenanceFailure.capacity,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('空间不足'), findsOneWidget);
      expect(find.text('整学期已保存，可离线查看'), findsNothing);
      await tester.tap(find.text('重新保存'));
      expect(starts.length, 2);
      update(
        () => state = const ScheduleImportState(
          status: ScheduleImportStatus.saved,
          progress: ScheduleImportProgress(
            term: 'selected',
            completedWeeks: 2,
            totalWeeks: 2,
            finished: true,
            route: ConnectionMode.direct,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('整学期已保存，可离线查看'), findsOneWidget);
      expect(find.text('第 3 周'), findsOneWidget);
      expect(queries, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
