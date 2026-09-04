part of '../bridge_backend_characterization_test.dart';

void registerBridgeBackendWriteAndErrorCharacterization() {
  test('十项写准备提交收据结果和完整错误映射保持安全闭包', () async {
    final client = _CharacterizationBridgeClient();
    final backend = BridgeBackend(client);
    final intents = <WriteIntent>[
      await backend.prepareBykcSelectCourse(courseId: 11),
      await backend.prepareBykcDeselectCourse(courseId: 12),
      await backend.prepareBykcSignCourse(
        courseId: 13,
        lat: 39.9,
        lng: 116.3,
        signType: 2,
      ),
      await backend.prepareSigninPerform(courseId: 'signin-1'),
      await backend.prepareLibbookReserve(
        areaId: 'area-1',
        seatId: 'seat-1',
        day: '2026-09-04',
        segment: '1',
        startTime: '08:00',
        endTime: '10:00',
      ),
      await backend.prepareLibbookCancelBooking(
        id: 'booking-1',
        page: 2,
        limit: 10,
      ),
      await backend.prepareYgdkSubmit(
        const YgdkSubmitInput(
          itemId: 7,
          startTime: '08:00',
          endTime: '09:00',
          place: '校园',
          shareToSquare: false,
          photo: YgdkPhotoInput(
            bytes: <int>[1, 2, 3],
            fileName: 'safe.jpg',
            mimeType: 'image/jpeg',
          ),
        ),
      ),
      await backend.prepareCgyySubmitReservation(
        const CgyySubmitInput(
          actions: <CgyyReserveAction>[
            CgyyReserveAction(
              venueSiteId: 7,
              reservationDate: '2026-09-04',
              spaceId: 8,
              timeId: 9,
              venueSpaceGroupId: 10,
              timeOrdinal: 0,
              eligibility: ActionEligibility.allowed,
            ),
          ],
          phone: 'phone-placeholder',
          theme: '课程讨论',
          purposeType: 2,
          joinerNum: 3,
          activityContent: '公开活动摘要',
          joiners: '参与人占位',
          isPhilosophySocialSciences: false,
          isOffSchoolJoiner: false,
        ),
      ),
      await backend.prepareCgyyCancelOrder(id: 14),
      await backend
          .prepareEvaluationSubmitCourses(const <EvaluationCourseInput>[
            EvaluationCourseInput(
              id: 'evaluation-1',
              kcmc: '课程',
              bpmc: '教师',
              rwid: 'task-1',
              wjid: 'questionnaire-1',
              kcdm: 'K1',
              bpdm: 'BP1',
              pjrdm: 'PJR1',
              pjrmc: '评价人',
              xnxq: '2026-fall',
              msid: 'M1',
              zdmc: '终端',
              ypjcs: 1,
              xypjcs: 2,
              sxz: '属性',
              rwh: '任务号',
              xn: '2026',
              xq: '1',
              pjlxid: '类型',
              sfksqbpj: '否',
              yxsfktjst: '是',
              isEvaluated: true,
            ),
          ]),
    ];

    expect(
      intents.map((intent) => intent.operation).toList(growable: false),
      WriteOperation.values,
    );
    final course =
        client.writeRequests[#prepareBykcSelectCourse]
            as BridgeBykcCourseRequest;
    final deselect =
        client.writeRequests[#prepareBykcDeselectCourse]
            as BridgeBykcCourseRequest;
    final sign =
        client.writeRequests[#prepareBykcSignCourse]
            as BridgeBykcSignCourseRequest;
    final reserve =
        client.writeRequests[#prepareLibbookReserve]
            as BridgeLibbookReserveRequest;
    final signin =
        client.writeRequests[#prepareSigninPerform]
            as BridgeSigninPerformRequest;
    final libbookCancel =
        client.writeRequests[#prepareLibbookCancelBooking]
            as BridgeLibbookCancelBookingRequest;
    final ygdk =
        client.writeRequests[#prepareYgdkSubmit] as BridgeYgdkSubmitRequest;
    final cgyy =
        client.writeRequests[#prepareCgyySubmitReservation]
            as BridgeCgyySubmitReservationRequest;
    final evaluation =
        client.writeRequests[#prepareEvaluationSubmitCourses]
            as BridgeEvaluationSubmitCoursesRequest;
    final cgyyCancel =
        client.writeRequests[#prepareCgyyCancelOrder]
            as BridgeCgyyCancelOrderRequest;
    expect(course.courseId, 11);
    expect(deselect.courseId, 12);
    expect(
      <Object?>[sign.courseId, sign.lat, sign.lng, sign.signType],
      <Object?>[13, 39.9, 116.3, 2],
    );
    expect(
      <String>[
        reserve.areaId,
        reserve.seatId,
        reserve.day,
        reserve.segment,
        reserve.startTime,
        reserve.endTime,
      ],
      <String>['area-1', 'seat-1', '2026-09-04', '1', '08:00', '10:00'],
    );
    expect(signin.courseId, 'signin-1');
    expect(
      <Object?>[libbookCancel.id, libbookCancel.page, libbookCancel.limit],
      <Object?>['booking-1', 2, 10],
    );
    expect(cgyyCancel.id, 14);
    expect(
      <Object?>[
        ygdk.itemId,
        ygdk.startTime,
        ygdk.endTime,
        ygdk.place,
        ygdk.shareToSquare,
        ygdk.photo?.bytes.toList(),
        ygdk.photo?.fileName,
        ygdk.photo?.mimeType,
      ],
      <Object?>[
        7,
        '08:00',
        '09:00',
        '校园',
        false,
        <int>[1, 2, 3],
        'safe.jpg',
        'image/jpeg',
      ],
    );
    final selection = cgyy.selections.single;
    expect(
      <Object?>[
        cgyy.venueSiteId,
        cgyy.reservationDate,
        selection.spaceId,
        selection.timeId,
        selection.venueSpaceGroupId,
        cgyy.phone,
        cgyy.theme,
        cgyy.purposeType,
        cgyy.joinerNum,
        cgyy.activityContent,
        cgyy.joiners,
        cgyy.isPhilosophySocialSciences,
        cgyy.isOffSchoolJoiner,
      ],
      <Object?>[
        7,
        '2026-09-04',
        8,
        9,
        10,
        'phone-placeholder',
        '课程讨论',
        2,
        3,
        '公开活动摘要',
        '参与人占位',
        false,
        false,
      ],
    );
    final evaluationCourse = evaluation.courses.single;
    expect(
      <Object?>[
        evaluationCourse.id,
        evaluationCourse.kcmc,
        evaluationCourse.bpmc,
        evaluationCourse.isEvaluated,
        evaluationCourse.rwid,
        evaluationCourse.wjid,
        evaluationCourse.kcdm,
        evaluationCourse.bpdm,
        evaluationCourse.pjrdm,
        evaluationCourse.pjrmc,
        evaluationCourse.xnxq,
        evaluationCourse.msid,
        evaluationCourse.zdmc,
        evaluationCourse.ypjcs,
        evaluationCourse.xypjcs,
        evaluationCourse.sxz,
        evaluationCourse.rwh,
        evaluationCourse.xn,
        evaluationCourse.xq,
        evaluationCourse.pjlxid,
        evaluationCourse.sfksqbpj,
        evaluationCourse.yxsfktjst,
      ],
      <Object?>[
        'evaluation-1',
        '课程',
        '教师',
        true,
        'task-1',
        'questionnaire-1',
        'K1',
        'BP1',
        'PJR1',
        '评价人',
        '2026-fall',
        'M1',
        '终端',
        1,
        2,
        '属性',
        '任务号',
        '2026',
        '1',
        '类型',
        '否',
        '是',
      ],
    );

    client.commitResult = const BridgeWriteCommitResult(
      operation: BridgeWriteOperation.cgyySubmitReservation,
      success: false,
      message: '结果待确认',
      outcomeUnknown: true,
      resolvedRoute: BridgeConnectionMode.webVpn,
      cgyyReceipt: BridgeCgyyReservationReceipt(
        orderId: 42,
        venueSiteId: 7,
        reservationDate: '2026-09-04',
        orderStatus: 1,
      ),
    );
    final committed = await backend.commitWrite('intent-1');
    expect(client.calls.last, 'commitWrite:intentId=intent-1');
    expect(committed.operation, WriteOperation.cgyySubmitReservation);
    expect(committed.success, isFalse);
    expect(committed.outcomeUnknown, isTrue);
    expect(committed.resolvedRoute, ConnectionMode.webvpn);
    expect(
      <Object?>[
        committed.cgyyReceipt?.orderId,
        committed.cgyyReceipt?.venueSiteId,
        committed.cgyyReceipt?.reservationDate,
        committed.cgyyReceipt?.orderStatus,
      ],
      <Object?>[42, 7, '2026-09-04', 1],
    );

    await backend.discardWriteIntent('intent-discard-2');
    expect(client.calls.last, 'discardWriteIntent:intentId=intent-discard-2');
    client.discardError = const BridgeError(
      code: BridgeErrorCode.networkError,
      kind: BridgeErrorKind.network,
      retryable: true,
      message: 'https://private.invalid/session?token=secret',
    );
    await expectLater(
      backend.discardWriteIntent('intent-discard-error'),
      throwsA(
        isA<BackendException>()
            .having((error) => error.code, 'code', UbaaErrorCode.networkError)
            .having((error) => error.detail, 'detail', isNull),
      ),
    );

    const expectedCodes = <BridgeErrorCode, UbaaErrorCode>{
      BridgeErrorCode.invalidInput: UbaaErrorCode.invalidInput,
      BridgeErrorCode.authenticationRequired:
          UbaaErrorCode.authenticationRequired,
      BridgeErrorCode.invalidCredentials: UbaaErrorCode.invalidCredentials,
      BridgeErrorCode.passwordRiskConfirmationFailed:
          UbaaErrorCode.passwordRiskConfirmationFailed,
      BridgeErrorCode.permissionDenied: UbaaErrorCode.permissionDenied,
      BridgeErrorCode.networkError: UbaaErrorCode.networkError,
      BridgeErrorCode.timeout: UbaaErrorCode.timeout,
      BridgeErrorCode.upstreamUnavailable: UbaaErrorCode.upstreamUnavailable,
      BridgeErrorCode.upstreamChanged: UbaaErrorCode.upstreamChanged,
      BridgeErrorCode.parseError: UbaaErrorCode.parseError,
      BridgeErrorCode.internalError: UbaaErrorCode.internalError,
      BridgeErrorCode.clientDisposed: UbaaErrorCode.internalError,
      BridgeErrorCode.confirmationRequired: UbaaErrorCode.confirmationRequired,
      BridgeErrorCode.intentExpired: UbaaErrorCode.intentExpired,
      BridgeErrorCode.operationConflict: UbaaErrorCode.operationConflict,
      BridgeErrorCode.outcomeUnknown: UbaaErrorCode.outcomeUnknown,
    };
    expect(expectedCodes.keys.toSet(), BridgeErrorCode.values.toSet());
    for (final entry in expectedCodes.entries) {
      final exception = await _captureBackendError(
        backend,
        client,
        code: entry.key,
        message: '安全诊断',
      );
      expect(exception.code, entry.value, reason: entry.key.name);
      expect(exception.detail, '安全诊断');
    }

    final safe160 = List<String>.filled(160, '安').join();
    final detailCases = <String, String?>{
      '   ': null,
      safe160: safe160,
      '${safe160}安': null,
      '包含 password 的诊断': null,
      '包含 COOKIE 的诊断': null,
      '包含 Token 的诊断': null,
      '包含 authorization 的诊断': null,
      '访问 http://example.invalid 失败': null,
      '访问 HTTPS://example.invalid 失败': null,
    };
    for (final entry in detailCases.entries) {
      final exception = await _captureBackendError(
        backend,
        client,
        code: BridgeErrorCode.internalError,
        message: entry.key,
      );
      expect(exception.detail, entry.value, reason: entry.key);
    }
  });
}

Future<BackendException> _captureBackendError(
  BridgeBackend backend,
  _CharacterizationBridgeClient client, {
  required BridgeErrorCode code,
  required String message,
}) async {
  client.authError = BridgeError(
    code: code,
    kind: BridgeErrorKind.internal,
    retryable: false,
    message: message,
  );
  try {
    await backend.authStatus();
  } on BackendException catch (error) {
    return error;
  }
  fail('预期 BridgeError 被映射为 BackendException');
}
