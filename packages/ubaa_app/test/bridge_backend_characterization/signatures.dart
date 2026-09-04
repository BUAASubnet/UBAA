part of '../bridge_backend_characterization_test.dart';

void registerBridgeBackendSignatureCharacterization() {
  test('公开构造入口和十二项后端能力保持静态签名且不触发原生调用', () {
    final fake = _CharacterizationBridgeClient();
    final BridgeBackend Function(BridgeClient) constructor = BridgeBackend.new;
    final BridgeBackend Function(String) open = BridgeBackend.open;
    final BackendFactory productionFactory = createProductionBackend;
    final backend = constructor(fake);

    final Future<AuthStatus> Function() ubaaSignature =
        (backend as UbaaBackend).authStatus;
    final Future<FeatureResult> Function(FeatureId, FeatureQuery)
    querySignature = (backend as FeatureQueryBackend).loadFeatureQuery;
    final Future<WriteIntent> Function({required int courseId}) bykcSignature =
        (backend as BykcWriteBackend).prepareBykcSelectCourse;
    final Future<WriteIntent> Function({required String courseId})
    signinSignature = (backend as SigninWriteBackend).prepareSigninPerform;
    final Future<WriteIntent> Function({required int id})
    cancellationSignature =
        (backend as CancellationWriteBackend).prepareCgyyCancelOrder;
    final Future<WriteIntent> Function({
      required String areaId,
      required String seatId,
      required String day,
      required String segment,
      required String startTime,
      required String endTime,
    })
    libbookSignature = (backend as LibbookWriteBackend).prepareLibbookReserve;
    final Future<WriteIntent> Function(YgdkSubmitInput) ygdkSignature =
        (backend as YgdkWriteBackend).prepareYgdkSubmit;
    final Future<WriteIntent> Function(CgyySubmitInput) cgyySignature =
        (backend as CgyyWriteBackend).prepareCgyySubmitReservation;
    final Future<WriteIntent> Function(List<EvaluationCourseInput>)
    evaluationSignature =
        (backend as EvaluationWriteBackend).prepareEvaluationSubmitCourses;
    final Future<BackendRouteSettings> Function() routeSignature =
        (backend as RouteSettingsBackend).routeSettings;
    final Future<void> Function() lifecycleSignature =
        (backend as BackendLifecycle).dispose;
    final Future<void> Function(String) discardSignature =
        (backend as WriteIntentDiscardBackend).discardWriteIntent;
    final Future<BackendRouteSettings> Function(RoutePolicy) setterSignature =
        backend.setDefaultRoutePolicy;

    expect(backend.client, same(fake));
    expect(<Object>[
      open,
      productionFactory,
      ubaaSignature,
      querySignature,
      bykcSignature,
      signinSignature,
      cancellationSignature,
      libbookSignature,
      ygdkSignature,
      cgyySignature,
      evaluationSignature,
      routeSignature,
      lifecycleSignature,
      discardSignature,
      setterSignature,
    ], hasLength(15));
    expect(fake.calls, isEmpty);
  });
}
