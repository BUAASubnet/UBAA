import 'package:ubaa_domain/ubaa_domain.dart';

import '../contracts/backend.dart';

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
