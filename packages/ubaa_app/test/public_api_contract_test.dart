import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

const _publicNames = <String>[
  'AuthStatus',
  'BackendException',
  'UbaaBackend',
  'BackendRouteSettings',
  'RouteSettingsBackend',
  'FeatureQueryBackend',
  'WriteCommitBackend',
  'BykcWriteBackend',
  'SigninWriteBackend',
  'CancellationWriteBackend',
  'LibbookWriteBackend',
  'YgdkWriteBackend',
  'CgyyWriteBackend',
  'EvaluationWriteBackend',
  'BackendLifecycle',
  'BackendFactory',
  'UnavailableBackend',
  'DemoBackend',
  'AppPhase',
  'LoginFormState',
  'AppController',
  'UbaaErrorMapper',
  'WriteCommitter',
  'WritePreparer',
  'WriteFlowController',
  'BridgeBackend',
  'createProductionBackend',
];

void main() {
  test('ubaa_app barrel 保持二十七个公开名字和稳定签名', () {
    expect(_publicNames, hasLength(27));
    expect(_publicNames.toSet(), hasLength(27));

    // 这些函数只作为编译期合同被引用，不会构造或打开原生 Bridge。
    expect(<Object>[
      _backendInterfaceSignatures,
      _backendValueSignatures,
      _controllerSignatures,
      _writeControllerSignatures,
      _bridgeSignatures,
    ], hasLength(5));
  });
}

List<Object?> _backendInterfaceSignatures(
  UbaaBackend backend,
  RouteSettingsBackend routeSettingsBackend,
  FeatureQueryBackend featureQueryBackend,
  WriteCommitBackend writeCommitBackend,
  BykcWriteBackend bykcWriteBackend,
  SigninWriteBackend signinWriteBackend,
  CancellationWriteBackend cancellationWriteBackend,
  LibbookWriteBackend libbookWriteBackend,
  YgdkWriteBackend ygdkWriteBackend,
  CgyyWriteBackend cgyyWriteBackend,
  EvaluationWriteBackend evaluationWriteBackend,
  BackendLifecycle backendLifecycle,
) {
  final Future<AuthStatus> Function() authStatus = backend.authStatus;
  final Future<UserSummary?> Function() userInfo = backend.userInfo;
  final Future<void> Function(RoutePolicy) prepareLogin = backend.prepareLogin;
  final Future<void> Function(LoginInput) login = backend.login;
  final Future<void> Function() logout = backend.logout;
  final Future<FeatureResult> Function(FeatureId) loadFeature =
      backend.loadFeature;
  final Future<BackendRouteSettings> Function() routeSettings =
      routeSettingsBackend.routeSettings;
  final Future<FeatureResult> Function(FeatureId, FeatureQuery)
  loadFeatureQuery = featureQueryBackend.loadFeatureQuery;
  final Future<WriteCommitResult> Function(String) commitWrite =
      writeCommitBackend.commitWrite;
  final Future<WriteIntent> Function({required int courseId})
  prepareBykcSelectCourse = bykcWriteBackend.prepareBykcSelectCourse;
  final Future<WriteIntent> Function({required int courseId})
  prepareBykcDeselectCourse = bykcWriteBackend.prepareBykcDeselectCourse;
  final Future<WriteIntent> Function({
    required int courseId,
    double? lat,
    double? lng,
    required int signType,
  })
  prepareBykcSignCourse = bykcWriteBackend.prepareBykcSignCourse;
  final Future<WriteIntent> Function({required String courseId})
  prepareSigninPerform = signinWriteBackend.prepareSigninPerform;
  final Future<WriteIntent> Function({required String id})
  prepareLibbookCancelBooking =
      cancellationWriteBackend.prepareLibbookCancelBooking;
  final Future<WriteIntent> Function({required int id}) prepareCgyyCancelOrder =
      cancellationWriteBackend.prepareCgyyCancelOrder;
  final Future<WriteIntent> Function({
    required String areaId,
    required String seatId,
    required String day,
    required String segment,
    required String startTime,
    required String endTime,
  })
  prepareLibbookReserve = libbookWriteBackend.prepareLibbookReserve;
  final Future<WriteIntent> Function(YgdkSubmitInput) prepareYgdkSubmit =
      ygdkWriteBackend.prepareYgdkSubmit;
  final Future<WriteIntent> Function(CgyySubmitInput)
  prepareCgyySubmitReservation = cgyyWriteBackend.prepareCgyySubmitReservation;
  final Future<WriteIntent> Function(List<EvaluationCourseInput>)
  prepareEvaluationSubmitCourses =
      evaluationWriteBackend.prepareEvaluationSubmitCourses;
  final Future<void> Function() dispose = backendLifecycle.dispose;

  return <Object?>[
    authStatus,
    userInfo,
    prepareLogin,
    login,
    logout,
    loadFeature,
    routeSettings,
    loadFeatureQuery,
    commitWrite,
    prepareBykcSelectCourse,
    prepareBykcDeselectCourse,
    prepareBykcSignCourse,
    prepareSigninPerform,
    prepareLibbookCancelBooking,
    prepareCgyyCancelOrder,
    prepareLibbookReserve,
    prepareYgdkSubmit,
    prepareCgyySubmitReservation,
    prepareEvaluationSubmitCourses,
    dispose,
  ];
}

