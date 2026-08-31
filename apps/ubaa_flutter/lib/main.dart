import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  runApp(const UbaaFlutterApp());
}

/// 官方 Flutter 宿主。生产构建通过构造函数注入 FRB backend；默认 Demo
/// backend 只用于 UI 预览和 widget 测试，不会访问真实学校服务。
class UbaaFlutterApp extends StatefulWidget {
  const UbaaFlutterApp({
    this.backend,
    this.credentialVault,
    this.telemetry,
    super.key,
  });

  final UbaaBackend? backend;
  final CredentialVault? credentialVault;
  final TelemetryClient? telemetry;

  @override
  State<UbaaFlutterApp> createState() => _UbaaFlutterAppState();
}

class _UbaaFlutterAppState extends State<UbaaFlutterApp> {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AppController(
      backend: widget.backend ?? DemoBackend(),
      credentialVault: widget.credentialVault,
      telemetry: widget.telemetry,
    );
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => MaterialApp(
      title: 'UBAA',
      debugShowCheckedModeBanner: false,
      theme: UbaaTheme.light(),
      darkTheme: UbaaTheme.dark(),
      themeMode: ThemeMode.system,
      home: _buildHome(),
    ),
  );

  Widget _buildHome() => switch (_controller.phase) {
    AppPhase.splash || AppPhase.checkingSession => const UbaaSplashView(),
    AppPhase.login || AppPhase.loggingIn => UbaaLoginView(
      username: _controller.loginForm.username,
      password: _controller.loginForm.password,
      captcha: _controller.loginForm.captcha,
      rememberPassword: _controller.loginForm.rememberPassword,
      autoLogin: _controller.loginForm.autoLogin,
      routePolicy: _controller.loginForm.routePolicy,
      error: _controller.error,
      isLoading: _controller.phase == AppPhase.loggingIn,
      credentialPersistenceAvailable:
          _controller.credentialPersistenceAvailable,
      onUsernameChanged: _controller.setUsername,
      onPasswordChanged: _controller.setPassword,
      onCaptchaChanged: _controller.setCaptcha,
      onRememberPasswordChanged: _controller.setRememberPassword,
      onAutoLoginChanged: _controller.setAutoLogin,
      onRoutePolicyChanged: (value) {
        unawaited(_controller.setRoutePolicy(value));
      },
      onSubmit: () => unawaited(_controller.submitLogin()),
    ),
    AppPhase.home => UbaaMainShell(
      user: _controller.user,
      snapshots: _controller.snapshots,
      routePolicy: _controller.loginForm.routePolicy,
      telemetryEnabled: _controller.telemetryEnabled,
      onRefresh: _controller.refreshHome,
      onRetryFeature: _controller.retryFeature,
      onLogout: _controller.logout,
      onRoutePolicyChanged: (value) {
        unawaited(_controller.setRoutePolicy(value));
      },
      onTelemetryChanged: (value) {
        unawaited(_controller.setTelemetryEnabled(value));
      },
    ),
  };
}
