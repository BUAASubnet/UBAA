import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/libbook/reservation_flow.dart';

void main() {
  testWidgets('非预约时段整页提示并停止座位加载，开放后重新读取日程', (tester) async {
    var now = DateTime.utc(2026, 11, 17, 0, 29);
    final queries = <FeatureQuery>[];
    await tester.pumpWidget(_page(queries, () => now));
    await tester.pumpAndSettle();
    expect(find.text('不在预约时间'), findsOneWidget);
    expect(queries, isEmpty);
    expect(find.byType(GridView), findsNothing);
    now = DateTime.utc(2026, 11, 17, 0, 30);
    await tester.pump(const Duration(seconds: 1));
    expect(queries.single.view, FeatureQueryView.libbookAreaDetail);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('预约面板打开期间到达截止时间会关闭面板并显示整页提示', (tester) async {
    var now = DateTime.utc(2026, 11, 17, 14, 59);
    final queries = <FeatureQuery>[];
    await tester.pumpWidget(_page(queries, () => now));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _page(queries, () => now, seats: true, onReserve: (_) async {}),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('001'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    now = DateTime.utc(2026, 11, 17, 15, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('不在预约时间'), findsOneWidget);
    expect(find.byType(GridView), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('长座位列表点击首个座位立即弹出可见预约面板', (tester) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    final queries = <FeatureQuery>[];
    DateTime now() => DateTime.utc(2026, 11, 17, 2);
    await tester.pumpWidget(_page(queries, now));
    await tester.pumpAndSettle();
    expect(queries.single.view, FeatureQueryView.libbookSeats);
    await tester.pumpWidget(
      _page(
        queries,
        now,
        seats: true,
        onReserve: (_) async {
          calls++;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('001'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('预约此座位').hitTestable(), findsOneWidget);
    await tester.tap(find.text('预约此座位'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

Widget _page(
  List<FeatureQuery> queries,
  DateTime Function() now, {
  bool seats = false,
  Future<void> Function(LibbookReserveAction)? onReserve,
}) {
  final query = FeatureQuery(
    view: seats
        ? FeatureQueryView.libbookSeats
        : FeatureQueryView.libbookAreaDetail,
    areaId: 'a1',
    date: DateTime(2026, 11, 17),
    segment: seats ? 'slot' : '',
    startTime: seats ? '07:00' : '',
    endTime: seats ? '23:00' : '',
  );
  return MaterialApp(
    home: Scaffold(
      body: LibbookReservationFlow(
        cacheEpoch: 0,
        query: query,
        now: now,
        fallback: const SizedBox(),
        onQuery: (q) async {
          queries.add(q);
        },
        onReserve: onReserve,
        snapshot: FeatureSnapshot(
          feature: FeatureId.libbook,
          status: FeatureLoadStatus.success,
          readContext: FeatureReadContext(
            requestRevision: seats ? 2 : 1,
            query: query,
          ),
          details: seats
              ? [
                  for (var i = 1; i <= 175; i++)
                    FeatureDetail(
                      title: '座位 $i',
                      presentation: LibbookSeatPresentation(
                        id: 's$i',
                        name: '座位 $i',
                        number: i.toString().padLeft(3, '0'),
                        status: 1,
                        statusName: '空闲',
                        areaId: 'a1',
                        queryDate: '2026-11-17',
                        segment: 'slot',
                        startTime: '07:00',
                        endTime: '23:00',
                      ),
                      actions: [
                        LibbookReserveAction(
                          areaId: 'a1',
                          seatId: 's$i',
                          day: '2026-11-17',
                          segment: 'slot',
                          startTime: '07:00',
                          endTime: '23:00',
                          eligibility: ActionEligibility.allowed,
                        ),
                      ],
                    ),
                ]
              : const [
                  FeatureDetail(
                    title: '分区',
                    presentation: LibbookAreaSchedulePresentation(
                      id: 'a1',
                      name: '分区',
                      days: [
                        LibbookDaySchedulePresentation(
                          day: '2026-11-17',
                          bookStart: '08:30',
                          bookEnd: '23:00',
                          bookClose: '23:59',
                          timeSlots: [
                            LibbookTimeSlotPresentation(
                              id: 'slot',
                              start: '07:00',
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
