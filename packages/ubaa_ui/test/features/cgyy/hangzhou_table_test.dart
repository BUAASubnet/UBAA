import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/cgyy/reservation_flow.dart';
import 'package:ubaa_ui/src/write/cgyy/draft.dart';

CgyySlotPresentation _slot(int timeId, {int? status, String? remark}) =>
    CgyySlotPresentation(
      venueSiteId: 701,
      reservationDate: '2026-11-25',
      spaceId: 1,
      spaceName: '1号（合成场）',
      timeId: timeId,
      beginTime: '0$timeId:00',
      endTime: '0${timeId + 1}:00',
      reservationStatus: status,
      adminRemark: remark,
    );

Future<void> _pump(WidgetTester tester, {required bool hangzhou}) async {
  final draft = CgyyFormDraft();
  addTearDown(draft.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CgyyReservationFlow(
          snapshot: FeatureSnapshot(
            feature: hangzhou ? FeatureId.hangzhouCgyy : FeatureId.cgyy,
            status: FeatureLoadStatus.success,
            details: [
              const FeatureDetail(
                title: '预约时间',
                presentation: CgyyDayPresentation(
                  venueSiteId: 701,
                  reservationDate: '2026-11-25',
                  availableDates: ['2026-11-25', '2026-11-26', '2026-11-27'],
                  timeSlots: [
                    CgyyTimePresentation(
                      id: 7,
                      beginTime: '07:00',
                      endTime: '08:00',
                      label: '上午',
                    ),
                    CgyyTimePresentation(
                      id: 8,
                      beginTime: '08:00',
                      endTime: '09:00',
                      label: '上午',
                    ),
                  ],
                  spaces: [
                    CgyySpacePresentation(
                      spaceId: 1,
                      spaceName: '1号（合成场）',
                      venueSiteId: 701,
                    ),
                  ],
                ),
              ),
              FeatureDetail(
                title: '7',
                presentation: _slot(7, status: 1, remark: '教学使用'),
              ),
              FeatureDetail(title: '8', presentation: _slot(8, status: 4)),
            ],
          ),
          query: FeatureQuery(
            view: FeatureQueryView.cgyyDayInfo,
            siteId: 701,
            date: DateTime(2026, 11, 25),
          ),
          cacheEpoch: 0,
          fallback: const Text('通用列表'),
          onQuery: (_) async {},
          onRetry: () async {},
          onlyAvailable: false,
          hangzhouVenue: hangzhou,
          formContext: CgyyFormContext(draft: draft),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('杭州场馆表头为场地，占用格按官网显示教学使用与已售', (tester) async {
    await _pump(tester, hangzhou: true);
    expect(find.text('场地'), findsOneWidget);
    expect(find.text('研讨室'), findsNothing);
    expect(find.text('教学使用'), findsOneWidget);
    expect(find.text('已售'), findsOneWidget);
  });

  testWidgets('杭州同一房间可选三个以上且不要求相邻的时段', (tester) async {
    await _pumpFree(tester, hangzhou: true);
    for (final time in ['10:00–11:00', '12:00–13:00', '13:00–14:00']) {
      await tester.tap(_cell(time));
      await tester.pumpAndSettle();
    }
    expect(find.text('已选'), findsNWidgets(3));
  });

  testWidgets('杭州按人数预约的场地像官网一样显示已约/总数', (tester) async {
    await _pumpFree(tester, hangzhou: true, total: 200);
    expect(find.text('75/200'), findsOneWidget);
    expect(find.text('2/200'), findsOneWidget);
    expect(find.text('0/200'), findsNWidgets(2));
    await tester.tap(_cell('10:00–11:00'));
    await tester.pumpAndSettle();
    expect(find.text('75/200'), findsNothing);
    expect(find.text('已选'), findsOneWidget);
  });

  testWidgets('北京研讨室仍只能选两个相邻时段', (tester) async {
    await _pumpFree(tester, hangzhou: false);
    for (final time in ['10:00–11:00', '11:00–12:00', '12:00–13:00']) {
      await tester.tap(_cell(time));
      await tester.pumpAndSettle();
    }
    expect(find.text('已选'), findsOneWidget);
  });

  testWidgets('北京研讨室表格保持原样', (tester) async {
    await _pump(tester, hangzhou: false);
    expect(find.text('研讨室'), findsOneWidget);
    expect(find.text('教学使用'), findsNothing);
    expect(find.text('已售'), findsNothing);
  });
}

FeatureDetail _free(int timeId, int ordinal, {int? already}) => FeatureDetail(
  title: '$timeId',
  presentation: CgyySlotPresentation(
    venueSiteId: 701,
    reservationDate: '2026-11-27',
    spaceId: 1,
    spaceName: '2006 合成室',
    timeId: timeId,
    beginTime: '$timeId:00',
    endTime: '${timeId + 1}:00',
    reservationStatus: 1,
    alreadyNum: already,
  ),
  actions: [
    CgyyReserveAction(
      venueSiteId: 701,
      reservationDate: '2026-11-27',
      spaceId: 1,
      timeId: timeId,
      venueSpaceGroupId: null,
      timeOrdinal: ordinal,
      eligibility: ActionEligibility.allowed,
    ),
  ],
);

Future<void> _pumpFree(
  WidgetTester tester, {
  required bool hangzhou,
  int? total,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final draft = CgyyFormDraft();
  addTearDown(draft.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CgyyReservationFlow(
          snapshot: FeatureSnapshot(
            feature: hangzhou ? FeatureId.hangzhouCgyy : FeatureId.cgyy,
            status: FeatureLoadStatus.success,
            details: [
              FeatureDetail(
                title: '预约时间',
                presentation: CgyyDayPresentation(
                  reservationTotalNum: total,
                  venueSiteId: 701,
                  reservationDate: '2026-11-27',
                  availableDates: ['2026-11-27'],
                  timeSlots: [
                    CgyyTimePresentation(
                      id: 10,
                      beginTime: '10:00',
                      endTime: '11:00',
                      label: '上午',
                    ),
                    CgyyTimePresentation(
                      id: 11,
                      beginTime: '11:00',
                      endTime: '12:00',
                      label: '上午',
                    ),
                    CgyyTimePresentation(
                      id: 12,
                      beginTime: '12:00',
                      endTime: '13:00',
                      label: '下午',
                    ),
                    CgyyTimePresentation(
                      id: 13,
                      beginTime: '13:00',
                      endTime: '14:00',
                      label: '下午',
                    ),
                  ],
                  spaces: [
                    CgyySpacePresentation(
                      spaceId: 1,
                      spaceName: '2006 合成室',
                      venueSiteId: 701,
                    ),
                  ],
                ),
              ),
              _free(10, 0, already: total == null ? null : 75),
              _free(11, 1, already: total == null ? null : 2),
              _free(12, 2),
              _free(13, 3),
            ],
          ),
          query: FeatureQuery(
            view: FeatureQueryView.cgyyDayInfo,
            siteId: 701,
            date: DateTime(2026, 11, 27),
          ),
          cacheEpoch: 0,
          fallback: const Text('通用列表'),
          onQuery: (_) async {},
          onRetry: () async {},
          onlyAvailable: false,
          hangzhouVenue: hangzhou,
          formContext: CgyyFormContext(draft: draft),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _cell(String time) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      (widget.properties.label?.contains(' $time ') ?? false),
);
