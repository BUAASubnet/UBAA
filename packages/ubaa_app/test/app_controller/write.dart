part of '../app_controller_test.dart';

void _registerWriteTests() {
  test('博雅写意图通过 typed backend 准备且控制器不替换请求参数', () async {
    final backend = _BykcWriteBackend();
    final controller = AppController(backend: backend);

    final intent = await controller.prepareBykcWrite(
      WriteOperation.bykcSelectCourse,
      42,
    );
    expect(intent.operation, WriteOperation.bykcSelectCourse);
    expect(backend.selectedCourseId, 42);
    expect(backend.commitCalls, 0);

    final committed = await controller.commitWrite(intent.intentId);
    expect(committed.success, isTrue);
    expect(backend.commitCalls, 1);
    controller.dispose();
  });

  test('丢弃待确认意图只调用可选 backend 且校验意图编号', () async {
    final backend = _BykcWriteBackend();
    final controller = AppController(backend: backend);
    final intent = await controller.prepareBykcWrite(
      WriteOperation.bykcSelectCourse,
      42,
    );

    await controller.discardWriteIntent(' ${intent.intentId} ');
    expect(backend.discardedIntentId, intent.intentId);
    await expectLater(
      controller.discardWriteIntent('  '),
      throwsA(isA<BackendException>()),
    );
    controller.dispose();
  });

  test('统一写提交能力在确认阶段已可丢弃意图', () async {
    final backend = _CommitCapabilityBackend();
    final controller = AppController(backend: backend);

    await controller.discardWriteIntent(' intent-42 ');

    expect(backend.discardedIntentId, 'intent-42');
    controller.dispose();
  });

  test('博雅写意图拒绝非正课程 ID 和未接入的操作', () async {
    final controller = AppController(backend: _BykcWriteBackend());
    await expectLater(
      controller.prepareBykcWrite(WriteOperation.bykcSelectCourse, 0),
      throwsA(
        isA<BackendException>().having(
          (error) => error.code,
          'code',
          UbaaErrorCode.invalidInput,
        ),
      ),
    );
    await expectLater(
      controller.prepareBykcWrite(WriteOperation.signinPerform, 42),
      throwsA(
        isA<BackendException>().having(
          (error) => error.code,
          'code',
          UbaaErrorCode.invalidInput,
        ),
      ),
    );
    controller.dispose();
  });

  test('课堂签到写意图只接受 typed Allowed action 并在末端提取目标', () async {
    final backend = _SigninWriteBackend();
    final controller = AppController(backend: backend);
    const allowed = SigninPerformAction(
      scheduleId: ' course-7 ',
      eligibility: ActionEligibility.allowed,
    );

    final intent = await controller.prepareSigninWrite(allowed);
    expect(intent.operation, WriteOperation.signinPerform);
    expect(backend.courseId, 'course-7');
    expect(backend.commitCalls, 0);
    await controller.commitWrite(intent.intentId);
    expect(backend.commitCalls, 1);

    for (final action in const <SigninPerformAction>[
      SigninPerformAction(
        scheduleId: 'course-denied',
        eligibility: ActionEligibility.denied,
      ),
      SigninPerformAction(
        scheduleId: 'course-unknown',
        eligibility: ActionEligibility.unknown,
      ),
      SigninPerformAction(
        scheduleId: '  ',
        eligibility: ActionEligibility.allowed,
      ),
    ]) {
      await expectLater(
        controller.prepareSigninWrite(action),
        throwsA(
          isA<BackendException>().having(
            (error) => error.code,
            'code',
            UbaaErrorCode.invalidInput,
          ),
        ),
      );
    }
    expect(backend.courseId, 'course-7');
    controller.dispose();
  });

  test('图书馆取消只接受完整 typed Allowed action 并保留同页上下文', () async {
    final backend = _CancellationWriteBackend();
    final controller = AppController(backend: backend);

    final libraryIntent = await controller.prepareLibbookCancelWrite(
      const LibbookCancelAction(
        bookingId: ' booking-3 ',
        page: 2,
        limit: 10,
        eligibility: ActionEligibility.allowed,
      ),
    );
    expect(libraryIntent.operation, WriteOperation.libbookCancelBooking);
    expect(backend.bookingId, 'booking-3');
    expect(backend.bookingPage, 2);
    expect(backend.bookingLimit, 10);

    for (final action in const <LibbookCancelAction>[
      LibbookCancelAction(
        bookingId: 'booking-3',
        page: 2,
        limit: 10,
        eligibility: ActionEligibility.denied,
      ),
      LibbookCancelAction(
        bookingId: 'booking-3',
        page: 2,
        limit: 10,
        eligibility: ActionEligibility.unknown,
      ),
      LibbookCancelAction(
        bookingId: '   ',
        page: 2,
        limit: 10,
        eligibility: ActionEligibility.allowed,
      ),
      LibbookCancelAction(
        bookingId: 'booking-3',
        page: 0,
        limit: 10,
        eligibility: ActionEligibility.allowed,
      ),
      LibbookCancelAction(
        bookingId: 'booking-3',
        page: 2,
        limit: 0,
        eligibility: ActionEligibility.allowed,
      ),
    ]) {
      await expectLater(
        controller.prepareLibbookCancelWrite(action),
        throwsA(
          isA<BackendException>().having(
            (error) => error.code,
            'code',
            UbaaErrorCode.invalidInput,
          ),
        ),
      );
    }
    expect(backend.libbookPrepareCalls, 1);

    controller.dispose();
  });

  test('场馆取消只接受 Core typed Allowed action 的 canonical 目标', () async {
    final backend = _CancellationWriteBackend();
    final controller = AppController(backend: backend);

    final venueIntent = await controller.prepareCgyyCancelWrite(
      const CgyyCancelAction(
        orderId: 17,
        orderStatus: 1,
        checkStatus: 2,
        targetOrderId: 17,
        eligibility: ActionEligibility.allowed,
      ),
    );
    expect(venueIntent.operation, WriteOperation.cgyyCancelOrder);
    expect(backend.orderId, 17);

    for (final action in const <CgyyCancelAction>[
      CgyyCancelAction(
        orderId: 17,
        orderStatus: 1,
        checkStatus: 2,
        targetOrderId: null,
        eligibility: ActionEligibility.allowed,
      ),
      CgyyCancelAction(
        orderId: 17,
        orderStatus: 1,
        checkStatus: 2,
        targetOrderId: 18,
        eligibility: ActionEligibility.allowed,
      ),
      CgyyCancelAction(
        orderId: 17,
        orderStatus: 2,
        checkStatus: 2,
        targetOrderId: null,
        eligibility: ActionEligibility.denied,
      ),
      CgyyCancelAction(
        orderId: 17,
        orderStatus: null,
        checkStatus: null,
        targetOrderId: null,
        eligibility: ActionEligibility.unknown,
      ),
      CgyyCancelAction(
        orderId: 0,
        orderStatus: 1,
        checkStatus: 2,
        targetOrderId: 0,
        eligibility: ActionEligibility.allowed,
      ),
    ]) {
      await expectLater(
        controller.prepareCgyyCancelWrite(action),
        throwsA(
          isA<BackendException>().having(
            (error) => error.code,
            'code',
            UbaaErrorCode.invalidInput,
          ),
        ),
      );
    }
    expect(backend.cgyyPrepareCalls, 1);
    controller.dispose();
  });

  test('博雅签到写意图只接受冻结类型并完整转发有效坐标', () async {
    final backend = _BykcWriteBackend();
    final controller = AppController(backend: backend);

    final intent = await controller.prepareBykcSignWrite(
      42,
      1,
      lat: 39.9,
      lng: 116.3,
    );
    expect(intent.operation, WriteOperation.bykcSignCourse);
    expect(backend.signCourseId, 42);
    expect(backend.signType, 1);
    expect(backend.signLat, 39.9);
    expect(backend.signLng, 116.3);

    await expectLater(
      controller.prepareBykcSignWrite(42, 3),
      throwsA(isA<BackendException>()),
    );
    await expectLater(
      controller.prepareBykcSignWrite(42, 1, lat: 39.9),
      throwsA(isA<BackendException>()),
    );
    await expectLater(
      controller.prepareBykcSignWrite(42, 1, lat: double.nan, lng: 116.3),
      throwsA(isA<BackendException>()),
    );
    controller.dispose();
  });

  test('图书馆预约写意图只接受完整的 typed Allowed action', () async {
    final backend = _LibbookWriteBackend();
    final controller = AppController(backend: backend);
    final intent = await controller.prepareLibbookReserveWrite(
      const LibbookReserveAction(
        areaId: ' area-1 ',
        seatId: ' seat-2 ',
        day: ' 2026-09-02 ',
        segment: ' 3 ',
        startTime: ' 10:00 ',
        endTime: ' 12:00 ',
        eligibility: ActionEligibility.allowed,
      ),
    );
    expect(intent.operation, WriteOperation.libbookReserve);
    expect(backend.prepareCalls, 1);
    expect(backend.areaId, 'area-1');
    expect(backend.seatId, 'seat-2');
    expect(backend.day, '2026-09-02');
    expect(backend.segment, '3');
    expect(backend.startTime, '10:00');
    expect(backend.endTime, '12:00');

    for (final action in const <LibbookReserveAction>[
      LibbookReserveAction(
        areaId: 'area-1',
        seatId: 'seat-denied',
        day: '2026-09-02',
        segment: '3',
        startTime: '10:00',
        endTime: '12:00',
        eligibility: ActionEligibility.denied,
      ),
      LibbookReserveAction(
        areaId: 'area-1',
        seatId: 'seat-unknown',
        day: '2026-09-02',
        segment: '3',
        startTime: '10:00',
        endTime: '12:00',
        eligibility: ActionEligibility.unknown,
      ),
      LibbookReserveAction(
        areaId: 'area-1',
        seatId: '   ',
        day: '2026-09-02',
        segment: '3',
        startTime: '10:00',
        endTime: '12:00',
        eligibility: ActionEligibility.allowed,
      ),
    ]) {
      await expectLater(
        controller.prepareLibbookReserveWrite(action),
        throwsA(
          isA<BackendException>().having(
            (error) => error.code,
            'code',
            UbaaErrorCode.invalidInput,
          ),
        ),
      );
    }
    expect(backend.prepareCalls, 1);
    controller.dispose();
  });

  test('场馆预约写意图只接受同目标相邻的 typed Allowed actions', () async {
    final backend = _CgyyWriteBackend();
    final controller = AppController(backend: backend);
    final intent = await controller.prepareCgyySubmitWrite(
      _cgyySubmitInput(
        actions: const <CgyyReserveAction>[_cgyySecondAction, _cgyyFirstAction],
      ),
    );
    expect(intent.operation, WriteOperation.cgyySubmitReservation);
    expect(backend.input?.joiners, '张三');
    expect(backend.input?.actions.first.venueSiteId, 3);
    expect(backend.input?.actions.first.reservationDate, '2026-09-03');
    expect(backend.input?.actions.map((action) => action.timeId), <int>[
      900,
      100,
    ]);
    expect(backend.input?.actions.map((action) => action.timeOrdinal), <int>[
      0,
      1,
    ]);
    expect(backend.commitCalls, 0);

    final invalidActionGroups = <List<CgyyReserveAction>>[
      const <CgyyReserveAction>[
        CgyyReserveAction(
          venueSiteId: 3,
          reservationDate: '2026-09-03',
          spaceId: 4,
          timeId: 901,
          venueSpaceGroupId: 9,
          timeOrdinal: 0,
          eligibility: ActionEligibility.denied,
        ),
      ],
      const <CgyyReserveAction>[
        CgyyReserveAction(
          venueSiteId: 3,
          reservationDate: '2026-09-03',
          spaceId: 4,
          timeId: 902,
          venueSpaceGroupId: 9,
          timeOrdinal: 0,
          eligibility: ActionEligibility.unknown,
        ),
      ],
      const <CgyyReserveAction>[_cgyyFirstAction, _cgyyFirstAction],
      const <CgyyReserveAction>[
        _cgyyFirstAction,
        CgyyReserveAction(
          venueSiteId: 3,
          reservationDate: '2026-09-03',
          spaceId: 4,
          timeId: 900,
          venueSpaceGroupId: 9,
          timeOrdinal: 1,
          eligibility: ActionEligibility.allowed,
        ),
      ],
      const <CgyyReserveAction>[
        _cgyyFirstAction,
        CgyyReserveAction(
          venueSiteId: 3,
          reservationDate: '2026-09-03',
          spaceId: 4,
          timeId: 101,
          venueSpaceGroupId: 9,
          timeOrdinal: 0,
          eligibility: ActionEligibility.allowed,
        ),
      ],
      const <CgyyReserveAction>[
        _cgyyFirstAction,
        _cgyySecondAction,
        _cgyyThirdAction,
      ],
      const <CgyyReserveAction>[_cgyyFirstAction, _cgyyThirdAction],
      const <CgyyReserveAction>[
        _cgyyFirstAction,
        CgyyReserveAction(
          venueSiteId: 8,
          reservationDate: '2026-09-03',
          spaceId: 4,
          timeId: 100,
          venueSpaceGroupId: 9,
          timeOrdinal: 1,
          eligibility: ActionEligibility.allowed,
        ),
      ],
      const <CgyyReserveAction>[
        _cgyyFirstAction,
        CgyyReserveAction(
          venueSiteId: 3,
          reservationDate: '2026-09-04',
          spaceId: 4,
          timeId: 100,
          venueSpaceGroupId: 9,
          timeOrdinal: 1,
          eligibility: ActionEligibility.allowed,
        ),
      ],
      const <CgyyReserveAction>[
        _cgyyFirstAction,
        CgyyReserveAction(
          venueSiteId: 3,
          reservationDate: '2026-09-03',
          spaceId: 5,
          timeId: 100,
          venueSpaceGroupId: 9,
          timeOrdinal: 1,
          eligibility: ActionEligibility.allowed,
        ),
      ],
      const <CgyyReserveAction>[
        _cgyyFirstAction,
        CgyyReserveAction(
          venueSiteId: 3,
          reservationDate: '2026-09-03',
          spaceId: 4,
          timeId: 100,
          venueSpaceGroupId: 10,
          timeOrdinal: 1,
          eligibility: ActionEligibility.allowed,
        ),
      ],
    ];
    for (final actions in invalidActionGroups) {
      await expectLater(
        controller.prepareCgyySubmitWrite(_cgyySubmitInput(actions: actions)),
        throwsA(
          isA<BackendException>().having(
            (error) => error.code,
            'code',
            UbaaErrorCode.invalidInput,
          ),
        ),
      );
    }
    expect(backend.input?.actions, hasLength(2));
    controller.dispose();
  });

  test('场馆预约写意图拒绝空 action 与 trim 后为空的参与人说明', () async {
    final backend = _CgyyWriteBackend();
    final controller = AppController(backend: backend);

    for (final input in <CgyySubmitInput>[
      _cgyySubmitInput(actions: const <CgyyReserveAction>[]),
      _cgyySubmitInput(joiners: '  \n  '),
    ]) {
      await expectLater(
        controller.prepareCgyySubmitWrite(input),
        throwsA(
          isA<BackendException>().having(
            (error) => error.code,
            'code',
            UbaaErrorCode.invalidInput,
          ),
        ),
      );
    }
    expect(backend.input, isNull);
    controller.dispose();
  });

  test('教学评教写意图只接受待评课程且至少一门', () async {
    final backend = _EvaluationWriteBackend();
    final controller = AppController(backend: backend);
    final intent = await controller
        .prepareEvaluationWrite(const <EvaluationCourseInput>[
          EvaluationCourseInput(
            id: 'course-1',
            kcmc: '课程',
            bpmc: '教师',
            rwid: 'task-1',
            wjid: 'questionnaire-1',
            kcdm: 'K1',
            msid: 'M1',
          ),
        ]);
    expect(intent.operation, WriteOperation.evaluationSubmitCourses);
    expect(backend.courses.single.id, 'course-1');
    expect(backend.commitCalls, 0);
    await expectLater(
      controller.prepareEvaluationWrite(const <EvaluationCourseInput>[]),
      throwsA(isA<BackendException>()),
    );
    await expectLater(
      controller.prepareEvaluationWrite(const <EvaluationCourseInput>[
        EvaluationCourseInput(
          id: 'done',
          kcmc: '课程',
          bpmc: '教师',
          isEvaluated: true,
          rwid: 'task-1',
          wjid: 'questionnaire-1',
          kcdm: 'K1',
          msid: 'M1',
        ),
      ]),
      throwsA(isA<BackendException>()),
    );
    controller.dispose();
  });

  test('写入成功核对只刷新对应读取领域', () async {
    final backend = _BykcWriteBackend();
    final controller = AppController(backend: backend);
    await controller.refreshAfterWrite(WriteOperation.libbookCancelBooking);
    expect(backend.loadedFeatures, <FeatureId>[FeatureId.libbook]);
    controller.dispose();
  });

  test('十项写操作成功后都只进入对应读取核对入口', () async {
    final backend = _RefreshMatrixBackend();
    final controller = AppController(backend: backend);

    for (final operation in WriteOperation.values) {
      backend.loadedFeatures.clear();
      backend.queries.clear();
      await controller.refreshAfterWrite(operation);
      if (operation == WriteOperation.cgyySubmitReservation) {
        expect(backend.loadedFeatures, isEmpty);
        expect(backend.queries, hasLength(1));
        expect(backend.queries.single.$1, FeatureId.cgyy);
        expect(backend.queries.single.$2.view, FeatureQueryView.cgyyOrders);
      } else if (operation == WriteOperation.cgyyCancelOrder ||
          operation == WriteOperation.ygdkSubmit) {
        expect(backend.loadedFeatures, isEmpty);
        expect(backend.queries, isEmpty);
      } else if (operation == WriteOperation.libbookReserve ||
          operation == WriteOperation.libbookCancelBooking) {
        expect(backend.loadedFeatures, isEmpty);
        expect(backend.queries, hasLength(1));
        expect(backend.queries.single.$1, FeatureId.libbook);
        expect(
          backend.queries.single.$2.view,
          FeatureQueryView.libbookBookings,
        );
      } else {
        expect(backend.queries, isEmpty);
        expect(backend.loadedFeatures, hasLength(1));
        expect(backend.loadedFeatures.single, _expectedFeature(operation));
      }
    }
    controller.dispose();
  });

  test('场馆写入成功优先刷新订单列表用于核对', () async {
    final backend = _CgyyQueryWriteBackend();
    final controller = AppController(backend: backend);

    await controller.refreshAfterWrite(WriteOperation.cgyySubmitReservation);

    expect(backend.queries, hasLength(1));
    expect(backend.queries.single.$1, FeatureId.cgyy);
    expect(backend.queries.single.$2.view, FeatureQueryView.cgyyOrders);
    controller.dispose();
  });

  test('图书馆预约与取消都只刷新一次预约记录', () async {
    final backend = _RefreshMatrixBackend();
    final controller = AppController(backend: backend);

    for (final operation in const <WriteOperation>[
      WriteOperation.libbookReserve,
      WriteOperation.libbookCancelBooking,
    ]) {
      backend.queries.clear();
      backend.loadedFeatures.clear();

      await controller.refreshAfterWrite(operation);

      expect(backend.loadedFeatures, isEmpty);
      expect(backend.queries, hasLength(1));
      expect(backend.queries.single.$1, FeatureId.libbook);
      expect(backend.queries.single.$2.view, FeatureQueryView.libbookBookings);
    }
    controller.dispose();
  });

  test('图书馆取消按 action 保存的同页上下文执行只读核对', () async {
    final backend = _RefreshMatrixBackend();
    final controller = AppController(backend: backend);

    await controller.refreshAfterWrite(
      WriteOperation.libbookCancelBooking,
      const FeatureQuery(
        view: FeatureQueryView.libbookBookings,
        page: 3,
        size: 10,
      ),
    );

    expect(backend.queries, hasLength(1));
    expect(backend.queries.single.$1, FeatureId.libbook);
    expect(backend.queries.single.$2.view, FeatureQueryView.libbookBookings);
    expect(backend.queries.single.$2.page, 3);
    expect(backend.queries.single.$2.size, 10);
    controller.dispose();
  });

  test('场馆提交收据只匹配刷新后订单列表中的公开编号', () async {
    final backend = _CgyyQueryWriteBackend(
      queryResult: const FeatureResult.success(
        details: <FeatureDetail>[
          FeatureDetail(
            title: '场馆订单',
            fields: <FeatureField>[FeatureField(label: '订单编号', value: '42')],
          ),
        ],
      ),
    );
    final controller = AppController(backend: backend);

    await controller.refreshAfterWrite(WriteOperation.cgyySubmitReservation);

    expect(
      await controller.matchesCgyyReceipt(
        const CgyyReservationReceipt(orderId: 42),
      ),
      isTrue,
    );
    expect(
      await controller.matchesCgyyReceipt(
        const CgyyReservationReceipt(orderId: 43),
      ),
      isFalse,
    );
    controller.dispose();
  });

  test('场馆取消双回读只用 Core strict 同 ID 已取消证明标记已核对', () async {
    final backend = _CgyyCancelReadbackBackend((query) async {
      final action = CgyyCancelAction(
        orderId: 17,
        orderStatus: 2,
        checkStatus: 2,
        targetOrderId: null,
        cancelledTargetOrderId: 17,
        eligibility: ActionEligibility.denied,
      );
      return FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: <FeatureDetail>[
          FeatureDetail(
            title: query.view == FeatureQueryView.cgyyOrders ? '订单列表' : '订单详情',
            fields: const <FeatureField>[
              FeatureField(label: '订单编号', value: '999'),
              FeatureField(label: '订单状态', value: '1'),
            ],
            actions: <FeatureAction>[action],
          ),
        ],
      );
    });
    final controller = AppController(backend: backend);

    expect(
      await controller.verifyCgyyCancellation(
        orderId: 17,
        expectedRoute: ConnectionMode.direct,
      ),
      isTrue,
    );
    expect(backend.queries.map((query) => query.view), <FeatureQueryView>[
      FeatureQueryView.cgyyOrders,
      FeatureQueryView.cgyyOrderDetail,
    ]);
    expect(backend.queries.last.orderId, 17);
    expect(backend.queries.first.page, 0);
    expect(backend.readbackRoutes, const <ConnectionMode>[
      ConnectionMode.direct,
      ConnectionMode.direct,
    ]);
    final snapshot = controller.snapshots[FeatureId.cgyy]!;
    expect(snapshot.status, FeatureLoadStatus.success);
    expect(snapshot.details.single.title, '订单列表');
    expect(snapshot.resolvedRoute, ConnectionMode.direct);
    controller.dispose();
  });

  test('场馆取消双回读的空失败路线冲突或 strict 证明缺失均保持未核对', () async {
    final cases = <Future<FeatureResult> Function(FeatureQuery)>[
      (query) async => query.view == FeatureQueryView.cgyyOrders
          ? _cgyyCancelReadbackResult(
              orderId: 17,
              orderStatus: 2,
              route: ConnectionMode.direct,
            )
          : const FeatureResult.empty(resolvedRoute: ConnectionMode.direct),
      (query) async {
        if (query.view == FeatureQueryView.cgyyOrders) {
          throw const BackendException(UbaaErrorCode.networkError);
        }
        return _cgyyCancelReadbackResult(
          orderId: 17,
          orderStatus: 2,
          route: ConnectionMode.direct,
        );
      },
      (query) async => _cgyyCancelReadbackResult(
        orderId: 17,
        orderStatus: 2,
        route: ConnectionMode.webvpn,
      ),
      (query) async => _cgyyCancelReadbackResult(
        orderId: query.view == FeatureQueryView.cgyyOrders ? 17 : 18,
        orderStatus: 2,
        route: ConnectionMode.direct,
      ),
      (query) async => _cgyyCancelReadbackResult(
        orderId: 17,
        orderStatus: query.view == FeatureQueryView.cgyyOrders ? 2 : 1,
        route: ConnectionMode.direct,
      ),
      (query) async => _cgyyCancelReadbackResult(
        orderId: 17,
        orderStatus: 2,
        route: ConnectionMode.direct,
      ),
    ];

    for (final load in cases) {
      final backend = _CgyyCancelReadbackBackend(load);
      final controller = AppController(backend: backend);

      expect(
        await controller.verifyCgyyCancellation(
          orderId: 17,
          expectedRoute: ConnectionMode.direct,
        ),
        isFalse,
      );
      expect(backend.queries, hasLength(2));
      expect(backend.queries.last.orderId, 17);
      expect(backend.readbackRoutes, const <ConnectionMode>[
        ConnectionMode.direct,
        ConnectionMode.direct,
      ]);
      expect(
        controller.snapshots[FeatureId.cgyy]!.resolvedRoute,
        isNot(ConnectionMode.webvpn),
      );
      controller.dispose();
    }
  });

  test('场馆取消双回读不得因并发 generation 丢弃本次列表后误用旧 snapshot', () async {
    final listStarted = Completer<void>();
    final releaseList = Completer<void>();
    final verified = FeatureResult.success(
      resolvedRoute: ConnectionMode.direct,
      details: <FeatureDetail>[
        FeatureDetail(
          title: '旧场馆订单',
          actions: <FeatureAction>[
            CgyyCancelAction(
              orderId: 17,
              orderStatus: 2,
              checkStatus: 2,
              targetOrderId: null,
              cancelledTargetOrderId: 17,
              eligibility: ActionEligibility.denied,
            ),
          ],
        ),
      ],
    );
    final backend = _CgyyCancelReadbackBackend((query) async {
      if (query.view == FeatureQueryView.cgyyOrders) {
        listStarted.complete();
        await releaseList.future;
        return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
      }
      return verified;
    });
    final controller = AppController(backend: backend);

    final verification = controller.verifyCgyyCancellation(
      orderId: 17,
      expectedRoute: ConnectionMode.direct,
    );
    await listStarted.future;
    await controller.refreshFeatureQuery(
      FeatureId.cgyy,
      const FeatureQuery(view: FeatureQueryView.cgyyOrderDetail, orderId: 999),
    );
    releaseList.complete();

    expect(await verification, isFalse);
    expect(backend.queries.map((query) => query.view), <FeatureQueryView>[
      FeatureQueryView.cgyyOrders,
      FeatureQueryView.cgyyOrderDetail,
      FeatureQueryView.cgyyOrderDetail,
    ]);
    expect(backend.readbackRoutes, const <ConnectionMode>[
      ConnectionMode.direct,
      ConnectionMode.direct,
    ]);
    final snapshot = controller.snapshots[FeatureId.cgyy]!;
    expect(snapshot.status, FeatureLoadStatus.success);
    expect(snapshot.details.single.title, '旧场馆订单');
    controller.dispose();
  });
}

