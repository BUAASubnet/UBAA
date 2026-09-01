import 'package:ubaa_domain/ubaa_domain.dart';

/// Core 当前认证状态的最小表示。
enum AuthStatus { signedOut, signedIn }

/// Bridge/Core 错误的安全边界。`detail` 只能记录脱敏诊断，不得传给 UI。
class BackendException implements Exception {
  const BackendException(this.code, {this.detail});

  final UbaaErrorCode code;
  final String? detail;

  @override
  String toString() => 'BackendException(${code.wireName})';
}

/// Flutter 宿主唯一需要依赖的业务接口。
///
/// 生产实现由 FRB 绑定适配；URL、Cookie、路由探测和会话文件均留在 Rust
/// Core 内部，Dart 层不拼接请求。
abstract interface class UbaaBackend {
  Future<AuthStatus> authStatus();

  Future<UserSummary?> userInfo();

  Future<void> prepareLogin(RoutePolicy policy);

  Future<void> login(LoginInput input);

  Future<void> logout();

  /// 首发只读功能统一返回摘要。详情 DTO 接入时保持此接口的错误语义。
  Future<FeatureResult> loadFeature(FeatureId feature);
}

/// Core 当前保存的全局路线策略和已认证路线槽位。
///
/// 该投影不包含 Session 内容；调用方只能据此决定是否需要重新登录目标路线。
class BackendRouteSettings {
  const BackendRouteSettings({
    required this.defaultPolicy,
    required this.activeRoutes,
  });

  final RoutePolicy defaultPolicy;
  final List<ConnectionMode> activeRoutes;
}

/// 支持读取全局路线策略和已认证路线槽位的生产 backend 能力。
abstract interface class RouteSettingsBackend {
  Future<BackendRouteSettings> routeSettings();
}

/// 支持领域筛选/服务端分页的可选 backend 能力。
///
/// 保留与 [UbaaBackend] 分离的接口，确保旧版 fake backend 不必伪造查询能力；
/// 生产 bridge backend 实现该接口并将参数 typed 传入 Core。
abstract interface class FeatureQueryBackend {
  Future<FeatureResult> loadFeatureQuery(FeatureId feature, FeatureQuery query);
}

/// 可由应用生命周期关闭的后端资源。
abstract interface class BackendLifecycle {
  Future<void> dispose();
}

/// 生产配置暂不可用时的安全后端。
///
/// 生产入口不能使用 [DemoBackend] 伪造登录或业务数据；路径、动态库或
/// 平台能力尚未准备好时，所有操作明确失败并由 UI 映射为可行动错误。
class UnavailableBackend implements UbaaBackend, BackendLifecycle {
  const UnavailableBackend();

  @override
  Future<AuthStatus> authStatus() => _unsupported<AuthStatus>();

  @override
  Future<UserSummary?> userInfo() => _unsupported<UserSummary?>();

  @override
  Future<void> prepareLogin(RoutePolicy policy) => _unsupported<void>();

  @override
  Future<void> login(LoginInput input) => _unsupported<void>();

  @override
  Future<void> logout() => _unsupported<void>();

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) =>
      _unsupported<FeatureResult>();

  @override
  Future<void> dispose() async {}

  Future<T> _unsupported<T>() =>
      Future<T>.error(const BackendException(UbaaErrorCode.unsupported));
}

/// UI 开发和 widget 测试使用的脱敏后端，不访问网络或真实账号。
class DemoBackend implements UbaaBackend {
  DemoBackend({this.loginDelay = const Duration(milliseconds: 350)});

  final Duration loginDelay;
  bool _signedIn = false;
  UserSummary? _user;

  @override
  Future<AuthStatus> authStatus() async =>
      _signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;

  @override
  Future<UserSummary?> userInfo() async => _user;

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {
    await Future<void>.delayed(loginDelay);
    if (input.username.trim().isEmpty || input.password.isEmpty) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    // 仅用于本地预览：Demo 账号可用任意非空密码。
    _signedIn = true;
    _user = UserSummary(
      username: input.username.trim(),
      displayName: 'BUAA 同学',
    );
  }

  @override
  Future<void> logout() async {
    _signedIn = false;
    _user = null;
  }

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    if (!_signedIn) {
      throw const BackendException(UbaaErrorCode.authenticationRequired);
    }
    await Future<void>.delayed(const Duration(milliseconds: 180));
    final summary = switch (feature) {
      FeatureId.schedule => '今天有 3 节课程',
      FeatureId.exam => '暂无近期考试',
      FeatureId.grades => '已加载本学期成绩',
      FeatureId.bykc => '已选 2 门博雅课程',
      FeatureId.classroom => '可用教室 18 间',
      FeatureId.spoc => '待完成作业 2 项',
      FeatureId.judge => '待提交作业 1 项',
      FeatureId.libbook => '座位服务已就绪',
      FeatureId.signin => '今日签到 1 门课程',
      FeatureId.cgyy => '可预约场馆 2 个',
      FeatureId.ygdk => '本周打卡进度已加载',
      FeatureId.evaluation => '待评课程 3 门',
    };
    return FeatureResult.success(
      summary: summary,
      details: <FeatureDetail>[
        FeatureDetail(title: feature.title, subtitle: summary),
      ],
    );
  }
}
