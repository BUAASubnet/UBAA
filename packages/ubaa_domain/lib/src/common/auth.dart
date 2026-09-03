import 'package:meta/meta.dart';

import 'route.dart';

@immutable
class LoginInput {
  const LoginInput({
    required this.username,
    required this.password,
    this.captcha,
    this.rememberPassword = false,
    this.autoLogin = false,
    this.routePolicy = RoutePolicy.auto,
  });

  final String username;
  final String password;
  final String? captcha;
  final bool rememberPassword;
  final bool autoLogin;
  final RoutePolicy routePolicy;
}

@immutable
class UserSummary {
  const UserSummary({
    required this.username,
    this.displayName,
    this.department,
  });

  final String username;
  final String? displayName;
  final String? department;

  String get preferredName => displayName == null || displayName!.trim().isEmpty
      ? username
      : displayName!;
}
