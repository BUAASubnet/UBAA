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

  test('可逆取消写意图按领域严格校验公开编号', () async {
    final backend = _CancellationWriteBackend();
    final controller = AppController(backend: backend);

    final libraryIntent = await controller.prepareCancellationWrite(
      WriteOperation.libbookCancelBooking,
      ' booking-3 ',
    );
    expect(libraryIntent.operation, WriteOperation.libbookCancelBooking);
    expect(backend.bookingId, 'booking-3');

    final venueIntent = await controller.prepareCancellationWrite(
      WriteOperation.cgyyCancelOrder,
      '17',
    );
    expect(venueIntent.operation, WriteOperation.cgyyCancelOrder);
    expect(backend.orderId, 17);

    await expectLater(
      controller.prepareCancellationWrite(
        WriteOperation.cgyyCancelOrder,
        'not-a-number',
      ),
      throwsA(isA<BackendException>()),
    );
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

  test('阳光打卡写意图只保留内存输入并拒绝空照片', () async {
    final backend = _YgdkWriteBackend();
    final controller = AppController(backend: backend);
    final intent = await controller.prepareYgdkWrite(
      const YgdkSubmitInput(
        itemId: 7,
        startTime: '09:00',
        endTime: '10:00',
        place: '校园',
        shareToSquare: false,
        photo: YgdkPhotoInput(
          bytes: <int>[1, 2, 3],
          fileName: 'safe.jpg',
          mimeType: 'image/jpeg',
        ),
      ),
    );
    expect(intent.operation, WriteOperation.ygdkSubmit);
    expect(backend.input?.itemId, 7);
    expect(backend.commitCalls, 0);
    await expectLater(
      controller.prepareYgdkWrite(
        const YgdkSubmitInput(
          photo: YgdkPhotoInput(
            bytes: <int>[],
            fileName: 'empty.jpg',
            mimeType: 'image/jpeg',
          ),
        ),
      ),
      throwsA(isA<BackendException>()),
    );
    controller.dispose();
  });

  test('场馆预约写意图校验公开站点、时段和参与信息', () async {
    final backend = _CgyyWriteBackend();
    final controller = AppController(backend: backend);
    final intent = await controller.prepareCgyySubmitWrite(
      const CgyySubmitInput(
        venueSiteId: 3,
        reservationDate: '2026-09-03',
        selections: <CgyyReservationSelectionInput>[
          CgyyReservationSelectionInput(spaceId: 4, timeId: 5),
        ],
        phone: 'phone-placeholder',
        theme: '课程讨论',
        purposeType: 1,
        joinerNum: 2,
        activityContent: '讨论',
        joiners: '张三',
        isPhilosophySocialSciences: false,
        isOffSchoolJoiner: false,
      ),
    );
    expect(intent.operation, WriteOperation.cgyySubmitReservation);
    expect(backend.input?.venueSiteId, 3);
    expect(backend.commitCalls, 0);
    await expectLater(
      controller.prepareCgyySubmitWrite(
        const CgyySubmitInput(
          venueSiteId: 3,
          reservationDate: '2026-09-03',
          selections: <CgyyReservationSelectionInput>[],
          phone: 'phone-placeholder',
          theme: '课程讨论',
          purposeType: 1,
          joinerNum: 1,
          activityContent: '讨论',
          joiners: '',
          isPhilosophySocialSciences: false,
          isOffSchoolJoiner: false,
        ),
      ),
      throwsA(isA<BackendException>()),
    );
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
      if (operation == WriteOperation.cgyySubmitReservation ||
          operation == WriteOperation.cgyyCancelOrder) {
        expect(backend.loadedFeatures, isEmpty);
        expect(backend.queries, hasLength(1));
        expect(backend.queries.single.$1, FeatureId.cgyy);
        expect(backend.queries.single.$2.view, FeatureQueryView.cgyyOrders);
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
}

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
