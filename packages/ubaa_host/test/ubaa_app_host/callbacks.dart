part of '../ubaa_app_host_test.dart';

void _registerCallbackTests() {
  testWidgets('共享宿主完整连接登录页与主界面回调', (tester) async {
    final backend = _RecordingBackend();
    final vault = MemoryCredentialVault();
    final photo = const YgdkPhotoInput(
      bytes: <int>[1, 2, 3],
      fileName: 'fixture.jpg',
      mimeType: 'image/jpeg',
    );
    final picker = MemoryPhotoPicker(photo: photo);
    final permissions = MemoryPermissionGateway(
      initial: <PlatformPermission, PlatformPermissionStatus>{
        PlatformPermission.photos: PlatformPermissionStatus.granted,
        PlatformPermission.foregroundLocation: PlatformPermissionStatus.granted,
      },
    );
    final locations = MemoryLocationProvider(
      location: PlatformLocation(lat: 39.9, lng: 116.3),
    );

    await tester.pumpWidget(
      UbaaAppHost(
        backend: backend,
        credentialVault: vault,
        photoPicker: picker,
        permissionGateway: permissions,
        locationProvider: locations,
        initialTab: 2,
      ),
    );
    await tester.pumpAndSettle();

    final login = tester.widget<UbaaLoginView>(find.byType(UbaaLoginView));
    expect(<Object?>[
      login.onUsernameChanged,
      login.onPasswordChanged,
      login.onCaptchaChanged,
      login.onRememberPasswordChanged,
      login.onAutoLoginChanged,
      login.onRoutePolicyChanged,
      login.onSubmit,
    ], everyElement(isA<Function>()));
    login.onUsernameChanged('student-fixture');
    login.onPasswordChanged('fixture-password');
    login.onCaptchaChanged('1234');
    login.onRememberPasswordChanged(true);
    login.onAutoLoginChanged(true);
    login.onRoutePolicyChanged(RoutePolicy.direct);
    await tester.pumpAndSettle();
    login.onSubmit();
    await tester.pumpAndSettle();

    expect(backend.lastLogin?.username, 'student-fixture');
    expect(backend.lastLogin?.password, 'fixture-password');
    expect(backend.lastLogin?.captcha, '1234');
    expect(backend.lastLogin?.rememberPassword, isTrue);
    expect(backend.lastLogin?.autoLogin, isTrue);
    expect(backend.lastLogin?.routePolicy, RoutePolicy.direct);
    expect(vault.saveCount, 1);

    var shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    expect(shell.initialTab, 2);
    backend.resetReadCalls();
    await shell.onRefresh();
    expect(backend.loadedFeatures, FeatureId.values);
    expect(backend.queryCalls, isEmpty);

    backend.resetReadCalls();
    await shell.onRetryFeature(FeatureId.judge);
    expect(backend.loadedFeatures, <FeatureId>[FeatureId.judge]);
    expect(backend.queryCalls, isEmpty);

    const query = FeatureQuery(view: FeatureQueryView.scheduleWeek, week: 3);
    backend.resetReadCalls();
    await shell.onFeatureQuery!(FeatureId.schedule, query);
    expect(backend.loadedFeatures, isEmpty);
    expect(backend.queryCalls, hasLength(1));
    expect(backend.queryCalls.single.feature, FeatureId.schedule);
    expect(backend.queryCalls.single.query, same(query));

    final selectIntent = await shell.onPrepareBykcWrite!(
      WriteOperation.bykcSelectCourse,
      41001,
    );
    expect(selectIntent.operation, WriteOperation.bykcSelectCourse);
    expect(selectIntent.intentId, 'intent-bykc-select');
    expect(backend.bykcSelectCourseId, 41001);

    final deselectIntent = await shell.onPrepareBykcWrite!(
      WriteOperation.bykcDeselectCourse,
      41002,
    );
    expect(deselectIntent.operation, WriteOperation.bykcDeselectCourse);
    expect(deselectIntent.intentId, 'intent-bykc-deselect');
    expect(backend.bykcDeselectCourseId, 41002);

    final signIntent = await shell.onPrepareBykcSignWrite!(
      const BykcSignAction(
        courseId: 41003,
        kind: BykcSignKind.signIn,
        eligibility: ActionEligibility.allowed,
        requiresCoordinates: false,
      ),
    );
    expect(signIntent.operation, WriteOperation.bykcSignCourse);
    expect(signIntent.intentId, 'intent-bykc-sign');
    expect(backend.bykcSign?.courseId, 41003);
    expect(backend.bykcSign?.signType, 1);
    expect(backend.bykcSign?.lat, isNull);
    expect(backend.bykcSign?.lng, isNull);
    expect(locations.requestCount, 0);
    expect(
      permissions.requests,
      isNot(contains(PlatformPermission.foregroundLocation)),
    );

    await shell.onPrepareBykcSignWrite!(
      const BykcSignAction(
        courseId: 41003,
        kind: BykcSignKind.signOut,
        eligibility: ActionEligibility.allowed,
        requiresCoordinates: true,
      ),
    );
    expect(backend.bykcSign?.signType, 2);
    expect(backend.bykcSign?.lat, 39.9);
    expect(backend.bykcSign?.lng, 116.3);
    expect(locations.requestCount, 1);
    expect(
      permissions.requests,
      contains(PlatformPermission.foregroundLocation),
    );

    await shell.onDiscardWriteIntent!(' intent-bykc-sign ');
    expect(backend.discardedIntentId, 'intent-bykc-sign');

    const signinAction = SigninPerformAction(
      scheduleId: ' signin-course-41004 ',
      eligibility: ActionEligibility.allowed,
    );
    final signinIntent = await shell.onPrepareSigninWrite!(signinAction);
    expect(signinIntent.operation, WriteOperation.signinPerform);
    expect(signinIntent.intentId, 'intent-signin');
    expect(backend.signinCourseId, 'signin-course-41004');

    final libbookCancelIntent = await shell.onPrepareLibbookCancelWrite!(
      const LibbookCancelAction(
        bookingId: ' booking-41005 ',
        page: 2,
        limit: 10,
        eligibility: ActionEligibility.allowed,
      ),
    );
    expect(libbookCancelIntent.operation, WriteOperation.libbookCancelBooking);
    expect(libbookCancelIntent.intentId, 'intent-libbook-cancel');
    expect(backend.libbookCancellationId, 'booking-41005');
    expect(backend.libbookCancellationPage, 2);
    expect(backend.libbookCancellationLimit, 10);

    final cgyyCancelIntent = await shell.onPrepareCgyyCancelWrite!(
      const CgyyCancelAction(
        orderId: 41006,
        orderStatus: 1,
        checkStatus: 2,
        targetOrderId: 41006,
        eligibility: ActionEligibility.allowed,
      ),
    );
    expect(cgyyCancelIntent.operation, WriteOperation.cgyyCancelOrder);
    expect(cgyyCancelIntent.intentId, 'intent-cgyy-cancel');
    expect(backend.cgyyCancellationId, 41006);

    const libbookAction = LibbookReserveAction(
      areaId: ' area-41007 ',
      seatId: ' seat-41008 ',
      day: ' 2099-04-09 ',
      segment: ' segment-41010 ',
      startTime: ' 08:11 ',
      endTime: ' 09:12 ',
      eligibility: ActionEligibility.allowed,
    );
    final reserveIntent = await shell.onPrepareLibbookReserveWrite!(
      libbookAction,
    );
    expect(reserveIntent.operation, WriteOperation.libbookReserve);
    expect(reserveIntent.intentId, 'intent-libbook-reserve');
    expect(backend.libbookReservation?.areaId, 'area-41007');
    expect(backend.libbookReservation?.seatId, 'seat-41008');
    expect(backend.libbookReservation?.day, '2099-04-09');
    expect(backend.libbookReservation?.segment, 'segment-41010');
    expect(backend.libbookReservation?.startTime, '08:11');
    expect(backend.libbookReservation?.endTime, '09:12');

    const writePhoto = YgdkPhotoInput(
      bytes: <int>[41, 13, 14],
      fileName: 'activity-41015.jpg',
      mimeType: 'image/jpeg',
    );
    const ygdkInput = YgdkSubmitInput(
      action: YgdkSubmitAction(
        classifyId: 41014,
        itemId: 41016,
        eligibility: ActionEligibility.allowed,
      ),
      startTime: '2099-04-17 08:17',
      endTime: '2099-04-17 09:18',
      place: ' playground-41019 ',
      shareToSquare: true,
      photo: writePhoto,
    );
    final ygdkIntent = await shell.onPrepareYgdkSubmitWrite!(ygdkInput);
    expect(ygdkIntent.operation, WriteOperation.ygdkSubmit);
    expect(ygdkIntent.intentId, 'intent-ygdk-submit');
    expect(backend.ygdkInput?.action.classifyId, 41014);
    expect(backend.ygdkInput?.action.itemId, 41016);
    expect(backend.ygdkInput?.startTime, '2099-04-17 08:17');
    expect(backend.ygdkInput?.endTime, '2099-04-17 09:18');
    expect(backend.ygdkInput?.place, 'playground-41019');
    expect(backend.ygdkInput?.shareToSquare, isTrue);
    expect(backend.ygdkInput?.photo.bytes, <int>[41, 13, 14]);
    expect(backend.ygdkInput?.photo.fileName, 'activity-41015.jpg');
    expect(backend.ygdkInput?.photo.mimeType, 'image/jpeg');

    const cgyyInput = CgyySubmitInput(
      actions: <CgyyReserveAction>[
        CgyyReserveAction(
          venueSiteId: 41020,
          reservationDate: ' 2099-04-21 ',
          spaceId: 41022,
          timeId: 41023,
          venueSpaceGroupId: 41024,
          timeOrdinal: 0,
          eligibility: ActionEligibility.allowed,
        ),
      ],
      phone: ' fixture-phone-41025 ',
      theme: ' fixture-theme-41026 ',
      purposeType: 41027,
      joinerNum: 41028,
      activityContent: ' fixture-content-41029 ',
      joiners: ' fixture-joiners-41030 ',
      isPhilosophySocialSciences: true,
      isOffSchoolJoiner: false,
    );
    final cgyyIntent = await shell.onPrepareCgyySubmitWrite!(cgyyInput);
    expect(cgyyIntent.operation, WriteOperation.cgyySubmitReservation);
    expect(cgyyIntent.intentId, 'intent-cgyy-submit');
    expect(backend.cgyyInput?.actions.single.venueSiteId, 41020);
    expect(backend.cgyyInput?.actions.single.reservationDate, '2099-04-21');
    expect(backend.cgyyInput?.actions, hasLength(1));
    expect(backend.cgyyInput?.actions.single.spaceId, 41022);
    expect(backend.cgyyInput?.actions.single.timeId, 41023);
    expect(backend.cgyyInput?.actions.single.venueSpaceGroupId, 41024);
    expect(backend.cgyyInput?.actions.single.timeOrdinal, 0);
    expect(backend.cgyyInput?.phone, 'fixture-phone-41025');
    expect(backend.cgyyInput?.theme, 'fixture-theme-41026');
    expect(backend.cgyyInput?.purposeType, 41027);
    expect(backend.cgyyInput?.joinerNum, 41028);
    expect(backend.cgyyInput?.activityContent, 'fixture-content-41029');
    expect(backend.cgyyInput?.joiners, 'fixture-joiners-41030');
    expect(backend.cgyyInput?.isPhilosophySocialSciences, isTrue);
    expect(backend.cgyyInput?.isOffSchoolJoiner, isFalse);

    const evaluationInput = EvaluationCourseInput(
      id: ' evaluation-id-41031 ',
      kcmc: ' course-name-41032 ',
      bpmc: ' teacher-name-41033 ',
      rwid: ' task-41034 ',
      wjid: ' questionnaire-41035 ',
      kcdm: ' course-code-41036 ',
      bpdm: ' teacher-code-41037 ',
      pjrdm: ' evaluator-code-41038 ',
      pjrmc: ' evaluator-name-41039 ',
      xnxq: ' term-41040 ',
      msid: ' mode-41041 ',
      zdmc: ' site-41042 ',
      ypjcs: 41043,
      xypjcs: 41044,
      sxz: ' attribute-41045 ',
      rwh: ' task-number-41046 ',
      xn: ' year-41047 ',
      xq: ' semester-41048 ',
      pjlxid: ' type-41049 ',
      sfksqbpj: ' allowed-41050 ',
      yxsfktjst: ' submitted-41051 ',
    );
    final evaluationIntent = await shell.onPrepareEvaluationWrite!(
      const <EvaluationCourseInput>[evaluationInput],
    );
    expect(evaluationIntent.operation, WriteOperation.evaluationSubmitCourses);
    expect(evaluationIntent.intentId, 'intent-evaluation-submit');
    final evaluation = backend.evaluationCourses?.single;
    expect(evaluation?.id, 'evaluation-id-41031');
    expect(evaluation?.kcmc, 'course-name-41032');
    expect(evaluation?.bpmc, 'teacher-name-41033');
    expect(evaluation?.isEvaluated, isFalse);
    expect(evaluation?.rwid, 'task-41034');
    expect(evaluation?.wjid, 'questionnaire-41035');
    expect(evaluation?.kcdm, 'course-code-41036');
    expect(evaluation?.bpdm, 'teacher-code-41037');
    expect(evaluation?.pjrdm, 'evaluator-code-41038');
    expect(evaluation?.pjrmc, 'evaluator-name-41039');
    expect(evaluation?.xnxq, 'term-41040');
    expect(evaluation?.msid, 'mode-41041');
    expect(evaluation?.zdmc, 'site-41042');
    expect(evaluation?.ypjcs, 41043);
    expect(evaluation?.xypjcs, 41044);
    expect(evaluation?.sxz, 'attribute-41045');
    expect(evaluation?.rwh, 'task-number-41046');
    expect(evaluation?.xn, 'year-41047');
    expect(evaluation?.xq, 'semester-41048');
    expect(evaluation?.pjlxid, 'type-41049');
    expect(evaluation?.sfksqbpj, 'allowed-41050');
    expect(evaluation?.yxsfktjst, 'submitted-41051');

    final commitResult = await shell.onCommitWrite!('intent-commit-41052');
    expect(backend.committedIntentId, 'intent-commit-41052');
    expect(commitResult, same(_RecordingBackend.commitResult));

    expect(await shell.onPickYgdkPhoto!(), same(photo));
    expect(permissions.requests, <PlatformPermission>[
      PlatformPermission.foregroundLocation,
      PlatformPermission.photos,
    ]);

    const featureRoutes = <WriteOperation, FeatureId>{
      WriteOperation.bykcSelectCourse: FeatureId.bykc,
      WriteOperation.bykcDeselectCourse: FeatureId.bykc,
      WriteOperation.bykcSignCourse: FeatureId.bykc,
      WriteOperation.signinPerform: FeatureId.signin,
      WriteOperation.evaluationSubmitCourses: FeatureId.evaluation,
    };
    for (final route in featureRoutes.entries) {
      backend.resetReadCalls();
      await shell.onWriteSuccess!(route.key, null);
      expect(backend.loadedFeatures, <FeatureId>[route.value]);
      expect(backend.queryCalls, isEmpty);
    }
    backend.resetReadCalls();
    await shell.onWriteSuccess!(WriteOperation.ygdkSubmit, null);
    expect(backend.loadedFeatures, isEmpty);
    expect(backend.queryCalls, isEmpty);
    expect(backend.ygdkOverviewRoutes, isEmpty);
    expect(backend.ygdkRecordReads, isEmpty);

    await shell.onRefreshYgdkAfterWrite!(expectedRoute: ConnectionMode.webvpn);
    expect(backend.loadedFeatures, isEmpty);
    expect(backend.queryCalls, isEmpty);
    expect(backend.ygdkOverviewRoutes, <ConnectionMode>[ConnectionMode.webvpn]);
    expect(
      backend.ygdkRecordReads,
      <({ConnectionMode route, int page, int size})>[
        (route: ConnectionMode.webvpn, page: 1, size: 20),
      ],
    );
    for (final operation in <WriteOperation>[
      WriteOperation.libbookReserve,
      WriteOperation.libbookCancelBooking,
    ]) {
      backend.resetReadCalls();
      await shell.onWriteSuccess!(operation, null);
      expect(backend.loadedFeatures, isEmpty);
      expect(backend.queryCalls, hasLength(1));
      expect(backend.queryCalls.single.feature, FeatureId.libbook);
      expect(
        backend.queryCalls.single.query.view,
        FeatureQueryView.libbookBookings,
      );
    }
    backend.resetReadCalls();
    await shell.onWriteSuccess!(WriteOperation.cgyySubmitReservation, null);
    expect(backend.loadedFeatures, isEmpty);
    expect(backend.queryCalls, hasLength(1));
    expect(backend.queryCalls.single.feature, FeatureId.cgyy);
    expect(backend.queryCalls.single.query.view, FeatureQueryView.cgyyOrders);
    expect(
      await shell.onVerifyCgyyReceipt!(
        const CgyyReservationReceipt(orderId: 41999),
      ),
      isTrue,
    );
    expect(
      await shell.onVerifyCgyyReceipt!(
        const CgyyReservationReceipt(orderId: 41998),
      ),
      isFalse,
    );
    backend.resetReadCalls();
    expect(
      await shell.onVerifyCgyyCancellation!(
        orderId: 41006,
        expectedRoute: ConnectionMode.direct,
      ),
      isTrue,
    );
    expect(
      backend.queryCalls.map((call) => call.query.view),
      <FeatureQueryView>[
        FeatureQueryView.cgyyOrders,
        FeatureQueryView.cgyyOrderDetail,
      ],
    );

    shell.onRoutePolicyChanged(RoutePolicy.webvpn);
    shell.onTelemetryChanged(true);
    await tester.pumpAndSettle();
    shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    expect(shell.routePolicy, RoutePolicy.webvpn);
    expect(shell.telemetryEnabled, isTrue);

    expect(vault.hasValue, isTrue);
    await shell.onLogout();
    expect(vault.hasValue, isTrue);
    await shell.onLogoutAndClearAccount();
    expect(vault.hasValue, isFalse);
    expect(vault.clearCount, 1);
    await tester.pumpAndSettle();
    expect(backend.logoutCalls, 2);
    expect(find.byType(UbaaLoginView), findsOneWidget);
  });
}
