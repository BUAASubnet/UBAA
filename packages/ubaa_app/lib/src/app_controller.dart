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
       };

  UbaaBackend _backend;
  final BackendFactory? _backendFactory;
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
  List<ConnectionMode> _activeRoutes = const <ConnectionMode>[];
  bool _rebuildingBackend = false;

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

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
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
    _refreshGeneration++;
    _setPhase(AppPhase.checkingSession);
    try {
      final replacement = factory();
      if (identical(replacement, _backend)) {
        _error = UbaaErrorMapper.fromCode(UbaaErrorCode.internalError);
        _setPhase(AppPhase.login);
        return false;
      }
      final previous = _backend;
      if (previous case final BackendLifecycle lifecycle) {
        try {
          await lifecycle.dispose();
        } on Object {
          // 新实例已经创建；旧实例清理失败不能让新实例继续持有旧状态。
        }
      }
      if (_disposed) {
        if (replacement case final BackendLifecycle lifecycle) {
          try {
            await lifecycle.dispose();
          } on Object {
            // controller 已销毁时尽力释放新实例，不能向 UI 抛出异常。
          }
        }
        return false;
      }
      _backend = replacement;
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
    if (_phase == AppPhase.loggingIn) return;
    final previousPolicy = _loginForm.routePolicy;
    if (previousPolicy == value) return;
    _clearError();
    try {
      await _backend.prepareLogin(value);
      BackendRouteSettings? settings;
      if (_backend case final RouteSettingsBackend routeBackend) {
        settings = await routeBackend.routeSettings();
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
      _loginForm = _loginForm.copyWith(routePolicy: previousPolicy);
      _error = UbaaErrorMapper.fromCode(exception.code);
    } catch (_) {
      _loginForm = _loginForm.copyWith(routePolicy: previousPolicy);
      _error = UbaaErrorMapper.fromCode(UbaaErrorCode.internalError);
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
    }
  }

  Future<void> refreshHome({Iterable<FeatureId>? only}) async {
    if (_disposed) return;
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
    if (_disposed) return;
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

  /// 准备博雅签到/签退；仅接受冻结合同的 signType 1/2，不伪造位置。
  Future<WriteIntent> prepareBykcSignWrite(int courseId, int signType) async {
    final backend = _backend;
    if (backend is! BykcWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    if (courseId <= 0 || (signType != 1 && signType != 2)) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    final writer = backend as BykcWriteBackend;
    return writer.prepareBykcSignCourse(courseId: courseId, signType: signType);
  }

  /// 准备课堂签到的 typed 一次性意图；课程编号必须来自读取白名单。
  Future<WriteIntent> prepareSigninWrite(String courseId) async {
    final backend = _backend;
    if (backend is! SigninWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    final writer = backend as SigninWriteBackend;
    final normalized = courseId.trim();
    if (normalized.isEmpty) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    return writer.prepareSigninPerform(courseId: normalized);
  }

  /// 准备图书馆或场馆取消的 typed 一次性意图；只接受读取结果中的公开编号。
  Future<WriteIntent> prepareCancellationWrite(
    WriteOperation operation,
    String targetId,
  ) async {
    final backend = _backend;
    if (backend is! CancellationWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    final writer = backend as CancellationWriteBackend;
    final normalized = targetId.trim();
    if (normalized.isEmpty) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    return switch (operation) {
      WriteOperation.libbookCancelBooking => writer.prepareLibbookCancelBooking(
        id: normalized,
      ),
      WriteOperation.cgyyCancelOrder => switch (int.tryParse(normalized)) {
        final id? when id > 0 => writer.prepareCgyyCancelOrder(id: id),
        _ => throw const BackendException(UbaaErrorCode.invalidInput),
      },
      _ => throw const BackendException(UbaaErrorCode.invalidInput),
    };
  }

  /// 准备图书馆预约；所有目标与时段均必须由用户从公开读取结果/控件提供。
  Future<WriteIntent> prepareLibbookReserveWrite({
    required String areaId,
    required String seatId,
    required String day,
    required String segment,
    required String startTime,
    required String endTime,
  }) async {
    final backend = _backend;
    if (backend is! LibbookWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    final values = <String>[
      areaId,
      seatId,
      day,
      segment,
      startTime,
      endTime,
    ].map((value) => value.trim()).toList(growable: false);
    if (values.any((value) => value.isEmpty)) {
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
    if (input.itemId != null && input.itemId! <= 0) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    final startTime = _trimOptional(input.startTime);
    final endTime = _trimOptional(input.endTime);
    final place = _trimOptional(input.place);
    final photo = input.photo;
    if (photo != null &&
        (photo.bytes.isEmpty ||
            photo.fileName.trim().isEmpty ||
            photo.mimeType.trim().isEmpty ||
            !photo.mimeType.trim().toLowerCase().startsWith('image/'))) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    return (backend as YgdkWriteBackend).prepareYgdkSubmit(
      YgdkSubmitInput(
        itemId: input.itemId,
        startTime: startTime,
        endTime: endTime,
        place: place,
        shareToSquare: input.shareToSquare,
        photo: photo == null
            ? null
            : YgdkPhotoInput(
                bytes: List<int>.unmodifiable(photo.bytes),
                fileName: photo.fileName.trim(),
                mimeType: photo.mimeType.trim().toLowerCase(),
              ),
      ),
    );
  }

  /// 准备场馆预约写意图；空间及时段必须来自已读取的公开可预约数据。
  Future<WriteIntent> prepareCgyySubmitWrite(CgyySubmitInput input) async {
    final backend = _backend;
    if (backend is! CgyyWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    if (input.venueSiteId <= 0 ||
        input.purposeType <= 0 ||
        input.joinerNum <= 0 ||
        input.reservationDate.trim().isEmpty ||
        input.phone.trim().isEmpty ||
        input.theme.trim().isEmpty ||
        input.activityContent.trim().isEmpty ||
        input.selections.isEmpty ||
        input.selections.any(
          (selection) =>
              selection.spaceId <= 0 ||
              selection.timeId <= 0 ||
              (selection.venueSpaceGroupId != null &&
                  selection.venueSpaceGroupId! <= 0),
        )) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    final selections = input.selections
        .map(
          (selection) => CgyyReservationSelectionInput(
            spaceId: selection.spaceId,
            timeId: selection.timeId,
            venueSpaceGroupId: selection.venueSpaceGroupId,
          ),
        )
        .toList(growable: false);
    return (backend as CgyyWriteBackend).prepareCgyySubmitReservation(
      CgyySubmitInput(
        venueSiteId: input.venueSiteId,
        reservationDate: input.reservationDate.trim(),
        selections: selections,
        phone: input.phone.trim(),
        theme: input.theme.trim(),
        purposeType: input.purposeType,
        joinerNum: input.joinerNum,
        activityContent: input.activityContent.trim(),
        joiners: input.joiners.trim(),
        isPhilosophySocialSciences: input.isPhilosophySocialSciences,
        isOffSchoolJoiner: input.isOffSchoolJoiner,
      ),
    );
  }

  /// 准备教学评教写意图；仅接受读取结果中的待评课程稳定字段。
  Future<WriteIntent> prepareEvaluationWrite(
    List<EvaluationCourseInput> courses,
  ) async {
    final backend = _backend;
    if (backend is! EvaluationWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    if (courses.isEmpty ||
        courses.any(
          (course) =>
              course.isEvaluated ||
              course.id.trim().isEmpty ||
              course.rwid.trim().isEmpty ||
              course.wjid.trim().isEmpty ||
              course.kcdm.trim().isEmpty ||
              course.msid.trim().isEmpty,
        )) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    return (backend as EvaluationWriteBackend).prepareEvaluationSubmitCourses(
      courses.map(_normalizeEvaluationCourse).toList(growable: false),
    );
  }

  static String? _trimOptional(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static EvaluationCourseInput _normalizeEvaluationCourse(
    EvaluationCourseInput course,
  ) => EvaluationCourseInput(
    id: course.id.trim(),
    kcmc: course.kcmc.trim(),
    bpmc: course.bpmc.trim(),
    isEvaluated: course.isEvaluated,
    rwid: course.rwid.trim(),
    wjid: course.wjid.trim(),
    kcdm: course.kcdm.trim(),
    bpdm: _trimOptional(course.bpdm),
    pjrdm: _trimOptional(course.pjrdm),
    pjrmc: _trimOptional(course.pjrmc),
    xnxq: _trimOptional(course.xnxq),
    msid: course.msid.trim(),
    zdmc: _trimOptional(course.zdmc),
    ypjcs: course.ypjcs,
    xypjcs: course.xypjcs,
    sxz: _trimOptional(course.sxz),
    rwh: _trimOptional(course.rwh),
    xn: _trimOptional(course.xn),
    xq: _trimOptional(course.xq),
    pjlxid: _trimOptional(course.pjlxid),
    sfksqbpj: _trimOptional(course.sfksqbpj),
    yxsfktjst: _trimOptional(course.yxsfktjst),
  );

  /// 提交已确认的一次性意图；不接受任意请求正文，也不自动重试。
  Future<WriteCommitResult> commitWrite(String intentId) async {
    final backend = _backend;
    if (backend is! WriteCommitBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    final writer = backend as WriteCommitBackend;
    if (intentId.trim().isEmpty) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    return writer.commitWrite(intentId);
  }

  /// 写入成功后仅刷新关联只读领域，用于结果核对；不会重试写请求。
  Future<void> refreshAfterWrite(WriteOperation operation) {
    if (operation == WriteOperation.cgyySubmitReservation ||
        operation == WriteOperation.cgyyCancelOrder) {
      // 订单列表是场馆写入的唯一稳定核对入口；若后端不支持筛选查询，
      // 保留旧的领域刷新兼容路径，不伪造核对成功。
      if (_backend is FeatureQueryBackend) {
        return refreshFeatureQuery(
          FeatureId.cgyy,
          const FeatureQuery(view: FeatureQueryView.cgyyOrders),
        );
      }
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
      WriteOperation.evaluationSubmitCourses => FeatureId.evaluation,
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
      if (_disposed || generation != _refreshGeneration) return;
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
      if (_disposed || generation != _refreshGeneration) return;
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
      if (_disposed || generation != _refreshGeneration) return;
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
    _activeRoutes = const <ConnectionMode>[];
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

  bool _routePolicyHasSession(
    RoutePolicy policy,
    List<ConnectionMode> activeRoutes,
  ) => switch (policy) {
    RoutePolicy.auto => activeRoutes.isNotEmpty,
    RoutePolicy.direct => activeRoutes.contains(ConnectionMode.direct),
    RoutePolicy.webvpn => activeRoutes.contains(ConnectionMode.webvpn),
  };

  void _resetFeatureSnapshots() {
    _refreshGeneration++;
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
