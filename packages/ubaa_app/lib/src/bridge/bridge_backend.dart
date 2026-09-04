import 'dart:async';
import 'dart:typed_data';

import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

import '../backend.dart';

part 'common.dart';
part 'read/academic.dart';
part 'read/assignments.dart';
part 'read/bykc.dart';
part 'read/cgyy.dart';
part 'read/evaluation.dart';
part 'read/libbook.dart';
part 'read/ygdk.dart';
part 'write/commit.dart';
part 'write/lifecycle.dart';
part 'write/prepare.dart';

const _supportedBridgeContractVersion = 2;

/// 基于 FRB opaque client 的生产后端。
///
/// 该适配器只负责把 bridge 的 typed 结果投影到应用层；请求 URL、Cookie、
/// Session 和路线选择仍由 Rust Core 管理。测试可以继续显式注入 [DemoBackend]，
/// 生产宿主不得把 Demo 作为默认实现。
class BridgeBackend
    implements
        UbaaBackend,
        FeatureQueryBackend,
        BykcWriteBackend,
        SigninWriteBackend,
        CancellationWriteBackend,
        LibbookWriteBackend,
        YgdkWriteBackend,
        CgyyWriteBackend,
        EvaluationWriteBackend,
        RouteSettingsBackend,
        BackendLifecycle {
  BridgeBackend(this.client) {
    final contractVersion = client.contractVersion();
    if (contractVersion != _supportedBridgeContractVersion) {
      _disposeIncompatibleBridgeClient(client);
      throw StateError('Bridge 合同版本不兼容。');
    }
  }

  /// 从平台已经解析好的应用私有目录打开 Core。
  factory BridgeBackend.open(String configDirectory) =>
      BridgeBackend(BridgeClient.open(configDir: configDirectory));

  final BridgeClient client;

  @override
  Future<AuthStatus> authStatus() => _authStatus(this);

  @override
  Future<UserSummary?> userInfo() => _userInfo(this);

  @override
  Future<void> prepareLogin(RoutePolicy policy) => _prepareLogin(this, policy);

  Future<BackendRouteSettings> setDefaultRoutePolicy(RoutePolicy policy) =>
      _setDefaultRoutePolicy(this, policy);

  @override
  Future<BackendRouteSettings> routeSettings() => _routeSettings(this);

  @override
  Future<void> login(LoginInput input) => _login(this, input);

  @override
  Future<void> logout() => _logout(this);

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) =>
      loadFeatureQuery(feature, const FeatureQuery());

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) => _loadFeatureQuery(this, feature, query);

  @override
  Future<void> dispose() => _dispose(this);

  @override
  Future<WriteIntent> prepareBykcSelectCourse({required int courseId}) async =>
      _prepareBykcSelectCourse(this, courseId: courseId);

  @override
  Future<WriteIntent> prepareBykcDeselectCourse({required int courseId}) =>
      _prepareBykcDeselectCourse(this, courseId: courseId);

  @override
  Future<WriteIntent> prepareBykcSignCourse({
    required int courseId,
    double? lat,
    double? lng,
    required int signType,
  }) => _prepareBykcSignCourse(
    this,
    courseId: courseId,
    lat: lat,
    lng: lng,
    signType: signType,
  );

  @override
  Future<WriteIntent> prepareSigninPerform({required String courseId}) =>
      _prepareSigninPerform(this, courseId: courseId);

  @override
  Future<WriteIntent> prepareLibbookReserve({
    required String areaId,
    required String seatId,
    required String day,
    required String segment,
    required String startTime,
    required String endTime,
  }) => _prepareLibbookReserve(
    this,
    areaId: areaId,
    seatId: seatId,
    day: day,
    segment: segment,
    startTime: startTime,
    endTime: endTime,
  );

  @override
  Future<WriteIntent> prepareLibbookCancelBooking({required String id}) =>
      _prepareLibbookCancelBooking(this, id: id);

  /// 准备阳光打卡。照片字节只在本次调用构造 typed DTO，不写入配置或日志。
  @override
  Future<WriteIntent> prepareYgdkSubmit(YgdkSubmitInput input) =>
      _prepareYgdkSubmit(this, input);

  /// 准备场馆预约；selection 只包含经过 UI 选择的 ID，不接受 raw JSON。
  @override
  Future<WriteIntent> prepareCgyySubmitReservation(CgyySubmitInput input) =>
      _prepareCgyySubmitReservation(this, input);

  @override
  Future<WriteIntent> prepareCgyyCancelOrder({required int id}) =>
      _prepareCgyyCancelOrder(this, id: id);

  /// 评教只接收 bridge 白名单课程 DTO，并在 commit 后由页面重新读取进度。
  @override
  Future<WriteIntent> prepareEvaluationSubmitCourses(
    List<EvaluationCourseInput> courses,
  ) => _prepareEvaluationSubmitCourses(this, courses);

  @override
  Future<WriteCommitResult> commitWrite(String intentId) =>
      _commitWrite(this, intentId);

  @override
  Future<void> discardWriteIntent(String intentId) =>
      _discardWriteIntent(this, intentId);
}

void _disposeIncompatibleBridgeClient(BridgeClient client) {
  try {
    unawaited(client.dispose().catchError((Object _) {}));
  } on Object {
    // 合同已不兼容，释放失败也不能继续启动该 backend。
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
