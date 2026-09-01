import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

import 'backend.dart';

/// 基于 FRB opaque client 的生产后端。
///
/// 该适配器只负责把 bridge 的 typed 结果投影到应用层；请求 URL、Cookie、
/// Session 和路线选择仍由 Rust Core 管理。测试可以继续显式注入 [DemoBackend]，
/// 生产宿主不得把 Demo 作为默认实现。
class BridgeBackend implements UbaaBackend, BackendLifecycle {
  BridgeBackend(this.client);

  /// 从平台已经解析好的应用私有目录打开 Core。
  factory BridgeBackend.open(String configDirectory) =>
      BridgeBackend(BridgeClient.open(configDir: configDirectory));

  final BridgeClient client;

  @override
  Future<AuthStatus> authStatus() async {
    try {
      final outcome = await client.authStatus();
      return outcome.readiness == BridgeLoginReadiness.noneReady
          ? AuthStatus.signedOut
          : AuthStatus.signedIn;
    } on BridgeError catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<UserSummary?> userInfo() async {
    try {
      final result = await client.userInfo();
      final profile = result.data;
      final username = profile.username?.trim();
      if (username == null || username.isEmpty) return null;
      return UserSummary(
        username: username,
        displayName: _nonBlank(profile.name),
      );
    } on BridgeError catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {
    try {
      await client.setDefaultRoutePolicy(policy: _toBridgePolicy(policy));
      await client.prepareLogin();
    } on BridgeError catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<void> login(LoginInput input) async {
    try {
      await client.setDefaultRoutePolicy(
        policy: _toBridgePolicy(input.routePolicy),
      );
      final outcome = await client.login(
        username: input.username.trim(),
        password: input.password,
      );
      if (outcome.readiness == BridgeLoginReadiness.noneReady) {
        final failed = outcome.routes
            .map((route) => route.error)
            .whereType<BridgeSafeError>()
            .firstOrNull;
        throw BackendException(_errorCode(failed?.code));
      }
    } on BridgeError catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<void> logout() async {
    try {
      await client.logout();
    } on BridgeError catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    try {
      final today = _dateOnly(DateTime.now());
      switch (feature) {
        case FeatureId.schedule:
          final result = await client.scheduleToday();
          return _countResult(result.data.length, '今日课程');
        case FeatureId.exam:
          final term = await _selectedTerm();
          if (term == null) return const FeatureResult.empty();
          final result = await client.examArrangement(term: term);
          return _countResult(
            result.data.arranged.length + result.data.notArranged.length,
            '考试安排',
          );
        case FeatureId.grades:
          final term = await _selectedTerm();
          if (term == null) return const FeatureResult.empty();
          final result = await client.grades(term: term);
          return _countResult(result.data.grades.length, '门课程成绩');
        case FeatureId.bykc:
          final result = await client.bykcCourses(page: 0, size: 20, all: true);
          return _countResult(result.data.content.length, '门博雅课程');
        case FeatureId.classroom:
          final result = await client.classroomSearch(campus: 1, date: today);
          final rooms = result.data.floors.fold<int>(
            0,
            (total, floor) => total + floor.rooms.length,
          );
          return _countResult(rooms, '间可用教室');
        case FeatureId.spoc:
          final result = await client.spocAssignments();
          return _countResult(result.data.assignments.length, '项 SPOC 作业');
        case FeatureId.judge:
          final result = await client.judgeAssignments(includeExpired: false);
          return _countResult(result.data.length, '项希冀作业');
        case FeatureId.libbook:
          final result = await client.libbookLibraries(day: today);
          return _countResult(result.data.length, '所图书馆');
      }
    } on BridgeError catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> dispose() => client.dispose();

  Future<String?> _selectedTerm() async {
    final result = await client.scheduleTerms();
    for (final term in result.data) {
      if (term.selected && term.itemCode.trim().isNotEmpty)
        return term.itemCode;
    }
    for (final term in result.data) {
      if (term.itemCode.trim().isNotEmpty) return term.itemCode;
    }
    return null;
  }

  static FeatureResult _countResult(int count, String unit) => count == 0
      ? const FeatureResult.empty()
      : FeatureResult.success(summary: '$count$unit');

  static String _dateOnly(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  static BridgeRoutePolicy _toBridgePolicy(RoutePolicy policy) =>
      switch (policy) {
        RoutePolicy.auto => BridgeRoutePolicy.auto,
        RoutePolicy.direct => BridgeRoutePolicy.direct,
        RoutePolicy.webvpn => BridgeRoutePolicy.webVpn,
      };

  static String? _nonBlank(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static BackendException _mapError(BridgeError error) =>
      BackendException(_errorCode(error.code.name), detail: _safeDetail(error));

  static UbaaErrorCode _errorCode(String? code) => switch (code) {
    'invalidInput' || 'invalid_input' => UbaaErrorCode.invalidInput,
    'authenticationRequired' ||
    'authentication_required' => UbaaErrorCode.authenticationRequired,
    'invalidCredentials' ||
    'invalid_credentials' => UbaaErrorCode.invalidCredentials,
    'passwordRiskConfirmationFailed' || 'password_risk_confirmation_failed' =>
      UbaaErrorCode.passwordRiskConfirmationFailed,
    'permissionDenied' || 'permission_denied' => UbaaErrorCode.permissionDenied,
    'networkError' || 'network_error' => UbaaErrorCode.networkError,
    'timeout' => UbaaErrorCode.timeout,
    'upstreamUnavailable' ||
    'upstream_unavailable' => UbaaErrorCode.upstreamUnavailable,
    'upstreamChanged' || 'upstream_changed' => UbaaErrorCode.upstreamChanged,
    'parseError' || 'parse_error' => UbaaErrorCode.parseError,
    _ => UbaaErrorCode.internalError,
  };

  static String? _safeDetail(BridgeError error) {
    final value = error.message.trim();
    if (value.isEmpty || value.length > 160) return null;
    if (value.contains(
      RegExp(r'(?i)(password|cookie|token|authorization|https?://)'),
    )) {
      return null;
    }
    return value;
  }
}

/// 创建生产后端；任何初始化失败都保持明确的不可用状态，不回退到 Demo。
UbaaBackend createProductionBackend() {
  try {
    return BridgeBackend.open(defaultConfigDirectory());
  } on Object {
    return const UnavailableBackend();
  }
}

extension on Iterable<BridgeSafeError?> {
  BridgeSafeError? get firstOrNull {
    for (final value in this) {
      if (value != null) return value;
    }
    return null;
  }
}
