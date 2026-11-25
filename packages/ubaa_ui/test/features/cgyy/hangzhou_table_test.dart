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

  testWidgets('北京研讨室表格保持原样', (tester) async {
    await _pump(tester, hangzhou: false);
    expect(find.text('研讨室'), findsOneWidget);
    expect(find.text('教学使用'), findsNothing);
    expect(find.text('已售'), findsNothing);
  });
}
