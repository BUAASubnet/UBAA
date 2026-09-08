import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../support/navigation.dart';

void main() {
  testWidgets('研讨室校区和楼栋采用typed选择，默认查询面板不占正文', (tester) async {
    final queries = <FeatureQuery>[];
    await _open(tester, const [
      FeatureDetail(
        title: '假标题',
        fields: [FeatureField(label: '站点 ID', value: '999')],
        presentation: CgyySitePresentation(
          id: 7,
          siteName: '一层',
          venueName: '合成研讨楼',
          campusName: '沙河校区',
        ),
      ),
    ], queries);
    expect(find.widgetWithText(FilterChip, '沙河'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, '合成研讨楼 / 一层'), findsOneWidget);
    expect(queries, hasLength(1));
    expect(queries.single.siteId, 7);
    expect(queries.single.view, FeatureQueryView.cgyyDayInfo);
    expect(find.byType(TextField), findsNothing);
  });
  testWidgets('研讨室房间时段表保留未知状态并在选中后才有下一步', (tester) async {
    final queries = <FeatureQuery>[];
    await _open(tester, _dayDetails, queries);
    expect(find.text('合成研讨室'), findsOneWidget);
    expect(find.text('无时段房间'), findsOneWidget);
    expect(find.text('资格未知'), findsOneWidget);
    expect(find.text('下一步'), findsNothing);
    await tester.tap(find.byTooltip('合成研讨室 08:00–09:00'));
    await tester.pumpAndSettle();
    expect(find.text('下一步'), findsOneWidget);
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('填写研讨室预约信息'), findsOneWidget);
    expect(queries, isEmpty);
  });
}

const _dayDetails = [
  FeatureDetail(
    title: '预约时间',
    presentation: CgyyDayPresentation(
      venueSiteId: 7,
      reservationDate: '2026-09-04',
      availableDates: ['2026-09-04'],
      timeSlots: [
        CgyyTimePresentation(
          id: 9,
          beginTime: '08:00',
          endTime: '09:00',
          label: '上午',
        ),
        CgyyTimePresentation(
          id: 3,
          beginTime: '09:00',
          endTime: '10:00',
          label: '上午',
        ),
      ],
      spaces: [
        CgyySpacePresentation(spaceId: 4, spaceName: '合成研讨室', venueSiteId: 7),
        CgyySpacePresentation(spaceId: 5, spaceName: '无时段房间', venueSiteId: 7),
      ],
    ),
  ),
  FeatureDetail(
    title: '合成研讨室 上午',
    presentation: CgyySlotPresentation(
      venueSiteId: 7,
      reservationDate: '2026-09-04',
      spaceId: 4,
      spaceName: '合成研讨室',
      timeId: 9,
      beginTime: '08:00',
      endTime: '09:00',
      reservationStatus: 1,
    ),
    actions: [
      CgyyReserveAction(
        venueSiteId: 7,
        reservationDate: '2026-09-04',
        spaceId: 4,
        timeId: 9,
        timeOrdinal: 0,
        venueSpaceGroupId: null,
        eligibility: ActionEligibility.allowed,
      ),
    ],
  ),
  FeatureDetail(
    title: '合成研讨室 上午',
    presentation: CgyySlotPresentation(
      venueSiteId: 7,
      reservationDate: '2026-09-04',
      spaceId: 4,
      spaceName: '合成研讨室',
      timeId: 3,
      beginTime: '09:00',
      endTime: '10:00',
    ),
  ),
];

Future<void> _open(
  WidgetTester tester,
  List<FeatureDetail> details,
  List<FeatureQuery> queries,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(402, 874);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      home: UbaaMainShell(
        initialTab: 2,
        user: const UserSummary(username: 'synthetic'),
        snapshots: {
          for (final id in FeatureId.values)
            id: FeatureSnapshot(
              feature: id,
              status: FeatureLoadStatus.success,
              details: id == FeatureId.cgyy ? details : const [],
            ),
        },
        routePolicy: RoutePolicy.auto,
        telemetryEnabled: false,
        onRefresh: () async {},
        onRetryFeature: (_) async {},
        onFeatureQuery: (_, query) async {
          queries.add(query);
        },
        onPrepareCgyySubmitWrite: (_) async => throw StateError('本用例禁止写准备'),
        onRunWritePrepare: (prepare, {required expectedOperation}) async =>
            prepare(),
        onCancelWrite: () async {},
        onConfirmWrite: () async => null,
        onLogout: () async {},
        onLogoutAndClearAccount: () async {},
        onRoutePolicyChanged: (_) {},
        onTelemetryChanged: (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
  await openFeature(tester, FeatureId.cgyy);
}
