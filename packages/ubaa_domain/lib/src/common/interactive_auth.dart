import 'dart:typed_data';

import 'auth.dart';
import 'error.dart';
import 'route.dart';

/// 当前登录页面独占的像素引用，不序列化、不写缓存或诊断。
class CaptchaPixelFrame {
  CaptchaPixelFrame({
    required this.width,
    required this.height,
    required Uint8List rgba,
  }) : _rgba = rgba;

  final int width;
  final int height;
  Uint8List? _rgba;

  Uint8List? get rgba => _rgba;
  bool get isReleased => _rgba == null;

  /// 释放本方引用；不声称擦除了 Dart、FFI 或图形系统的所有拷贝。
  void release() {
    _rgba = null;
  }

  @override
  String toString() => 'CaptchaPixelFrame([已隐藏])';
}

enum LoginRouteVerificationStatus { prepared, captchaRequired, ready, failed }

/// 答案与图像只属于专用验证状态，不属于 LoginInput 或 AppSnapshot。
class LoginRouteVerification {
  const LoginRouteVerification({
    required this.route,
    required this.status,
    this.revision = 0,
    this.frame,
    this.validFor = Duration.zero,
    this.answer = '',
    this.error,
    this.isRefreshing = false,
  });

  final ConnectionMode route;
  final LoginRouteVerificationStatus status;
  final int revision;
  final CaptchaPixelFrame? frame;
  final Duration validFor;
  final String answer;
  final UiError? error;
  final bool isRefreshing;

  bool get hasUsableFrame => frame != null && !frame!.isReleased;

  LoginRouteVerification withAnswer(String value) => LoginRouteVerification(
    route: route,
    status: status,
    revision: revision,
    frame: frame,
    validFor: validFor,
    answer: value,
    error: error,
    isRefreshing: isRefreshing,
  );

  LoginRouteVerification cleared({UiError? error, bool refreshing = false}) =>
      LoginRouteVerification(
        route: route,
        status: LoginRouteVerificationStatus.captchaRequired,
        revision: revision,
        error: error,
        isRefreshing: refreshing,
      );

  @override
  String toString() => 'LoginRouteVerification($route, $status)';
}

class LoginVerificationState {
  LoginVerificationState({
    required Iterable<LoginRouteVerification> routes,
    this.profile,
  }) : routes = List<LoginRouteVerification>.unmodifiable(routes);

  final List<LoginRouteVerification> routes;
  final UserSummary? profile;

  List<ConnectionMode> get readyRoutes => <ConnectionMode>[
    for (final route in routes)
      if (route.status == LoginRouteVerificationStatus.ready) route.route,
  ];

  bool get hasCaptcha => routes.any(
    (route) => route.status == LoginRouteVerificationStatus.captchaRequired,
  );

  bool get canSubmit => routes.any(
    (route) =>
        route.status == LoginRouteVerificationStatus.prepared ||
        (route.status == LoginRouteVerificationStatus.captchaRequired &&
            route.hasUsableFrame &&
            route.answer.trim().isNotEmpty &&
            !route.isRefreshing),
  );

  LoginRouteVerification? forRoute(ConnectionMode value) {
    for (final route in routes) {
      if (route.route == value) return route;
    }
    return null;
  }

  void releaseFrames() {
    for (final route in routes) {
      route.frame?.release();
    }
  }

  @override
  String toString() => 'LoginVerificationState(路线数量: ${routes.length})';
}
