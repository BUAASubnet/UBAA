import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../support/bridge/recording_client.dart'
    show FixtureCharacterizationBridgeClient, fixtureWebVpnRoute;

void registerLibbookPresentationTests() {
  final day = DateTime(2026, 9, 4);
  test('图书馆日程投影保留日期与各自时段的嵌套关联', () async {
    final client = _LibraryScheduleClient();
    final result = await BridgeBackend(client).loadFeatureQuery(
      FeatureId.libbook,
      FeatureQuery(
        view: FeatureQueryView.libbookAreaDetail,
        areaId: 'area-1',
        date: day,
      ),
    );
    expect(
      result.details.single.presentation,
      isA<LibbookAreaSchedulePresentation>(),
    );
    final schedule =
        result.details.single.presentation! as LibbookAreaSchedulePresentation;
    expect(schedule.id, 'area-1');
    expect(schedule.days.map((day) => day.day), ['2026-09-04', '2026-09-05']);
    expect(schedule.days.first.timeSlots.single.id, 'first-slot');
    final slot = schedule.days.last.timeSlots.single;
    expect(
      [slot.id, slot.start, slot.end, slot.label],
      ['second-slot', '14:00', '16:00', '同名时段'],
    );
    expect(client.calls, ['libbookAreaSchedule:areaId=area-1']);
    expect(result.details.single.actions, isEmpty);
    expect(result.resolvedRoute, ConnectionMode.webvpn);
  });
  test('图书馆投影保留同名楼层的独立ID和当前读取日期', () async {
    final client = _LibraryPresentationClient();
    final result = await BridgeBackend(
      client,
    ).loadFeatureQuery(FeatureId.libbook, FeatureQuery(date: day));
    expect(result.details.single.presentation, isNotNull);
    final p = result.details.single.presentation! as LibbookLibraryPresentation;
    expect(p.id, 'library-read-1');
    expect(p.queryDate, '2026-09-04');
    expect(p.storeys.map((floor) => floor.id), ['floor-a', 'floor-b']);
    expect(p.storeys.map((floor) => floor.name), ['同名楼层', '同名楼层']);
    expect(p.storeys.first.freeNum, 0);
    expect(p.storeys.last.totalNum, 20);
    expect(client.calls, ['libraries:2026-09-04']);
    expect(result.resolvedRoute, ConnectionMode.webvpn);
  });
  test('图书馆分区投影保留响应归属且不从查询替换响应父ID', () async {
    final client = FixtureCharacterizationBridgeClient();
    final result = await BridgeBackend(client).loadFeatureQuery(
      FeatureId.libbook,
      FeatureQuery(
        view: FeatureQueryView.libbookAreas,
        premisesId: 'request-parent',
        storeyId: 'request-floor',
        date: day,
      ),
    );
    expect(result.details.single.presentation, isNotNull);
    final p = result.details.single.presentation! as LibbookAreaPresentation;
    expect(p.id, 'area-read-1');
    expect(p.premisesId, 'premises-1');
    expect(p.storeyId, 'storey-1');
    expect(p.queryDate, '2026-09-04');
    expect(client.calls, [
      'libbookAreas:premisesId=request-parent,storeyId=request-floor,day=2026-09-04',
    ]);
  });
  test('图书馆分区详情保留原始时段ID与起止，不从上午标签推断', () async {
    final result = await BridgeBackend(FixtureCharacterizationBridgeClient())
        .loadFeatureQuery(
          FeatureId.libbook,
          FeatureQuery(
            view: FeatureQueryView.libbookAreaDetail,
            areaId: 'area-1',
            date: day,
          ),
        );
    expect(result.details.single.presentation, isNotNull);
    final p =
        result.details.single.presentation! as LibbookAreaSchedulePresentation;
    expect(p.days.single.day, '2026-09-04');
    expect(p.days.single.timeSlots.single.id, 'slot-read-1');
    expect(p.days.single.timeSlots.single.start, '08:00');
    expect(p.days.single.timeSlots.single.end, '10:00');
    expect(p.days.single.timeSlots.single.label, '上午');
    expect(result.details.single.actions, isEmpty);
    expect(result.details.single.readNavigation, isNull);
  });
  test('图书馆座位投影保留原查询上下文且写动作仍独立', () async {
    final result = await BridgeBackend(FixtureCharacterizationBridgeClient())
        .loadFeatureQuery(
          FeatureId.libbook,
          FeatureQuery(
            view: FeatureQueryView.libbookSeats,
            areaId: 'area-1',
            date: day,
            segment: 'segment-original',
            startTime: '08:00',
            endTime: '10:00',
          ),
        );
    expect(result.details.single.presentation, isNotNull);
    final p = result.details.single.presentation! as LibbookSeatPresentation;
    expect(p.id, 'seat-read-1');
    expect(p.number, 'A-01');
    expect(p.queryDate, '2026-09-04');
    expect(p.segment, 'segment-original');
    expect(
      result.details.single.action<LibbookReserveAction>()?.seatId,
      'seat-read-1',
    );
  });
  test('图书馆记录状态文案不改变typed取消资格或服务端分页', () async {
    final result = await BridgeBackend(FixtureCharacterizationBridgeClient())
        .loadFeatureQuery(
          FeatureId.libbook,
          const FeatureQuery(
            view: FeatureQueryView.libbookBookings,
            page: 2,
            size: 3,
          ),
        );
    expect(result.details.single.presentation, isNotNull);
    final p = result.details.single.presentation! as LibbookBookingPresentation;
    expect(p.status, 1);
    expect(p.statusName, '展示文案声称已结束');
    expect(p.seatNumber, 'A-01');
    expect(
      result.details.single.action<LibbookCancelAction>()?.eligibility,
      ActionEligibility.allowed,
    );
    expect(result.pagination?.page, 2);
    expect(result.pagination?.size, 3);
    expect(result.pagination?.total, 9);
  });
}

