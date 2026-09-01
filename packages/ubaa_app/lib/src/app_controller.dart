import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

import 'backend.dart';

enum AppPhase { splash, checkingSession, login, loggingIn, home }

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

/// 应用状态协调器。UI 只订阅此类，不直接持有 FRB handle 或平台存储对象。
class AppController extends ChangeNotifier {
  AppController({
    required UbaaBackend backend,
    CredentialVault? credentialVault,
    TelemetryClient? telemetry,
  }) : _backend = backend,
       _credentialVault = credentialVault ?? const NoopCredentialVault(),
       _telemetry = telemetry ?? const NoopTelemetryClient(),
       _telemetryEnabled = (telemetry ?? const NoopTelemetryClient()).enabled,
       _snapshots = {
         for (final feature in FeatureId.values)
           feature: FeatureSnapshot(feature: feature),
       };

  final UbaaBackend _backend;
  final CredentialVault _credentialVault;
  final TelemetryClient _telemetry;
  final Map<FeatureId, FeatureSnapshot> _snapshots;

  AppPhase _phase = AppPhase.splash;
  LoginFormState _loginForm = const LoginFormState();
  UserSummary? _user;
  UiError? _error;
  bool _disposed = false;
  bool _initialized = false;
  int _refreshGeneration = 0;
  bool _telemetryEnabled;

