import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  test('共享 bootstrap 严格按初始化顺序启动同一宿主', () async {
    final events = <String>[];
    final vault = MemoryCredentialVault();
    final picker = MemoryPhotoPicker();
    final permissions = MemoryPermissionGateway();
    final locations = MemoryLocationProvider();
    Widget? launched;

    await bootstrapUbaaHost(
      ensureFlutterInitialized: () => events.add('binding'),
      initializeSdk: () async {
        events.add('sdk:start');
        await Future<void>.delayed(Duration.zero);
        events.add('sdk:end');
      },
      debugHello: () {
        events.add('hello');
        return 'UBAA FRB 2.13.0 ready';
      },
      createCapabilities: () async {
        events.add('capabilities:start');
        await Future<void>.delayed(Duration.zero);
        events.add('capabilities:end');
        return PlatformCapabilities(
          credentialVault: vault,
          photoPicker: picker,
          permissionGateway: permissions,
          locationProvider: locations,
        );
      },
      runApplication: (app) {
        events.add('runApp');
        launched = app;
      },
    );

    expect(events, <String>[
      'binding',
      'sdk:start',
      'sdk:end',
      'hello',
      'capabilities:start',
      'capabilities:end',
      'runApp',
    ]);
    final host = launched! as UbaaAppHost;
    expect(host.credentialVault, same(vault));
    expect(host.photoPicker, same(picker));
    expect(host.permissionGateway, same(permissions));
    expect(host.locationProvider, same(locations));
  });

  test('SDK 初始化失败时不探测 hello、不创建能力也不运行应用', () async {
    final events = <String>[];
    final failure = StateError('脱敏 SDK 初始化失败');

    await expectLater(
      bootstrapUbaaHost(
        ensureFlutterInitialized: () => events.add('binding'),
        initializeSdk: () async {
          events.add('sdk');
          throw failure;
        },
        debugHello: () {
          events.add('hello');
          return 'UBAA FRB 2.13.0 ready';
        },
        createCapabilities: () async {
          events.add('capabilities');
          return _capabilities();
        },
        runApplication: (_) => events.add('runApp'),
      ),
      throwsA(same(failure)),
    );
    expect(events, <String>['binding', 'sdk']);
  });

  test('debug hello 失败时不创建能力也不运行应用', () async {
    final events = <String>[];

    await expectLater(
      bootstrapUbaaHost(
        ensureFlutterInitialized: () => events.add('binding'),
        initializeSdk: () async => events.add('sdk'),
        debugHello: () {
          events.add('hello');
          return 'unexpected';
        },
        createCapabilities: () async {
          events.add('capabilities');
          return _capabilities();
        },
        runApplication: (_) => events.add('runApp'),
      ),
      throwsA(isA<AssertionError>()),
    );
    expect(events, <String>['binding', 'sdk', 'hello']);
  });

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

    final cgyyCancelIntent = await shell.onPrepareCancellationWrite!(
      WriteOperation.cgyyCancelOrder,
      '41006',
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
      fileName: ' activity-41015.jpg ',
      mimeType: ' IMAGE/JPEG ',
    );
    const ygdkInput = YgdkSubmitInput(
      itemId: 41016,
      startTime: ' 08:17 ',
      endTime: ' 09:18 ',
      place: ' playground-41019 ',
      shareToSquare: true,
      photo: writePhoto,
    );
    final ygdkIntent = await shell.onPrepareYgdkSubmitWrite!(ygdkInput);
    expect(ygdkIntent.operation, WriteOperation.ygdkSubmit);
    expect(ygdkIntent.intentId, 'intent-ygdk-submit');
    expect(backend.ygdkInput?.itemId, 41016);
    expect(backend.ygdkInput?.startTime, '08:17');
    expect(backend.ygdkInput?.endTime, '09:18');
    expect(backend.ygdkInput?.place, 'playground-41019');
    expect(backend.ygdkInput?.shareToSquare, isTrue);
    expect(backend.ygdkInput?.photo?.bytes, <int>[41, 13, 14]);
    expect(backend.ygdkInput?.photo?.fileName, 'activity-41015.jpg');
    expect(backend.ygdkInput?.photo?.mimeType, 'image/jpeg');

    const cgyyInput = CgyySubmitInput(
      venueSiteId: 41020,
      reservationDate: ' 2099-04-21 ',
      selections: <CgyyReservationSelectionInput>[
        CgyyReservationSelectionInput(
          spaceId: 41022,
          timeId: 41023,
          venueSpaceGroupId: 41024,
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
    expect(backend.cgyyInput?.venueSiteId, 41020);
    expect(backend.cgyyInput?.reservationDate, '2099-04-21');
    expect(backend.cgyyInput?.selections, hasLength(1));
    expect(backend.cgyyInput?.selections.single.spaceId, 41022);
    expect(backend.cgyyInput?.selections.single.timeId, 41023);
    expect(backend.cgyyInput?.selections.single.venueSpaceGroupId, 41024);
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
      WriteOperation.ygdkSubmit: FeatureId.ygdk,
      WriteOperation.evaluationSubmitCourses: FeatureId.evaluation,
    };
    for (final route in featureRoutes.entries) {
      backend.resetReadCalls();
      await shell.onWriteSuccess!(route.key, null);
      expect(backend.loadedFeatures, <FeatureId>[route.value]);
      expect(backend.queryCalls, isEmpty);
    }
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
    for (final operation in <WriteOperation>[
      WriteOperation.cgyySubmitReservation,
      WriteOperation.cgyyCancelOrder,
    ]) {
      backend.resetReadCalls();
      await shell.onWriteSuccess!(operation, null);
      expect(backend.loadedFeatures, isEmpty);
      expect(backend.queryCalls, hasLength(1));
      expect(backend.queryCalls.single.feature, FeatureId.cgyy);
      expect(backend.queryCalls.single.query.view, FeatureQueryView.cgyyOrders);
    }
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

  testWidgets('共享宿主把提交异常隔离为 domain UiError', (tester) async {
    final backend = _RecordingBackend()..signedIn = true;
    await tester.pumpWidget(UbaaAppHost(backend: backend));
    await tester.pumpAndSettle();
    final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));

    backend.commitFailure = const BackendException(UbaaErrorCode.networkError);
    await expectLater(
      shell.onCommitWrite!('intent-network-error'),
      throwsA(
        isA<UiError>().having(
          (error) => error.code,
          'code',
          UbaaErrorCode.networkError,
        ),
      ),
    );

    backend.commitFailure = StateError('/private/token=secret');
    await expectLater(
      shell.onCommitWrite!('intent-internal-error'),
      throwsA(
        isA<UiError>().having(
          (error) => error.code,
          'code',
          UbaaErrorCode.internalError,
        ),
      ),
    );
  });
}