List<Object?> _backendValueSignatures(
  UnavailableBackend unavailableBackend,
  DemoBackend demoBackend,
) {
  const AuthStatus status = AuthStatus.signedOut;
  final BackendException Function(UbaaErrorCode, {String? detail})
  exceptionConstructor = BackendException.new;
  final BackendRouteSettings Function({
    required RoutePolicy defaultPolicy,
    required List<ConnectionMode> activeRoutes,
  })
  routeSettingsConstructor = BackendRouteSettings.new;
  final BackendFactory backendFactory = createProductionBackend;
  final UbaaBackend Function() productionFactory = createProductionBackend;
  final UnavailableBackend Function() unavailableConstructor =
      UnavailableBackend.new;
  final DemoBackend Function({Duration loginDelay}) demoConstructor =
      DemoBackend.new;
  final UbaaBackend unavailableAsBackend = unavailableBackend;
  final BackendLifecycle unavailableAsLifecycle = unavailableBackend;
  final UbaaBackend demoAsBackend = demoBackend;

  return <Object?>[
    status,
    exceptionConstructor,
    routeSettingsConstructor,
    backendFactory,
    productionFactory,
    unavailableConstructor,
    demoConstructor,
    unavailableAsBackend,
    unavailableAsLifecycle,
    demoAsBackend,
  ];
}

List<Object?> _controllerSignatures(
  LoginFormState loginForm,
  AppController appController,
) {
  const AppPhase phase = AppPhase.splash;
  final LoginFormState Function({
    String username,
    String password,
    String captcha,
    bool rememberPassword,
    bool autoLogin,
    RoutePolicy routePolicy,
  })
  loginFormConstructor = LoginFormState.new;
  final LoginFormState Function({
    String? username,
    String? password,
    String? captcha,
    bool? rememberPassword,
    bool? autoLogin,
    RoutePolicy? routePolicy,
  })
  copyLoginForm = loginForm.copyWith;
  final AppController Function({
    required UbaaBackend backend,
    BackendFactory? backendFactory,
    CredentialVault? credentialVault,
    TelemetryClient? telemetry,
  })
  appControllerConstructor = AppController.new;
  final AppPhase Function(AppController) readPhase = (controller) =>
      controller.phase;
  final UiError Function(UbaaErrorCode) mapError = UbaaErrorMapper.fromCode;

  return <Object?>[
    phase,
    loginFormConstructor,
    copyLoginForm,
    appControllerConstructor,
    readPhase,
    mapError,
    appController,
  ];
}

List<Object?> _writeControllerSignatures(
  WriteCommitter writeCommitter,
  WritePreparer writePreparer,
  WriteFlowController writeFlowController,
) {
  final Future<WriteCommitResult> Function(String) commit = writeCommitter;
  final Future<WriteIntent> Function() prepareIntent = writePreparer;
  final WriteFlowController Function({required WriteCommitter commit})
  controllerConstructor = WriteFlowController.new;
  final void Function(WriteIntent) setIntent = writeFlowController.setIntent;
  final Future<WriteIntent?> Function(WritePreparer) prepare =
      writeFlowController.prepare;
  final void Function() cancel = writeFlowController.cancel;
  final Future<WriteCommitResult?> Function() confirm =
      writeFlowController.confirm;

  return <Object?>[
    commit,
    prepareIntent,
    controllerConstructor,
    setIntent,
    prepare,
    cancel,
    confirm,
  ];
}

List<Object?> _bridgeSignatures(BridgeBackend bridgeBackend) {
  _acceptBridgeClientShape(BridgeBackend.new, (backend) => backend.client);
  final BridgeBackend Function(String) open = BridgeBackend.open;
  final Future<BackendRouteSettings> Function(RoutePolicy)
  setDefaultRoutePolicy = bridgeBackend.setDefaultRoutePolicy;
  final Future<BackendRouteSettings> Function() routeSettings =
      bridgeBackend.routeSettings;
  final UbaaBackend Function() productionFactory = createProductionBackend;
  final UbaaBackend backend = bridgeBackend;
  final RouteSettingsBackend routeBackend = bridgeBackend;
  final FeatureQueryBackend queryBackend = bridgeBackend;
  final WriteCommitBackend commitBackend = bridgeBackend;
  final BykcWriteBackend bykcBackend = bridgeBackend;
  final SigninWriteBackend signinBackend = bridgeBackend;
  final CancellationWriteBackend cancellationBackend = bridgeBackend;
  final LibbookWriteBackend libbookBackend = bridgeBackend;
  final YgdkWriteBackend ygdkBackend = bridgeBackend;
  final CgyyWriteBackend cgyyBackend = bridgeBackend;
  final EvaluationWriteBackend evaluationBackend = bridgeBackend;
  final BackendLifecycle lifecycle = bridgeBackend;

  return <Object?>[
    open,
    setDefaultRoutePolicy,
    routeSettings,
    productionFactory,
    backend,
    routeBackend,
    queryBackend,
    commitBackend,
    bykcBackend,
    signinBackend,
    cancellationBackend,
    libbookBackend,
    ygdkBackend,
    cgyyBackend,
    evaluationBackend,
    lifecycle,
  ];
}

void _acceptBridgeClientShape<TClient>(
  BridgeBackend Function(TClient) constructor,
  TClient Function(BridgeBackend) client,
) {}
