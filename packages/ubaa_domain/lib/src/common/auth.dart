import 'package:meta/meta.dart';

import 'route.dart';
import '../feature/data_evidence.dart';

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
    this.schoolId,
    this.email,
    this.phone,
    this.idCardTypeName,
    this.accountScope,
    this.profileEvidence,
    this.profileRoute,
    this.profileNotice,
  });

  final String username;
  final String? displayName;
  final String? department;
  final String? schoolId;
  final String? email;
  final String? phone;
  final String? idCardTypeName;

  /// 仅资料展示的来源；不改变认证资格或账号归属。
  /// 本机展示归属的opaque别名，不是学校账号或认证依据。
  final String? accountScope;
  final DataEvidence? profileEvidence;
  final ConnectionMode? profileRoute;
  final String? profileNotice;

  String get preferredName => displayName == null || displayName!.trim().isEmpty
      ? username
      : displayName!;
}