PlatformCapabilities _capabilities() => PlatformCapabilities(
  credentialVault: MemoryCredentialVault(),
  photoPicker: MemoryPhotoPicker(),
  permissionGateway: MemoryPermissionGateway(),
  locationProvider: const UnavailableLocationProvider(),
);

final class _RecordingBackend
    implements
        UbaaBackend,
        FeatureQueryBackend,
        RouteSettingsBackend,
        BykcWriteBackend,
        SigninWriteBackend,
        CancellationWriteBackend,
        LibbookWriteBackend,
        YgdkWriteBackend,
        CgyyWriteBackend,
        EvaluationWriteBackend,
        WriteIntentDiscardBackend,
        BackendLifecycle {
  static const commitResult = WriteCommitResult(
    operation: WriteOperation.cgyySubmitReservation,
    success: true,
    message: 'commit-result-41997',
    outcomeUnknown: false,
    resolvedRoute: ConnectionMode.webvpn,
    cgyyReceipt: CgyyReservationReceipt(orderId: 41999),
  );

  bool signedIn = false;
  RoutePolicy routePolicy = RoutePolicy.auto;
  LoginInput? lastLogin;
  final List<FeatureId> loadedFeatures = <FeatureId>[];
  final List<({FeatureId feature, FeatureQuery query})> queryCalls =
      <({FeatureId feature, FeatureQuery query})>[];
  int? bykcSelectCourseId;
  int? bykcDeselectCourseId;
  ({int courseId, double? lat, double? lng, int signType})? bykcSign;
  String? signinCourseId;
  String? libbookCancellationId;
  int? libbookCancellationPage;
  int? libbookCancellationLimit;
  int? cgyyCancellationId;
  ({
    String areaId,
    String seatId,
    String day,
    String segment,
    String startTime,
    String endTime,
  })?
  libbookReservation;
  YgdkSubmitInput? ygdkInput;
  CgyySubmitInput? cgyyInput;
  List<EvaluationCourseInput>? evaluationCourses;
  String? committedIntentId;
  String? discardedIntentId;
  Object? commitFailure;
  int logoutCalls = 0;
  int disposeCalls = 0;

  void resetReadCalls() {
    loadedFeatures.clear();
    queryCalls.clear();
  }

  @override
  Future<AuthStatus> authStatus() async =>
      signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;

  @override
  Future<UserSummary?> userInfo() async => signedIn
      ? const UserSummary(username: 'student-fixture', displayName: '测试同学')
      : null;

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {
    routePolicy = policy;
  }

  @override
  Future<void> login(LoginInput input) async {
    lastLogin = input;
    signedIn = true;
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    signedIn = false;
  }

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    loadedFeatures.add(feature);
    return FeatureResult.success(summary: '脱敏 ${feature.title}');
  }

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    queryCalls.add((feature: feature, query: query));
    if (feature == FeatureId.cgyy &&
        query.view == FeatureQueryView.cgyyOrders) {
      return const FeatureResult.success(
        summary: '脱敏场馆订单',
        details: <FeatureDetail>[
          FeatureDetail(
            title: '脱敏订单',
            fields: <FeatureField>[FeatureField(label: '订单编号', value: '41999')],
          ),
        ],
      );
    }
    return FeatureResult.success(summary: '脱敏 ${feature.title}');
  }

  @override
  Future<WriteIntent> prepareBykcSelectCourse({required int courseId}) async {
    bykcSelectCourseId = courseId;
    return _intent('bykc-select', WriteOperation.bykcSelectCourse);
  }

  @override
  Future<WriteIntent> prepareBykcDeselectCourse({required int courseId}) async {
    bykcDeselectCourseId = courseId;
    return _intent('bykc-deselect', WriteOperation.bykcDeselectCourse);
  }

  @override
  Future<WriteIntent> prepareBykcSignCourse({
    required int courseId,
    double? lat,
    double? lng,
    required int signType,
  }) async {
    bykcSign = (courseId: courseId, lat: lat, lng: lng, signType: signType);
    return _intent('bykc-sign', WriteOperation.bykcSignCourse);
  }

  @override
  Future<WriteIntent> prepareSigninPerform({required String courseId}) async {
    signinCourseId = courseId;
    return _intent('signin', WriteOperation.signinPerform);
  }

  @override
  Future<WriteIntent> prepareLibbookCancelBooking({
    required String id,
    required int page,
    required int limit,
  }) async {
    libbookCancellationId = id;
    libbookCancellationPage = page;
    libbookCancellationLimit = limit;
    return _intent(
      'libbook-cancel',
      WriteOperation.libbookCancelBooking,
    ).withReadbackQuery(
      FeatureQuery(
        view: FeatureQueryView.libbookBookings,
        page: page,
        size: limit,
      ),
    );
  }

  @override
  Future<WriteIntent> prepareCgyyCancelOrder({required int id}) async {
    cgyyCancellationId = id;
    return _intent('cgyy-cancel', WriteOperation.cgyyCancelOrder);
  }

  @override
  Future<WriteIntent> prepareLibbookReserve({
    required String areaId,
    required String seatId,
    required String day,
    required String segment,
    required String startTime,
    required String endTime,
  }) async {
    libbookReservation = (
      areaId: areaId,
      seatId: seatId,
      day: day,
      segment: segment,
      startTime: startTime,
      endTime: endTime,
    );
    return _intent('libbook-reserve', WriteOperation.libbookReserve);
  }

  @override
  Future<WriteIntent> prepareYgdkSubmit(YgdkSubmitInput input) async {
    ygdkInput = input;
    return _intent('ygdk-submit', WriteOperation.ygdkSubmit);
  }

  @override
  Future<WriteIntent> prepareCgyySubmitReservation(
    CgyySubmitInput input,
  ) async {
    cgyyInput = input;
    return _intent('cgyy-submit', WriteOperation.cgyySubmitReservation);
  }

  @override
  Future<WriteIntent> prepareEvaluationSubmitCourses(
    List<EvaluationCourseInput> courses,
  ) async {
    evaluationCourses = List<EvaluationCourseInput>.unmodifiable(courses);
    return _intent('evaluation-submit', WriteOperation.evaluationSubmitCourses);
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    committedIntentId = intentId;
    final failure = commitFailure;
    if (failure != null) throw failure;
    return commitResult;
  }

  @override
  Future<void> discardWriteIntent(String intentId) async {
    discardedIntentId = intentId;
  }

  @override
  Future<BackendRouteSettings> routeSettings() async => BackendRouteSettings(
    defaultPolicy: routePolicy,
    activeRoutes: signedIn
        ? const <ConnectionMode>[ConnectionMode.direct, ConnectionMode.webvpn]
        : const <ConnectionMode>[],
  );

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }

  WriteIntent _intent(String id, WriteOperation operation) => WriteIntent(
    intentId: 'intent-$id',
    operation: operation,
    targetSummary: 'target-$id',
    resolvedRoute: ConnectionMode.direct,
    warnings: const <String>[],
    expiresAt: DateTime.utc(2099, 1, 1),
    requestDigest: 'digest-$id',
  );
}
