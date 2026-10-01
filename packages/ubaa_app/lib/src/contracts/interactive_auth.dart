import 'package:ubaa_domain/ubaa_domain.dart';

import 'routing.dart';

/// 成功继续后的真实身份与实际路线设置，不包含验证材料。
class InteractiveLoginCompletion {
  const InteractiveLoginCompletion({
    required this.user,
    required this.settings,
  });

  final UserSummary user;
  final BackendRouteSettings settings;
}

/// 独立于旧非交互 UbaaBackend 的页面验证通路。
abstract interface class InteractiveLoginBackend {
  Future<LoginVerificationState> beginInteractiveLogin(LoginInput input);

  Future<LoginVerificationState> submitInteractiveLogin(
    LoginInput input,
    Map<ConnectionMode, String> answers,
  );

  Future<LoginVerificationState> refreshInteractiveCaptcha(
    ConnectionMode route,
  );

  Future<InteractiveLoginCompletion> continueInteractiveLogin(
    ConnectionMode selectedRoute, {
    bool pinRoute = false,
  });

  void discardInteractiveCaptcha(ConnectionMode route);

  void cancelInteractiveLogin();
}