class _LibraryPresentationClient extends FixtureCharacterizationBridgeClient {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #libbookLibraries) {
      calls.add('libraries:${invocation.namedArguments[#day]}');
      return Future.value(
        const BridgeRoutedLibBookLibraries(
          route: fixtureWebVpnRoute,
          data: [
            BridgeLibBookLibrary(
              id: 'library-read-1',
              name: '合成楼馆',
              freeNum: 3,
              totalNum: 40,
              storeys: [
                BridgeLibBookStorey(
                  id: 'floor-a',
                  name: '同名楼层',
                  freeNum: 0,
                  totalNum: 20,
                ),
                BridgeLibBookStorey(
                  id: 'floor-b',
                  name: '同名楼层',
                  freeNum: 3,
                  totalNum: 20,
                ),
              ],
            ),
          ],
        ),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

class _LibraryScheduleClient extends FixtureCharacterizationBridgeClient {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #libbookAreaSchedule) {
      calls.add(
        'libbookAreaSchedule:areaId=${invocation.namedArguments[#areaId]}',
      );
      return Future.value(
        const BridgeRoutedLibBookAreaSchedule(
          route: fixtureWebVpnRoute,
          data: BridgeLibBookAreaSchedule(
            id: 'area-1',
            name: '合成分区',
            days: [
              BridgeLibBookDaySchedule(
                day: '2026-09-04',
                timeSlots: [
                  BridgeLibBookTimeSlot(
                    id: 'first-slot',
                    start: '08:00',
                    end: '10:00',
                    label: '同名时段',
                  ),
                ],
              ),
              BridgeLibBookDaySchedule(
                day: '2026-09-05',
                timeSlots: [
                  BridgeLibBookTimeSlot(
                    id: 'second-slot',
                    start: '14:00',
                    end: '16:00',
                    label: '同名时段',
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  registerLibbookPresentationTests();
}
