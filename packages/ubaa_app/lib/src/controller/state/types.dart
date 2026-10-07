import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

enum AppPhase { splash, checkingSession, login, loggingIn, home }

enum SessionRecoveryStatus {
  idle,
  restoring,
  ready,
  unavailable,
  needsLogin,
  signedOut,
}

@immutable
class LoginFormState {
  const LoginFormState({
    this.username = '',
    this.password = '',
    this.captcha = '',
    this.rememberPassword = false,
    this.autoLogin = false,
    this.routePolicy = RoutePolicy.auto,
  });

  final String username;
  final String password;
  final String captcha;
  final bool rememberPassword;
  final bool autoLogin;
  final RoutePolicy routePolicy;

  LoginFormState copyWith({
    String? username,
    String? password,
    String? captcha,
    bool? rememberPassword,
    bool? autoLogin,
    RoutePolicy? routePolicy,
  }) => LoginFormState(
    username: username ?? this.username,
    password: password ?? this.password,
    captcha: captcha ?? this.captcha,
    rememberPassword: rememberPassword ?? this.rememberPassword,
    autoLogin: autoLogin ?? this.autoLogin,
    routePolicy: routePolicy ?? this.routePolicy,
  );
}
