import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

import '../contracts/backend.dart';
import '../contracts/lifecycle.dart';
import '../contracts/query.dart';
import '../contracts/routing.dart';
import '../contracts/write.dart';
import '../write/cgyy_validation.dart';
import '../write/coordinator.dart';
import '../write/receipt_verifier.dart';
import '../write/ygdk_validation.dart';
import 'error_mapper.dart';

part 'app_controller/cgyy_readback.dart';
part 'app_controller/evaluation_readback.dart';
part 'app_controller/refresh.dart';
part 'app_controller/write_lifecycle.dart';
part 'app_controller/ygdk_readback.dart';

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
    BackendFactory? backendFactory,
    CredentialVault? credentialVault,
    TelemetryClient? telemetry,
  }) : _backend = backend,
       _backendFactory = backendFactory,
       _credentialVault = credentialVault ?? const NoopCredentialVault(),
       _telemetry = telemetry ?? const NoopTelemetryClient(),
       _telemetryEnabled = (telemetry ?? const NoopTelemetryClient()).enabled,
       _snapshots = {
         for (final feature in FeatureId.values)
           feature: FeatureSnapshot(feature: feature),
       } {
    _writeCoordinator = _createWriteCoordinator(backend);
    _writeCoordinator.addListener(_notify);
  }

  UbaaBackend _backend;
  final BackendFactory? _backendFactory;
  final CredentialVault _credentialVault;
  final TelemetryClient _telemetry;
  final Map<FeatureId, FeatureSnapshot> _snapshots;
  late WriteCoordinator _writeCoordinator;
  int _writeTransitions = 0;

  AppPhase _phase = AppPhase.splash;
  LoginFormState _loginForm = const LoginFormState();
  UserSummary? _user;
  UiError? _error;
  bool _disposed = false;
  bool _initialized = false;
  final Map<FeatureId, int> _featureRefreshGenerations = <FeatureId, int>{
    for (final feature in FeatureId.values) feature: 0,
  };
  int _lifecycleEpoch = 0;
  int _ygdkGeneration = 0;
  bool _telemetryEnabled;
  YgdkReadbackState _ygdkReadbackState = const YgdkReadbackState.empty();
  List<ConnectionMode> _activeRoutes = const <ConnectionMode>[];
  bool _rebuildingBackend = false;

  /// Expando 按实例身份关联释放 Future，且不会因去重表阻止已释放
  /// backend 被回收。
  final Expando<Future<void>> _backendDisposals = Expando<Future<void>>();

  AppPhase get phase => _phase;
  LoginFormState get loginForm => _loginForm;
  UserSummary? get user => _user;
  UiError? get error => _error;
  bool get telemetryEnabled => _telemetryEnabled;
  bool get credentialPersistenceAvailable => _credentialVault.isAvailable;
  List<ConnectionMode> get activeRoutes =>
      List<ConnectionMode>.unmodifiable(_activeRoutes);
  bool get isRebuildingBackend => _rebuildingBackend;
  Map<FeatureId, FeatureSnapshot> get snapshots =>
      Map<FeatureId, FeatureSnapshot>.unmodifiable(_snapshots);
  YgdkReadbackState get ygdkReadbackState => _ygdkReadbackState;
  WriteCoordinator get writeCoordinator => _writeCoordinator;

  /// backend 必须同时提供 typed 写入与原路线回读，宿主才可暴露
  /// 阳光打卡提交入口。平台照片能力仍由宿主另行检查。
  bool get hasYgdkSubmissionBackendCapabilities =>
      _backend is YgdkWriteBackend && _backend is YgdkSubmissionReadbackBackend;

  /// backend 必须同时提供 typed 写入与调用方固定路线回读，
  /// 宿主才能暴露评教提交入口。
  bool get hasEvaluationSubmissionBackendCapabilities =>
      _backend is EvaluationWriteBackend &&
      _backend is EvaluationSubmissionReadbackBackend;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _beginWriteTransition();
    _setPhase(AppPhase.checkingSession);
    try {
      if (_backend case final RouteSettingsBackend routeBackend) {
        final settings = await routeBackend.routeSettings();
        if (_disposed) return;
        _applyRouteSettings(settings);
      }
      final status = await _backend.authStatus();
      if (_disposed) return;
      if (status == AuthStatus.signedIn) {
        _user = await _backend.userInfo();
        if (_disposed) return;
        if (_user != null) {
          _setPhase(AppPhase.home);
          await _recordAppOpen();
          unawaited(refreshHome());
          return;
        }
      }
      final saved = await _credentialVault.read();
      if (_disposed) return;
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
    } finally {
      _endWriteTransition();
    }
  }

  /// 在 Dart isolate 或宿主生命周期重建后替换 opaque backend。
  ///
  /// 新 backend 成功创建后才 dispose 旧 backend；随后重新读取 Core 的路线和
  ///认证状态。没有提供工厂、正在登录/重建或 controller 已销毁时返回 `false`，
  ///不伪造恢复成功。
  Future<bool> rebuildBackend() async {
    final factory = _backendFactory;
    if (factory == null || _disposed || _rebuildingBackend) return false;
    // 初始化正在读取旧 backend 的认证/路线状态时，生命周期重建会与旧
    // handle 竞争并可能把结果写入新实例；等待初始化完成后再由下一次
    // resumed 事件触发重建。
    if (_phase == AppPhase.loggingIn || _phase == AppPhase.checkingSession) {
      return false;
    }
    _rebuildingBackend = true;
    _beginWriteTransition();
    _setPhase(AppPhase.checkingSession);
    try {
      final replacement = factory();
      if (identical(replacement, _backend)) {
        _error = UbaaErrorMapper.fromCode(UbaaErrorCode.internalError);
        _setPhase(AppPhase.login);
        return false;
      }
      final previous = _backend;
      try {
        await _disposeBackendOnce(previous);
      } on Object {
        // 新实例已经创建；旧实例清理失败不能让新实例继续持有旧状态。
      }
      if (_disposed) {
        try {
          await _disposeBackendOnce(replacement);
        } on Object {
          // controller 已销毁时尽力释放新实例，不能向 UI 抛出异常。
        }
        return false;
      }
      _backend = replacement;
      _replaceWriteCoordinator(replacement);
      _initialized = false;
      _user = null;
      _activeRoutes = const <ConnectionMode>[];
      _resetFeatureSnapshots();
      await initialize();
      return true;
    } on BackendException catch (exception) {
      _error = UbaaErrorMapper.fromCode(exception.code);
      _setPhase(AppPhase.login);
      return false;
    } on Object {
      _error = UbaaErrorMapper.fromCode(UbaaErrorCode.internalError);
      _setPhase(AppPhase.login);
      return false;
    } finally {
      _endWriteTransition();
      _rebuildingBackend = false;
      _notify();
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
    if (_disposed || _phase == AppPhase.loggingIn) return;
    final previousPolicy = _loginForm.routePolicy;
    if (previousPolicy == value) return;
    _beginWriteTransition();
    _clearError();
    try {
      await _backend.prepareLogin(value);
      if (_disposed) return;
      BackendRouteSettings? settings;
      if (_backend case final RouteSettingsBackend routeBackend) {
        settings = await routeBackend.routeSettings();
        if (_disposed) return;
      }
      if (settings case final routeSettings?) {
        _applyRouteSettings(routeSettings);
      } else {
        _loginForm = _loginForm.copyWith(routePolicy: value);
      }
      if (_phase == AppPhase.home &&
          settings != null &&
          !_routePolicyHasSession(value, settings.activeRoutes)) {
        // 切换到尚未认证的固定路线时，不能继续展示旧用户数据；保留用户名和
        // 用户主动保存的凭据，回到登录页完成目标路线认证。
        _user = null;
        _resetFeatureSnapshots();
        _setPhase(AppPhase.login);
      }
    } on BackendException catch (exception) {
      if (_disposed) return;
      _loginForm = _loginForm.copyWith(routePolicy: previousPolicy);
      _error = UbaaErrorMapper.fromCode(exception.code);
    } catch (_) {
      if (_disposed) return;
      _loginForm = _loginForm.copyWith(routePolicy: previousPolicy);
      _error = UbaaErrorMapper.fromCode(UbaaErrorCode.internalError);
    } finally {
      _endWriteTransition();
    }
    _notify();
  }

  Future<void> submitLogin() async {
    if (_disposed || _phase == AppPhase.loggingIn) return;
    final username = _loginForm.username.trim();
    if (username.isEmpty || _loginForm.password.isEmpty) {
      _error = UbaaErrorMapper.fromCode(UbaaErrorCode.invalidInput);
      _notify();
      return;
    }
    _beginWriteTransition();
    _error = null;
    _activeRoutes = const <ConnectionMode>[];
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
      if (_disposed) return;
      await _refreshRouteSettings();
      if (_disposed) return;
      _user = await _backend.userInfo() ?? UserSummary(username: username);
      if (_disposed) return;
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
      if (_disposed) return;
      _setPhase(AppPhase.home);
      await _recordAppOpen();
      unawaited(refreshHome());
    } on BackendException catch (exception) {
      if (exception.code == UbaaErrorCode.invalidCredentials) {
        await _credentialVault.clear();
      }
      if (_disposed) return;
      _error = UbaaErrorMapper.fromCode(exception.code);
      _setPhase(AppPhase.login);
    } catch (_) {
      if (_disposed) return;
      _error = UbaaErrorMapper.fromCode(UbaaErrorCode.internalError);
      _setPhase(AppPhase.login);
    } finally {
      _endWriteTransition();
    }
  }

  Future<void> refreshHome({Iterable<FeatureId>? only}) =>
      _refreshHome(only: only);

  Future<void> retryFeature(FeatureId feature) =>
      refreshHome(only: <FeatureId>[feature]);

  /// 对支持 [FeatureQueryBackend] 的生产实现执行单领域筛选读取。
  Future<void> refreshFeatureQuery(FeatureId feature, FeatureQuery query) =>
      _refreshFeatureQuery(feature, query);

  /// 准备博雅选课/退选的 typed 一次性意图；准备本身不提交写请求。
  Future<WriteIntent> prepareBykcWrite(
    WriteOperation operation,
    int courseId,
  ) async {
    final backend = _backend;
    if (backend is! BykcWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    final writer = backend as BykcWriteBackend;
    if (courseId <= 0) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    return switch (operation) {
      WriteOperation.bykcSelectCourse => writer.prepareBykcSelectCourse(
        courseId: courseId,
      ),
      WriteOperation.bykcDeselectCourse => writer.prepareBykcDeselectCourse(
        courseId: courseId,
      ),
      _ => throw const BackendException(UbaaErrorCode.invalidInput),
    };
  }

  /// 准备博雅签到/签退；仅接受冻结合同的 signType 1/2 和完整有效坐标对。
  Future<WriteIntent> prepareBykcSignWrite(
    int courseId,
    int signType, {
    double? lat,
    double? lng,
  }) async {
    final backend = _backend;
    if (backend is! BykcWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    final hasNoCoordinates = lat == null && lng == null;
    final hasValidCoordinates =
        lat != null &&
        lng != null &&
        lat.isFinite &&
        lng.isFinite &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180;
    if (courseId <= 0 ||
        (signType != 1 && signType != 2) ||
        (!hasNoCoordinates && !hasValidCoordinates)) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    final writer = backend as BykcWriteBackend;
    return writer.prepareBykcSignCourse(
      courseId: courseId,
      lat: lat,
      lng: lng,
      signType: signType,
    );
  }

  /// 准备课堂签到的 typed 一次性意图；目标和资格必须来自读取白名单。
  Future<WriteIntent> prepareSigninWrite(SigninPerformAction action) async {
    final backend = _backend;
    if (backend is! SigninWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    final writer = backend as SigninWriteBackend;
    final normalized = action.scheduleId.trim();
    if (normalized.isEmpty || action.eligibility != ActionEligibility.allowed) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    return writer.prepareSigninPerform(courseId: normalized);
  }

  /// 准备场馆取消的一次性意图；只接受 Core 给出的 typed 目标。
  Future<WriteIntent> prepareCgyyCancelWrite(CgyyCancelAction action) async {
    final backend = _backend;
    if (backend is! CancellationWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    if (!action.hasCanonicalTarget) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    return (backend as CancellationWriteBackend).prepareCgyyCancelOrder(
      id: action.orderId,
    );
  }

  /// 准备图书馆取消意图；目标、资格与分页上下文全部来自 Core typed 读取。
  Future<WriteIntent> prepareLibbookCancelWrite(
    LibbookCancelAction action,
  ) async {
    final backend = _backend;
    if (backend is! CancellationWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    final bookingId = action.bookingId.trim();
    if (action.eligibility != ActionEligibility.allowed ||
        bookingId.isEmpty ||
        action.page <= 0 ||
        action.limit <= 0) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    final writer = backend as CancellationWriteBackend;
    return writer.prepareLibbookCancelBooking(
      id: bookingId,
      page: action.page,
      limit: action.limit,
    );
  }

  /// 准备图书馆预约的 typed 一次性意图；只接受读取白名单中的完整目标。
  Future<WriteIntent> prepareLibbookReserveWrite(
    LibbookReserveAction action,
  ) async {
    final backend = _backend;
    if (backend is! LibbookWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    final values = <String>[
      action.areaId,
      action.seatId,
      action.day,
      action.segment,
      action.startTime,
      action.endTime,
    ].map((value) => value.trim()).toList(growable: false);
    if (action.eligibility != ActionEligibility.allowed ||
        values.any((value) => value.isEmpty)) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    final writer = backend as LibbookWriteBackend;
    return writer.prepareLibbookReserve(
      areaId: values[0],
      seatId: values[1],
      day: values[2],
      segment: values[3],
      startTime: values[4],
      endTime: values[5],
    );
  }

  /// 准备阳光打卡写意图；照片字节只复制到本次内存请求，不落盘或写日志。
  Future<WriteIntent> prepareYgdkWrite(YgdkSubmitInput input) async {
    final backend = _backend;
    if (backend is! YgdkWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    return (backend as YgdkWriteBackend).prepareYgdkSubmit(
      validateYgdkSubmitInput(input),
    );
  }

  /// 准备场馆预约写意图；只接受 Core 已核对的 typed actions。
  Future<WriteIntent> prepareCgyySubmitWrite(CgyySubmitInput input) async {
    final backend = _backend;
    if (backend is! CgyyWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    return (backend as CgyyWriteBackend).prepareCgyySubmitReservation(
      validateCgyySubmitInput(input),
    );
  }

  /// 准备教学评教写意图；仅接受读取 action 中的 typed 目标。
  Future<WriteIntent> prepareEvaluationWrite(
    List<EvaluationSubmitTarget> targets,
  ) async {
    final backend = _backend;
    if (backend is! EvaluationWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    final normalized = targets
        .map(_normalizeEvaluationTarget)
        .toList(growable: false);
    final uniqueKeys = normalized.map((target) => target.selectionKey).toSet();
    if (normalized.isEmpty ||
        normalized.any((target) => !target.hasRequiredIdentity) ||
        uniqueKeys.length != normalized.length) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    return (backend as EvaluationWriteBackend).prepareEvaluationSubmitCourses(
      normalized,
    );
  }

  /// 提交已确认的一次性意图；不接受任意请求正文，也不自动重试。
  Future<WriteCommitResult> commitWrite(String intentId) =>
      _commitWriteWithBackend(_backend, intentId);

  /// 释放尚未确认的一次性意图；该操作不提交任何上游写请求。
  Future<void> discardWriteIntent(String intentId) =>
      _discardWriteWithBackend(_backend, intentId);

  /// 写入成功后仅刷新关联只读领域，用于结果核对；不会重试写请求。
  Future<void> refreshAfterWrite(
    WriteOperation operation, [
    FeatureQuery? readbackQuery,
  ]) {
    if (operation == WriteOperation.libbookReserve ||
        operation == WriteOperation.libbookCancelBooking) {
      if (_backend is FeatureQueryBackend) {
        return refreshFeatureQuery(
          FeatureId.libbook,
          readbackQuery ??
              const FeatureQuery(view: FeatureQueryView.libbookBookings),
        );
      }
    }
    if (operation == WriteOperation.cgyySubmitReservation) {
      // 订单列表是场馆写入的唯一稳定核对入口；若后端不支持筛选查询，
      // 保留旧的领域刷新兼容路径，不伪造核对成功。
      if (_backend is FeatureQueryBackend) {
        return refreshFeatureQuery(
          FeatureId.cgyy,
          const FeatureQuery(view: FeatureQueryView.cgyyOrders),
        );
      }
    }
    if (operation == WriteOperation.cgyyCancelOrder) {
      // 场馆取消必须由 verifyCgyyCancellation 独占执行列表+详情双回读；
      // 此通用入口不做单列表降级，也不会触发写入重试。
      return Future<void>.value();
    }
    if (operation == WriteOperation.ygdkSubmit) {
      // 阳光打卡必须由 refreshYgdkAfterWrite 使用 intent 的原路线读取
      // 概览和首页记录；通用刷新不得降级为 Auto 路线。
      return Future<void>.value();
    }
    if (operation == WriteOperation.evaluationSubmitCourses) {
      // 评教必须使用 intent 原路线回读；通用刷新不得重新执行 Auto。
      return Future<void>.value();
    }
    final feature = switch (operation) {
      WriteOperation.bykcSelectCourse ||
      WriteOperation.bykcDeselectCourse ||
      WriteOperation.bykcSignCourse => FeatureId.bykc,
      WriteOperation.signinPerform => FeatureId.signin,
      WriteOperation.libbookReserve ||
      WriteOperation.libbookCancelBooking => FeatureId.libbook,
      WriteOperation.ygdkSubmit => FeatureId.ygdk,
      WriteOperation.cgyySubmitReservation ||
      WriteOperation.cgyyCancelOrder => FeatureId.cgyy,
      WriteOperation.evaluationSubmitCourses => throw StateError(
        '评教使用调用方固定路线回读',
      ),
    };
    return refreshHome(only: <FeatureId>[feature]);
  }

  /// 在场馆订单刷新完成后，仅按公开订单编号匹配提交收据。
  ///
  /// 该方法不发起额外请求，调用方必须先等待 [refreshAfterWrite]；读取失败、
  /// 空结果或不匹配均返回 `false`，绝不把写入结果升级为已核对。
  Future<bool> matchesCgyyReceipt(CgyyReservationReceipt receipt) async {
    if (receipt.orderId <= 0) return false;
    final snapshot = _snapshots[FeatureId.cgyy];
    if (snapshot == null || snapshot.status != FeatureLoadStatus.success) {
      return false;
    }
    final orderId = receipt.orderId.toString();
    return snapshot.details.any(
      (detail) => detail.fields.any(
        (field) => field.label == '订单编号' && field.value == orderId,
      ),
    );
  }

  /// 在 intent 的实际路线上执行场馆取消列表+详情双回读。
  Future<bool> verifyCgyyCancellation({
    required int orderId,
    required ConnectionMode expectedRoute,
  }) => _verifyCgyyCancellation(
    this,
    orderId: orderId,
    expectedRoute: expectedRoute,
  );

  /// 在 intent 的实际路线 best-effort 刷新阳光打卡概览与首页记录。
  ///
  /// 冻结来源没有提供记录与本次写入的严格关联规则，因此该方法不
  /// 接收收据也不返回核对结论，更不得将 OutcomeUnknown 升级为成功。
  Future<void> refreshYgdkAfterWrite({required ConnectionMode expectedRoute}) =>
      _refreshYgdkAfterWrite(this, expectedRoute: expectedRoute);

  /// 在 intent 的实际路线 best-effort 刷新评教课程。
  ///
  /// 该回读只更新 Evaluation 快照，不改写结果，也不会重试提交。
  Future<void> refreshEvaluationAfterWrite({
    required ConnectionMode expectedRoute,
  }) => _refreshEvaluationAfterWrite(this, expectedRoute: expectedRoute);

  Future<void> logout({bool clearSavedCredential = false}) async {
    if (_disposed) return;
    _beginWriteTransition();
    try {
      try {
        await _backend.logout();
      } on Object {
        // 注销失败也回到登录页，避免继续展示可能过期的隐私数据。
      }
      if (clearSavedCredential) await _credentialVault.clear();
      if (_disposed) return;
      _user = null;
      _activeRoutes = const <ConnectionMode>[];
      _loginForm = _loginForm.copyWith(password: '');
      _resetFeatureSnapshots();
      _setPhase(AppPhase.login);
    } finally {
      _endWriteTransition();
    }
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

  bool _routePolicyHasSession(
    RoutePolicy policy,
    List<ConnectionMode> activeRoutes,
  ) => switch (policy) {
    RoutePolicy.auto => activeRoutes.isNotEmpty,
    RoutePolicy.direct => activeRoutes.contains(ConnectionMode.direct),
    RoutePolicy.webvpn => activeRoutes.contains(ConnectionMode.webvpn),
  };

  void _resetFeatureSnapshots() {
    _lifecycleEpoch++;
    _ygdkGeneration++;
    _writeCoordinator.invalidate();
    _ygdkReadbackState = const YgdkReadbackState.empty();
    for (final feature in FeatureId.values) {
      _snapshots[feature] = FeatureSnapshot(feature: feature);
    }
  }

  void _applyRouteSettings(BackendRouteSettings settings) {
    _activeRoutes = List<ConnectionMode>.unmodifiable(settings.activeRoutes);
    _loginForm = _loginForm.copyWith(routePolicy: settings.defaultPolicy);
  }

  Future<void> _refreshRouteSettings() async {
    if (_backend case final RouteSettingsBackend routeBackend) {
      try {
        final settings = await routeBackend.routeSettings();
        if (_disposed) return;
        _applyRouteSettings(settings);
      } on Object {
        if (_disposed) return;
        // 登录已经成功时，路线状态读取失败不能把账号重新置为失败；清空
        // 不确定的活动槽位，后续读取仍由 Core 返回实际错误。
        _activeRoutes = const <ConnectionMode>[];
      }
    }
  }

  void _setPhase(AppPhase phase) {
    if (phase == AppPhase.login) {
      _lifecycleEpoch++;
      _ygdkGeneration++;
      _writeCoordinator.invalidate();
    }
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

  Future<void> _disposeBackendOnce(UbaaBackend backend) {
    final existing = _backendDisposals[backend];
    if (existing != null) return existing;
    if (backend is! BackendLifecycle) return Future<void>.value();
    final lifecycle = backend as BackendLifecycle;

    final completer = Completer<void>();
    _backendDisposals[backend] = completer.future;
    try {
      lifecycle.dispose().then<void>(
        (_) => completer.complete(),
        onError: (Object error, StackTrace stackTrace) {
          completer.completeError(error, stackTrace);
        },
      );
    } on Object catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
    return completer.future;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _lifecycleEpoch++;
    _ygdkGeneration++;
    _writeCoordinator.removeListener(_notify);
    _writeCoordinator.dispose();
    _ygdkReadbackState = const YgdkReadbackState.empty();
    _snapshots[FeatureId.ygdk] = const FeatureSnapshot(feature: FeatureId.ygdk);
    unawaited(_disposeBackendOnce(_backend).catchError((_) {}));
    super.dispose();
  }
}