  AppPhase get phase => _phase;
  LoginFormState get loginForm => _loginForm;
  UserSummary? get user => _user;
  UiError? get error => _error;
  bool get telemetryEnabled => _telemetryEnabled;
  bool get credentialPersistenceAvailable => _credentialVault.isAvailable;
  Map<FeatureId, FeatureSnapshot> get snapshots =>
      Map<FeatureId, FeatureSnapshot>.unmodifiable(_snapshots);

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _setPhase(AppPhase.checkingSession);
    try {
      final status = await _backend.authStatus();
      if (status == AuthStatus.signedIn) {
        _user = await _backend.userInfo();
        if (_user != null) {
          _setPhase(AppPhase.home);
          await _recordAppOpen();
          unawaited(refreshHome());
          return;
        }
      }
      final saved = await _credentialVault.read();
      if (saved != null && saved.isUsable) {
        _loginForm = _loginForm.copyWith(
          username: saved.username,
          autoLogin: saved.autoLogin,
          rememberPassword: _credentialVault.isAvailable,
        );
        if (saved.autoLogin && _credentialVault.isAvailable) {
          // 密码只在当前登录调用的短生命周期内放入 controller；submitLogin 成功
          // 或失败都会清空密码字段，且失败凭据会被清理。
          _loginForm = _loginForm.copyWith(password: saved.password);
          await submitLogin();
          return;
        }
      }
      _setPhase(AppPhase.login);
    } on BackendException catch (exception) {
      _error = UbaaErrorMapper.fromCode(exception.code);
      _setPhase(AppPhase.login);
    } catch (_) {
      _error = UbaaErrorMapper.fromCode(UbaaErrorCode.internalError);
      _setPhase(AppPhase.login);
    }
  }

  void setUsername(String value) {
    _loginForm = _loginForm.copyWith(username: value);
    _error = null;
    _notify();
  }

  void setPassword(String value) {
    _loginForm = _loginForm.copyWith(password: value);
    _error = null;
    _notify();
  }

  void setCaptcha(String value) {
    _loginForm = _loginForm.copyWith(captcha: value);
    _error = null;
    _notify();
  }

  void setRememberPassword(bool value) {
    _loginForm = _loginForm.copyWith(rememberPassword: value);
    _notify();
  }

  void setAutoLogin(bool value) {
    _loginForm = _loginForm.copyWith(
      autoLogin: value,
      rememberPassword: value ? true : _loginForm.rememberPassword,
    );
    _notify();
  }

  Future<void> setRoutePolicy(RoutePolicy value) async {
    if (_phase == AppPhase.loggingIn) return;
    _loginForm = _loginForm.copyWith(routePolicy: value);
    _clearError();
    try {
      await _backend.prepareLogin(value);
    } on BackendException catch (exception) {
      _error = UbaaErrorMapper.fromCode(exception.code);
    } catch (_) {
      _error = UbaaErrorMapper.fromCode(UbaaErrorCode.internalError);
    }
    _notify();
  }

  Future<void> submitLogin() async {
    if (_phase == AppPhase.loggingIn) return;
    final username = _loginForm.username.trim();
    if (username.isEmpty || _loginForm.password.isEmpty) {
      _error = UbaaErrorMapper.fromCode(UbaaErrorCode.invalidInput);
      _notify();
      return;
    }
    _error = null;
    _setPhase(AppPhase.loggingIn);
    try {
      await _backend.login(
        LoginInput(
          username: username,
          password: _loginForm.password,
          captcha: _loginForm.captcha.trim().isEmpty
              ? null
              : _loginForm.captcha.trim(),
          rememberPassword: _loginForm.rememberPassword,
          autoLogin: _loginForm.autoLogin,
          routePolicy: _loginForm.routePolicy,
        ),
      );
      _user = await _backend.userInfo() ?? UserSummary(username: username);
      if (_loginForm.rememberPassword && _credentialVault.isAvailable) {
        await _credentialVault.write(
          Credential(
            username: username,
            password: _loginForm.password,
            autoLogin: _loginForm.autoLogin,
          ),
        );
      } else if (!_loginForm.rememberPassword) {
        await _credentialVault.clear();
      }
      _loginForm = _loginForm.copyWith(password: '', captcha: '');
      _setPhase(AppPhase.home);
      await _recordAppOpen();
      unawaited(refreshHome());
    } on BackendException catch (exception) {
      if (exception.code == UbaaErrorCode.invalidCredentials) {
        await _credentialVault.clear();
      }
      _error = UbaaErrorMapper.fromCode(exception.code);
      _setPhase(AppPhase.login);
    } catch (_) {
      _error = UbaaErrorMapper.fromCode(UbaaErrorCode.internalError);
      _setPhase(AppPhase.login);
    }
  }

  Future<void> refreshHome({Iterable<FeatureId>? only}) async {
    final generation = ++_refreshGeneration;
    final features = (only ?? FeatureId.values).toList(growable: false);
    for (final feature in features) {
      _snapshots[feature] = _snapshots[feature]!.copyWith(
        status: FeatureLoadStatus.loading,
        clearError: true,
      );
    }
    _notify();
    await Future.wait(
      features.map((feature) => _loadFeature(feature, generation)),
    );
  }

  Future<void> retryFeature(FeatureId feature) =>
      refreshHome(only: <FeatureId>[feature]);

  /// 对支持 [FeatureQueryBackend] 的生产实现执行单领域筛选读取。
  ///
  /// 不支持查询的 fake backend 明确报 unsupported，不会在 Dart 端拼接请求。
  Future<void> refreshFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (_backend is! FeatureQueryBackend) {
      _snapshots[feature] = _snapshots[feature]!.copyWith(
        status: FeatureLoadStatus.failure,
        error: UbaaErrorMapper.fromCode(UbaaErrorCode.unsupported),
      );
      _notify();
      return;
    }
    final generation = ++_refreshGeneration;
    _snapshots[feature] = _snapshots[feature]!.copyWith(
      status: FeatureLoadStatus.loading,
      clearError: true,
    );
    _notify();
    await _loadFeature(feature, generation, query: query);
  }

  Future<void> _loadFeature(
    FeatureId feature,
    int generation, {
    FeatureQuery? query,
  }) async {
    final started = DateTime.now();
    final hadPreviousData = _snapshots[feature]!.updatedAt != null;
    try {
      final result = switch ((_backend, query)) {
        (FeatureQueryBackend queryBackend, final FeatureQuery value) =>
          await queryBackend.loadFeatureQuery(feature, value),
        _ => await _backend.loadFeature(feature),
      };
      if (generation != _refreshGeneration) return;
      final status = result.error != null
          ? FeatureLoadStatus.failure
          : result.isEmpty
          ? FeatureLoadStatus.empty
          : FeatureLoadStatus.success;
      _snapshots[feature] = _snapshots[feature]!.copyWith(
        status: status,
        summary: result.summary,
        details: result.details,
        error: result.error,
        resolvedRoute: result.resolvedRoute,
        updatedAt: DateTime.now(),
        clearError: result.error == null,
        clearSummary: result.summary == null,
        clearDetails: result.details.isEmpty,
        clearResolvedRoute: result.resolvedRoute == null,
      );
      await _recordFeature(
        feature,
        success: result.error == null && !result.isEmpty,
        empty: result.isEmpty,
        error: result.error,
        latency: DateTime.now().difference(started),
      );
    } on BackendException catch (exception) {
      if (generation != _refreshGeneration) return;
      final uiError = UbaaErrorMapper.fromCode(exception.code);
      _snapshots[feature] = _snapshots[feature]!.copyWith(
        status: hadPreviousData
            ? FeatureLoadStatus.stale
            : FeatureLoadStatus.failure,
        error: uiError,
        updatedAt: DateTime.now(),
      );
      await _recordFeature(
        feature,
        error: uiError,
        latency: DateTime.now().difference(started),
      );
    } catch (_) {
      if (generation != _refreshGeneration) return;
      _snapshots[feature] = _snapshots[feature]!.copyWith(
        status: hadPreviousData
            ? FeatureLoadStatus.stale
            : FeatureLoadStatus.failure,
        error: UbaaErrorMapper.fromCode(UbaaErrorCode.internalError),
        updatedAt: DateTime.now(),
      );
      await _recordFeature(
        feature,
        error: UbaaErrorMapper.fromCode(UbaaErrorCode.internalError),
        latency: DateTime.now().difference(started),
      );
    }
    _notify();
  }

  Future<void> logout({bool clearSavedCredential = false}) async {
    try {
      await _backend.logout();
    } on Object {
      // 注销失败也回到登录页，避免继续展示可能过期的隐私数据。
    }
    if (clearSavedCredential) await _credentialVault.clear();
    _user = null;
    _loginForm = _loginForm.copyWith(password: '');
    _setPhase(AppPhase.login);
  }

  Future<void> setTelemetryEnabled(bool value) async {
    // 真实宿主会替换对应的启用/关闭 client；协调器同时在调用边界抑制
    // 事件，保证关闭后不会再产生新记录。
    _telemetryEnabled = value;
    if (!value) await _telemetry.flush();
    _notify();
  }

  Future<void> clearTelemetryQueue() async {
    await _telemetry.flush();
  }

  void clearError() {
    _clearError();
  }

  void _clearError() {
    if (_error == null) return;
    _error = null;
    _notify();
  }

  void _setPhase(AppPhase phase) {
    _phase = phase;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _recordAppOpen() async {
    if (!_telemetryEnabled) return;
    await _telemetry.track(TelemetryEvents.appStarted);
  }

  Future<void> _recordFeature(
    FeatureId feature, {
    bool success = false,
    bool empty = false,
    UiError? error,
    Duration? latency,
  }) async {
    if (!_telemetryEnabled) return;
    final event = error == null
        ? TelemetryEvents.featureLoaded
        : TelemetryEvents.featureFailed;
    final result = success
        ? 'success'
        : empty
        ? 'empty'
        : 'failure';
    await _telemetry.track(
      event,
      properties: <String, Object?>{
        'feature': feature.wireName,
        'result': result,
        if (error != null) 'error_code': error.code.wireName,
        if (error != null) 'retryable': error.retryable,
        if (latency != null) 'source': _latencyBucket(latency),
      },
    );
  }

  String _latencyBucket(Duration latency) {
    if (latency < const Duration(milliseconds: 500)) return 'lt_500ms';
    if (latency < const Duration(seconds: 2)) return '500ms_2s';
    if (latency < const Duration(seconds: 5)) return '2s_5s';
    return 'gte_5s';
  }

  @override
  void dispose() {
    _disposed = true;
    if (_backend case final BackendLifecycle lifecycle) {
      unawaited(lifecycle.dispose().catchError((_) {}));
    }
    super.dispose();
  }
}