FeatureResult _cgyyCancelReadbackResult({
  required int orderId,
  required int? orderStatus,
  required ConnectionMode route,
}) => FeatureResult.success(
  resolvedRoute: route,
  details: <FeatureDetail>[
    FeatureDetail(
      title: '场馆订单',
      actions: <FeatureAction>[
        CgyyCancelAction(
          orderId: orderId,
          orderStatus: orderStatus,
          checkStatus: 2,
          targetOrderId: null,
          eligibility: ActionEligibility.denied,
        ),
      ],
    ),
  ],
);

const _cgyyFirstAction = CgyyReserveAction(
  venueSiteId: 3,
  reservationDate: '2026-09-03',
  spaceId: 4,
  timeId: 900,
  venueSpaceGroupId: 9,
  timeOrdinal: 0,
  eligibility: ActionEligibility.allowed,
);

const _cgyySecondAction = CgyyReserveAction(
  venueSiteId: 3,
  reservationDate: '2026-09-03',
  spaceId: 4,
  timeId: 100,
  venueSpaceGroupId: 9,
  timeOrdinal: 1,
  eligibility: ActionEligibility.allowed,
);

const _cgyyThirdAction = CgyyReserveAction(
  venueSiteId: 3,
  reservationDate: '2026-09-03',
  spaceId: 4,
  timeId: 700,
  venueSpaceGroupId: 9,
  timeOrdinal: 2,
  eligibility: ActionEligibility.allowed,
);

CgyySubmitInput _cgyySubmitInput({
  List<CgyyReserveAction> actions = const <CgyyReserveAction>[_cgyyFirstAction],
  String joiners = '  张三  ',
}) => CgyySubmitInput(
  actions: actions,
  phone: ' phone-placeholder ',
  theme: ' 课程讨论 ',
  purposeType: 1,
  joinerNum: 2,
  activityContent: ' 讨论 ',
  joiners: joiners,
  isPhilosophySocialSciences: false,
  isOffSchoolJoiner: false,
);

FeatureId _expectedFeature(WriteOperation operation) => switch (operation) {
  WriteOperation.bykcSelectCourse ||
  WriteOperation.bykcDeselectCourse ||
  WriteOperation.bykcSignCourse => FeatureId.bykc,
  WriteOperation.signinPerform => FeatureId.signin,
  WriteOperation.libbookReserve ||
  WriteOperation.libbookCancelBooking => FeatureId.libbook,
  WriteOperation.ygdkSubmit => FeatureId.ygdk,
  WriteOperation.cgyySubmitReservation ||
  WriteOperation.cgyyCancelOrder => FeatureId.cgyy,
  WriteOperation.evaluationSubmitCourses => FeatureId.evaluation,
};
