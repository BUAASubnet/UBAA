import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../../support/navigation.dart';

void main() {
  testWidgets('图书馆已保存座位在恢复期间仍可阅读且不能准备预约', (tester) async {
    await tester.pumpWidget(_page(FeatureLoadStatus.stale));
    await tester.pumpAndSettle();
    await openFeature(tester, FeatureId.libbook);
    expect(find.text('合成座位甲'), findsOneWidget);
    expect(find.text('资格未确认'), findsOneWidget);
    expect(find.text('准备预约此座位'), findsNothing);
    await tester.pumpWidget(_page(FeatureLoadStatus.loading));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('合成座位甲'), findsOneWidget);
    expect(find.text('准备预约此座位'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _page(FeatureLoadStatus status) => MaterialApp(
  home: UbaaMainShell(
    initialDestination: UiDestination.campus,
    user: const UserSummary(username: 'synthetic'),
    snapshots: {
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: feature == FeatureId.libbook
              ? status
              : FeatureLoadStatus.success,
          readContext: feature == FeatureId.libbook
              ? FeatureReadContext(
                  requestRevision: 1,
                  query: FeatureQuery(
                    view: FeatureQueryView.libbookSeats,
                    areaId: 'a1',
                    date: DateTime(2026, 9, 22),
                    segment: 'segment',
                    startTime: '08:00',
                    endTime: '09:00',
                  ),
                )
              : null,
          evidence: feature == FeatureId.libbook
              ? DataEvidence(
                  accountId: 'synthetic',
                  origin: DataOrigin.persisted,
                  fetchedAt: DateTime(2026, 9, 22),
                  complete: true,
                  savedForOffline: true,
                  scopeDate: '2026-09-22',
                )
              : null,
          details: feature == FeatureId.libbook
              ? [
                  FeatureDetail(
                    title: '合成座位甲',
                    presentation: LibbookSeatPresentation(
                      id: 's1',
                      name: '合成座位甲',
                      number: '',
                      status: 1,
                      statusName: '空闲',
                      areaId: 'a1',
                      queryDate: '2026-09-22',
                      segment: 'segment',
                      startTime: '08:00',
                      endTime: '09:00',
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