/// 将 Core 稳定错误代码映射为不泄露上游细节的中文提示。
class UbaaErrorMapper {
  const UbaaErrorMapper._();

  static UiError fromCode(UbaaErrorCode code) => switch (code) {
    UbaaErrorCode.invalidInput => const UiError(
      code: UbaaErrorCode.invalidInput,
      title: '输入有误',
      message: '请检查学号、密码和其他必填内容。',
    ),
    UbaaErrorCode.authenticationRequired => const UiError(
      code: UbaaErrorCode.authenticationRequired,
      title: '登录已失效',
      message: '请重新登录后再试。',
      actionLabel: '重新登录',
    ),
    UbaaErrorCode.invalidCredentials => const UiError(
      code: UbaaErrorCode.invalidCredentials,
      title: '账号或密码不正确',
      message: '请确认学号和密码后重试。',
    ),
    UbaaErrorCode.passwordRiskConfirmationFailed => const UiError(
      code: UbaaErrorCode.passwordRiskConfirmationFailed,
      title: '需要额外确认',
      message: '学校登录需要额外安全确认，暂时无法完成。',
    ),
    UbaaErrorCode.permissionDenied => const UiError(
      code: UbaaErrorCode.permissionDenied,
      title: '暂无权限',
      message: '当前账号没有使用此功能的权限。',
    ),
    UbaaErrorCode.networkError => const UiError(
      code: UbaaErrorCode.networkError,
      title: '网络不可用',
      message: '请检查校园网或 VPN 连接后重试。',
      actionLabel: '重试',
      retryable: true,
    ),
    UbaaErrorCode.timeout => const UiError(
      code: UbaaErrorCode.timeout,
      title: '请求超时',
      message: '网络响应较慢，请稍后重试。',
      actionLabel: '重试',
      retryable: true,
    ),
    UbaaErrorCode.upstreamUnavailable => const UiError(
      code: UbaaErrorCode.upstreamUnavailable,
      title: '学校服务暂时不可用',
      message: '请稍后重试；其他功能可能仍然可以使用。',
      actionLabel: '重试',
      retryable: true,
    ),
    UbaaErrorCode.upstreamChanged || UbaaErrorCode.parseError => const UiError(
      code: UbaaErrorCode.upstreamChanged,
      title: '学校系统发生变化',
      message: '暂时无法读取此功能，请稍后再试。',
      actionLabel: '重试',
      retryable: true,
    ),
    UbaaErrorCode.internalError => const UiError(
      code: UbaaErrorCode.internalError,
      title: '应用内部错误',
      message: '请重试；如果问题持续，请反馈错误编号。',
      actionLabel: '重试',
      retryable: true,
    ),
    UbaaErrorCode.unsupported => const UiError(
      code: UbaaErrorCode.unsupported,
      title: '暂不支持',
      message: '当前平台或版本暂不支持此功能。',
    ),
    UbaaErrorCode.confirmationRequired => const UiError(
      code: UbaaErrorCode.confirmationRequired,
      title: '需要确认',
      message: '请先查看并确认本次操作的目标与影响。',
    ),
    UbaaErrorCode.intentExpired => const UiError(
      code: UbaaErrorCode.intentExpired,
      title: '确认已过期',
      message: '操作确认已过期，请重新准备。',
      actionLabel: '重新准备',
    ),
    UbaaErrorCode.operationConflict => const UiError(
      code: UbaaErrorCode.operationConflict,
      title: '操作状态已变化',
      message: '路线或会话已变化，请重新准备操作。',
      actionLabel: '重新准备',
    ),
    UbaaErrorCode.outcomeUnknown => const UiError(
      code: UbaaErrorCode.outcomeUnknown,
      title: '结果待核对',
      message: '操作结果暂时无法确认，请先刷新相关状态，勿重复提交。',
      actionLabel: '刷新状态',
      retryable: true,
    ),
  };
}
