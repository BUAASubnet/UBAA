import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../support/bridge/fixtures.dart'
    show
        FixtureContractVersionClient,
        FixtureFakeBykcChosenCoursesClient,
        FixtureFakeCancellationProjectionClient,
        FixtureFakeCgyyCommitClient,
        FixtureFakeYgdkRecordsClient,
        currentBridgeContractVersion;

void main() {
  test('BridgeBackend 接受当前合同版本', () {
    final client = FixtureContractVersionClient(currentBridgeContractVersion);

    final backend = BridgeBackend(client);

    expect(backend.client, same(client));
    expect(client.disposeCalls, 0);
  });

  test('BridgeBackend 在 release 可执行路径明确拒绝旧 v8 合同', () {
    final client = FixtureContractVersionClient(8);

    expect(
      () => BridgeBackend(client),
      throwsA(
        isA<InitializationException>().having(
          (e) => e.failure,
          '分类',
          InitializationFailure.bridgeIncompatible,
        ),
      ),
    );
    expect(client.disposeCalls, 1);
  });

  test('BridgeBackend 博雅已选课程投影签到时间和位置要求但不暴露坐标', () async {
    final response = BridgeRoutedBykcChosenCourses(
      data: const <BridgeBykcChosenCourse>[
        BridgeBykcChosenCourse(
          id: 1,
          courseId: 42,
          courseName: '课程 A',
          coursePosition: '校本部',
          checkin: null,
          signEligibility: BridgeActionEligibility.allowed,
          signOutEligibility: BridgeActionEligibility.unknown,
          deselectEligibility: BridgeActionEligibility.unknown,
          signConfig: BridgeBykcSignConfig(
            signStartDate: '2026-09-02 08:00',
            signEndDate: '2026-09-02 10:00',
            signOutStartDate: '2026-09-02 11:00',
            signOutEndDate: '2026-09-02 12:00',
            signPoints: <BridgeBykcSignPoint>[
              BridgeBykcSignPoint(lat: 39.99, lng: 116.31, radius: 100),
              BridgeBykcSignPoint(lat: 40.00, lng: 116.32, radius: 80),
            ],
          ),
          courseSignType: 1,
        ),
      ],
      route: const BridgeRouteDecision(
        policy: BridgeRoutePolicy.direct,
        resolvedRoute: BridgeConnectionMode.direct,
        network: BridgeNetworkState.campus,
        initialRoute: BridgeConnectionMode.direct,
        usedFallback: false,
      ),
    );
    final result =
        await BridgeBackend(
          FixtureFakeBykcChosenCoursesClient(response),
        ).loadFeatureQuery(
          FeatureId.bykc,
          const FeatureQuery(view: FeatureQueryView.bykcChosenCourses),
        );
    final fields = {
      for (final field in result.details.single.fields)
        field.label: field.value,
    };
    expect(fields['签到时间'], '2026-09-02 08:00–2026-09-02 10:00');
    expect(fields['签退时间'], '2026-09-02 11:00–2026-09-02 12:00');
    expect(fields['可签到'], '是');
    expect(fields['可签退'], '未知');
    expect(fields.containsKey('签到状态'), isFalse);
    expect(fields['位置要求'], '指定位置（2 处）');
    expect(fields['签到类型'], '1');
    final actions = result.details.single.actions
        .whereType<BykcSignAction>()
        .toList(growable: false);
    expect(
      actions.map(
        (action) => (
          action.courseId,
          action.kind,
          action.eligibility,
          action.requiresCoordinates,
        ),
      ),
      <(int, BykcSignKind, ActionEligibility, bool)>[
        (42, BykcSignKind.signIn, ActionEligibility.allowed, false),
        (42, BykcSignKind.signOut, ActionEligibility.unknown, false),
      ],
    );
    expect(
      result.details.single.fields.any(
        (field) =>
            field.value.contains('39.99') || field.value.contains('116.31'),
      ),
      isFalse,
    );
  });

  test('BridgeBackend 仅在全部签到点坐标有效且半径有限为正时不要求调用方坐标', () async {
    const eligibility = BridgeActionEligibility.allowed;
    const unknown = BridgeActionEligibility.unknown;
    final response = BridgeRoutedBykcChosenCourses(
      data: const <BridgeBykcChosenCourse>[
        BridgeBykcChosenCourse(
          id: 1,
          courseId: 101,
          courseName: '完整范围',
          signEligibility: eligibility,
          signOutEligibility: eligibility,
          deselectEligibility: unknown,
          signConfig: BridgeBykcSignConfig(
            signPoints: <BridgeBykcSignPoint>[
              BridgeBykcSignPoint(lat: 39.9, lng: 116.3, radius: 1),
            ],
          ),
        ),
        BridgeBykcChosenCourse(
          id: 2,
          courseId: 102,
          courseName: '空范围',
          signEligibility: eligibility,
          signOutEligibility: eligibility,
          deselectEligibility: unknown,
          signConfig: BridgeBykcSignConfig(signPoints: <BridgeBykcSignPoint>[]),
        ),
        BridgeBykcChosenCourse(
          id: 3,
          courseId: 103,
          courseName: '零半径',
          signEligibility: eligibility,
          signOutEligibility: eligibility,
          deselectEligibility: unknown,
          signConfig: BridgeBykcSignConfig(
            signPoints: <BridgeBykcSignPoint>[
              BridgeBykcSignPoint(lat: 39.9, lng: 116.3, radius: 0),
            ],
          ),
        ),
        BridgeBykcChosenCourse(
          id: 4,
          courseId: 104,
          courseName: '无限半径',
          signEligibility: eligibility,
          signOutEligibility: eligibility,
          deselectEligibility: unknown,
          signConfig: BridgeBykcSignConfig(
            signPoints: <BridgeBykcSignPoint>[
              BridgeBykcSignPoint(
                lat: 39.9,
                lng: 116.3,
                radius: double.infinity,
              ),
            ],
          ),
        ),
        BridgeBykcChosenCourse(
          id: 5,
          courseId: 105,
          courseName: '缺失配置',
          signEligibility: eligibility,
          signOutEligibility: eligibility,
          deselectEligibility: unknown,
        ),
        BridgeBykcChosenCourse(
          id: 6,
          courseId: 106,
          courseName: '混合完整与不完整范围',
          signEligibility: eligibility,
          signOutEligibility: eligibility,
          deselectEligibility: unknown,
          signConfig: BridgeBykcSignConfig(
            signPoints: <BridgeBykcSignPoint>[
              BridgeBykcSignPoint(lat: 39.9, lng: 116.3, radius: 1),
              BridgeBykcSignPoint(lat: 39.91, lng: 116.31, radius: 0),
            ],
          ),
        ),
        BridgeBykcChosenCourse(
          id: 7,
          courseId: 107,
          courseName: '非法纬度',
          signEligibility: eligibility,
          signOutEligibility: eligibility,
          deselectEligibility: unknown,
          signConfig: BridgeBykcSignConfig(
            signPoints: <BridgeBykcSignPoint>[
              BridgeBykcSignPoint(lat: double.nan, lng: 116.3, radius: 1),
            ],
          ),
        ),
        BridgeBykcChosenCourse(
          id: 8,
          courseId: 108,
          courseName: '越界经度',
          signEligibility: eligibility,
          signOutEligibility: eligibility,
          deselectEligibility: unknown,
          signConfig: BridgeBykcSignConfig(
            signPoints: <BridgeBykcSignPoint>[
              BridgeBykcSignPoint(lat: 39.9, lng: 181, radius: 1),
            ],
          ),
        ),
      ],
      route: const BridgeRouteDecision(
        policy: BridgeRoutePolicy.direct,
        resolvedRoute: BridgeConnectionMode.direct,
        network: BridgeNetworkState.campus,
        initialRoute: BridgeConnectionMode.direct,
        usedFallback: false,
      ),
    );

    final result =
        await BridgeBackend(
          FixtureFakeBykcChosenCoursesClient(response),
        ).loadFeatureQuery(
          FeatureId.bykc,
          const FeatureQuery(view: FeatureQueryView.bykcChosenCourses),
        );
    final requirements = <int, bool>{
      for (final detail in result.details)
        for (final action in detail.actions.whereType<BykcSignAction>())
          action.courseId: action.requiresCoordinates,
    };
    expect(requirements, <int, bool>{
      101: false,
      102: true,
      103: true,
      104: true,
      105: true,
      106: true,
      107: true,
      108: true,
    });
    expect(
      result.details
          .singleWhere((detail) => detail.title == '空范围')
          .fields
          .singleWhere((field) => field.label == '位置要求')
          .value,
      '需获取当前位置（未返回可用签到范围）',
    );
    expect(
      result.details
          .singleWhere((detail) => detail.title == '缺失配置')
          .fields
          .singleWhere((field) => field.label == '位置要求')
          .value,
      '位置配置未知（需获取当前位置）',
    );
  });

  test('BridgeBackend 保留场馆提交的非敏感订单收据用于结果核对', () async {
    final backend = BridgeBackend(FixtureFakeCgyyCommitClient());

    final result = await backend.commitWrite('cgyy-intent');

    expect(result.operation, WriteOperation.cgyySubmitReservation);
    expect(result.cgyyReceipt?.orderId, 42);
    expect(result.cgyyReceipt?.venueSiteId, 3);
    expect(result.cgyyReceipt?.reservationDate, '2026-09-03');
    expect(result.cgyyReceipt?.orderStatus, 1);
  });

  test('BridgeBackend 取消入口状态仅展示并由 typed 资格供 UI 门禁使用', () async {
    final route = const BridgeRouteDecision(
      policy: BridgeRoutePolicy.direct,
      resolvedRoute: BridgeConnectionMode.direct,
      network: BridgeNetworkState.campus,
      initialRoute: BridgeConnectionMode.direct,
      usedFallback: false,
    );
    final backend = BridgeBackend(
      FixtureFakeCancellationProjectionClient(
        libbook: BridgeRoutedLibBookBookings(
          data: const BridgeLibBookBookingsPage(
            bookings: <BridgeLibBookBooking>[
              BridgeLibBookBooking(
                id: 'booking-6',
                nameMerge: '预约',
                areaName: '馆区',
                seatNo: 'A-01',
                day: '2026-09-02',
                beginTime: '10:00',
                endTime: '12:00',
                status: 6,
                statusName: '有效',
                cancelEligibility: BridgeActionEligibility.denied,
                cancelTarget: 'booking-6',
              ),
            ],
            page: 1,
            limit: 20,
            total: 1,
          ),
          route: route,
        ),
        cgyy: BridgeRoutedCgyyOrders(
          data: const BridgeCgyyOrdersPage(
            content: <BridgeCgyyOrder>[
              BridgeCgyyOrder(
                id: 17,
                orderStatus: 1,
                checkStatus: 2,
                cancelEligibility: BridgeActionEligibility.allowed,
                cancelTarget: BridgeCgyyCancelOrderTarget(orderId: 17),
              ),
            ],
            totalElements: 1,
            totalPages: 1,
            size: 20,
            number: 0,
          ),
          route: route,
        ),
      ),
    );
    final libbook = await backend.loadFeatureQuery(
      FeatureId.libbook,
      const FeatureQuery(view: FeatureQueryView.libbookBookings),
    );
    final libbookFields = {
      for (final field in libbook.details.single.fields)
        field.label: field.value,
    };
    expect(libbookFields['状态码'], '6');
    expect(libbookFields['状态'], '有效');
    final libbookAction = libbook.details.single.action<LibbookCancelAction>();
    expect(libbookAction?.bookingId, 'booking-6');
    expect(libbookAction?.page, 1);
    expect(libbookAction?.limit, 20);
    expect(libbookAction?.eligibility, ActionEligibility.denied);

    final cgyy = await backend.loadFeatureQuery(
      FeatureId.cgyy,
      const FeatureQuery(view: FeatureQueryView.cgyyOrders),
    );
    final cgyyFields = {
      for (final field in cgyy.details.single.fields) field.label: field.value,
    };
    expect(cgyyFields['订单状态'], '1');
    expect(cgyyFields['审核状态'], '2');
    expect(cgyyFields['订单状态说明'], '待审批');
    expect(cgyyFields['审核状态说明'], '待辅导员审批');
    final cgyyAction = cgyy.details.single.action<CgyyCancelAction>();
    expect(cgyyAction?.orderId, 17);
    expect(cgyyAction?.orderStatus, 1);
    expect(cgyyAction?.checkStatus, 2);
    expect(cgyyAction?.targetOrderId, 17);
    expect(cgyyAction?.eligibility, ActionEligibility.allowed);
  });

  test('BridgeBackend 阳光打卡记录只投影图片数量而不传递地址', () async {
    final response = BridgeRoutedYgdkRecords(
      data: const BridgeYgdkRecordsPage(
        content: <BridgeYgdkRecord>[
          BridgeYgdkRecord(
            recordId: 7,
            itemId: 3,
            itemName: '跑步',
            startTime: '2026-09-02 08:00',
            endTime: '2026-09-02 09:00',
            place: '校园',
            imageCount: 2,
            isOpen: false,
          ),
        ],
        total: 1,
        page: 1,
        size: 20,
        hasMore: false,
      ),
      route: const BridgeRouteDecision(
        policy: BridgeRoutePolicy.direct,
        resolvedRoute: BridgeConnectionMode.direct,
        network: BridgeNetworkState.campus,
        initialRoute: BridgeConnectionMode.direct,
        usedFallback: false,
      ),
    );
    final result = await BridgeBackend(FixtureFakeYgdkRecordsClient(response))
        .loadFeatureQuery(
          FeatureId.ygdk,
          const FeatureQuery(view: FeatureQueryView.ygdkRecords),
        );
    expect(result.summary, '1条打卡记录');
    final fields = {
      for (final field in result.details.single.fields)
        field.label: field.value,
    };
    expect(fields['图片数量'], '2');
    expect(result.pagination?.page, 1);
    expect(result.pagination?.size, 20);
    expect(result.pagination?.total, 1);
    expect(result.pagination?.hasMore, isFalse);
    expect(
      result.details.single.fields.any((field) => field.value.contains('http')),
      isFalse,
    );
  });
}
