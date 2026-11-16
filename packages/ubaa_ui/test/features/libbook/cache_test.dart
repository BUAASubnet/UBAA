import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_ui/src/features/libbook/reservation_flow.dart';
import '../../support/navigation.dart';

void main() {
  testWidgets('分区刷新期间不使用缓存日期查询座位，刷新成功后使用新日程', (tester) async {
    final queries = <FeatureQuery>[];
    await tester.pumpWidget(_schedulePage(FeatureLoadStatus.loading, queries));
    await tester.pump();
    expect(queries, isEmpty);

    await tester.pumpWidget(_schedulePage(FeatureLoadStatus.success, queries));
    await tester.pumpAndSettle();
    expect(queries, hasLength(1));
    expect(queries.single.view, FeatureQueryView.libbookSeats);
    expect(queries.single.date, DateTime(2026, 11, 16));
    expect(queries.single.segment, 'current-slot');
  });

  testWidgets('分区刷新失败后保留缓存日程但不自动查询旧日期座位', (tester) async {
    final queries = <FeatureQuery>[];
    await tester.pumpWidget(_schedulePage(FeatureLoadStatus.stale, queries));
    await tester.pumpAndSettle();
    expect(queries, isEmpty);
  });

  testWidgets('图书馆已保存座位在恢复期间仍可阅读且不能准备预约', (tester) async {
    await tester.pumpWidget(_page(FeatureLoadStatus.stale));
    await tester.pumpAndSettle();
    await openFeature(tester, FeatureId.libbook);
    expect(find.text('合成座位甲'), findsOneWidget);
    expect(find.text('资格未确认'), findsNothing);
    expect(find.text('预约此座位'), findsNothing);
    await tester.pumpWidget(_page(FeatureLoadStatus.loading));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('合成座位甲'), findsOneWidget);
    expect(find.text('预约此座位'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _schedulePage(FeatureLoadStatus status, List<FeatureQuery> queries) {
  final online = status == FeatureLoadStatus.success;
  final query = FeatureQuery(
    view: FeatureQueryView.libbookAreaDetail,
    areaId: 'a1',
    date: DateTime(2026, 11, 16),
  );
  return MaterialApp(
    home: Scaffold(
      body: LibbookReservationFlow(
        cacheEpoch: 0,
        query: query,
        fallback: const SizedBox(),
        onQuery: (query) async => queries.add(query),
        snapshot: FeatureSnapshot(
          feature: FeatureId.libbook,
          status: status,
          error: status == FeatureLoadStatus.stale
              ? const UiError(
                  code: UbaaErrorCode.networkError,
                  title: '读取失败',
                  message: '合成网络错误',
                )
              : null,
          readContext: FeatureReadContext(requestRevision: 1, query: query),
          evidence: DataEvidence(
            accountId: 'synthetic',
            origin: online ? DataOrigin.online : DataOrigin.persisted,
            fetchedAt: DateTime(2026, 11, online ? 16 : 14),
            complete: true,
            savedForOffline: true,
          ),
          details: [
            FeatureDetail(
              title: '合成分区',
              presentation: LibbookAreaSchedulePresentation(
                id: 'a1',
                name: '合成分区',
                days: [
                  LibbookDaySchedulePresentation(
                    bookStart: '00:00',
                    bookEnd: '23:59',
                    bookClose: '23:59',
                    day: online ? '2026-11-16' : '2026-11-14',
                    timeSlots: [
                      LibbookTimeSlotPresentation(
                        id: online ? 'current-slot' : 'old-slot',
                        start: '08:00',
                        end: '23:00',
                        label: '全天',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
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
    onRefresh: () async {},
    onRetryFeature: (_) async {},
    onLogout: () async {},
    onLogoutAndClearAccount: () async {},
    onRoutePolicyChanged: (_) {},
  ),
);
