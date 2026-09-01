import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('BridgeBackend 空教室楼层和节次筛选只投影白名单结果', () async {
    final response = BridgeRoutedClassroomQuery(
      data: const BridgeClassroomQuery(
        code: 0,
        message: 'ok',
        floors: <BridgeClassroomFloor>[
          BridgeClassroomFloor(
            name: '主楼',
            rooms: <BridgeClassroomInfo>[
              BridgeClassroomInfo(
                id: 'room-1',
                floorId: 'F2',
                name: '主楼 201',
                availableSections: '1,3',
              ),
              BridgeClassroomInfo(
                id: 'room-2',
                floorId: 'F2',
                name: '主楼 202',
                availableSections: '13',
              ),
            ],
          ),
          BridgeClassroomFloor(
            name: '新主楼',
            rooms: <BridgeClassroomInfo>[
              BridgeClassroomInfo(
                id: 'room-3',
                floorId: 'F3',
                name: '新主楼 301',
                availableSections: '3',
              ),
            ],
          ),
        ],
      ),
      route: const BridgeRouteDecision(
        policy: BridgeRoutePolicy.direct,
        resolvedRoute: BridgeConnectionMode.direct,
        network: BridgeNetworkState.campus,
        initialRoute: BridgeConnectionMode.direct,
        usedFallback: false,
      ),
    );
    final backend = BridgeBackend(_FakeClassroomClient(response));

    final result = await backend.loadFeatureQuery(
      FeatureId.classroom,
      FeatureQuery(
        date: DateTime(2026, 9, 2),
        campus: 2,
        floorId: 'F2',
        section: '3',
      ),
    );

    expect(result.summary, '1间可用教室');
    expect(result.details.single.title, '主楼 201');
    expect(result.resolvedRoute, ConnectionMode.direct);
  });
}

class _FakeClassroomClient implements BridgeClient {
  _FakeClassroomClient(this.response);

  final BridgeRoutedClassroomQuery response;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #classroomSearch) {
      return Future<BridgeRoutedClassroomQuery>.value(response);
    }
    throw UnsupportedError('unexpected bridge call: ${invocation.memberName}');
  }
}
