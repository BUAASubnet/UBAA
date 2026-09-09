part of '../ui_account_test.dart';

/// 专用于账号界面的合成边界，不继承演示 backend、不接触真实存储。
final class _AccountBackend
    implements UbaaBackend, FeatureQueryBackend, RouteSettingsBackend {
  _AccountBackend({this.state = 'normal'});
  final String state;
  String get contactEmail => state == 'long'
      ? 'synthetic.long.profile.contact.for.multidisciplinary.student@example.invalid'
      : 'synthetic@example.invalid';
  bool signedIn = false;
  RoutePolicy policy = RoutePolicy.auto;
  int reads = 0;
  int logouts = 0;
  LoginInput? lastLogin;
  Completer<void>? loginGate;
  int loginCalls = 0;

  @override
  Future<AuthStatus> authStatus() async {
    if (state == 'restore-error') {
      throw const BackendException(UbaaErrorCode.networkError);
    }
    return signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;
  }

  @override
  Future<UserSummary?> userInfo() async => !signedIn
      ? null
      : UserSummary(
          username: 'account-fixture',
          displayName: state == 'long' ? '合成账号资料长姓名与跨学院联合培养展示换行检查' : '合成同学',
          schoolId: state == 'missing' ? null : '合成学校标识',
          idCardTypeName: state == 'missing' ? null : '合成证件类型',
          email: state == 'missing' ? null : contactEmail,
          phone: state == 'missing' ? null : '00000000000',
        );

  @override
  Future<void> prepareLogin(RoutePolicy value) async {
    policy = value;
  }

  @override
  Future<void> login(LoginInput input) async {
    lastLogin = input;
    loginCalls++;
    if (loginGate != null) await loginGate!.future;
    if (state == 'invalid-credentials') {
      throw const BackendException(UbaaErrorCode.invalidCredentials);
    }
    if (state == 'login-error') {
      throw const BackendException(UbaaErrorCode.networkError);
    }
    signedIn = true;
  }

  @override
  Future<void> logout() async {
    logouts++;
    signedIn = false;
  }

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    reads++;
    if (!signedIn) {
      throw const BackendException(UbaaErrorCode.authenticationRequired);
    }
    return const FeatureResult.success(
      summary: '合成只读摘要',
      details: [FeatureDetail(title: '合成账号巡检课程')],
      resolvedRoute: ConnectionMode.direct,
    );
  }

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) => loadFeature(feature);

  @override
  Future<BackendRouteSettings> routeSettings() async => BackendRouteSettings(
    defaultPolicy: policy,
    // 仅直连已认证，不能将自动策略画成两条路线均成功。
    activeRoutes: signedIn ? [ConnectionMode.direct] : [],
  );
}
