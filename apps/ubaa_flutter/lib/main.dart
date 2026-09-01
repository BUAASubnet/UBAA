import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

Future<void> main() async {
  await RustLib.init();
  assert(bridgeHello() == 'UBAA FRB 2.13.0 ready');
  runApp(const UbaaFlutterApp());
}

/// 官方 Flutter 宿主。生产入口只使用 FRB backend；widget 测试可显式注入
/// [DemoBackend]，初始化失败时显示安全的不可用状态，不伪造业务成功。
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

class _UbaaFlutterAppState extends State<UbaaFlutterApp>
    with WidgetsBindingObserver {
  late final AppController _controller;
  bool _wasBackgrounded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AppController(
      backend: widget.backend ?? createProductionBackend(),
      backendFactory: widget.backend == null ? createProductionBackend : null,
      credentialVault: widget.credentialVault,
      telemetry: widget.telemetry,
    );
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _wasBackgrounded = true;
      return;
    }
    if (state == AppLifecycleState.resumed && _wasBackgrounded) {
      _wasBackgrounded = false;
      // 新 isolate/宿主恢复后重新打开 opaque client；没有生产工厂时该调用
      // 安全返回 false，测试 backend 不会被替换。
      unawaited(_controller.rebuildBackend());
    }
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
      activeRoutes: _controller.activeRoutes,
      telemetryEnabled: _controller.telemetryEnabled,
      onRefresh: _controller.refreshHome,
      onRetryFeature: _controller.retryFeature,
      onFeatureQuery: (feature, query) {
        return _controller.refreshFeatureQuery(feature, query);
      },
          onPrepareBykcWrite: (operation, courseId) =>
              _controller.prepareBykcWrite(operation, courseId),
          onPrepareSigninWrite: _controller.prepareSigninWrite,
          onCommitWrite: _controller.commitWrite,
      onLogout: _controller.logout,
      onLogoutAndClearAccount: () =>
          _controller.logout(clearSavedCredential: true),
      onRoutePolicyChanged: (value) {
        unawaited(_controller.setRoutePolicy(value));
      },
      onTelemetryChanged: (value) {
        unawaited(_controller.setTelemetryEnabled(value));
      },
    ),
  };
}
