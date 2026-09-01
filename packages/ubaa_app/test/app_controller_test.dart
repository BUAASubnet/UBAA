import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('登录后独立加载普通与高级只读功能', () async {
    final controller = AppController(
      backend: DemoBackend(loginDelay: Duration.zero),
      credentialVault: MemoryCredentialVault(),
    );
    await controller.initialize();
    expect(controller.phase, AppPhase.login);
    controller.setUsername('2020000000');
    controller.setPassword('not-a-real-password');
    await controller.submitLogin();
    expect(controller.phase, AppPhase.home);
    await controller.refreshHome();
    expect(
      controller.snapshots.values.every(
        (snapshot) => snapshot.status == FeatureLoadStatus.success,
      ),
      isTrue,
    );
    controller.dispose();
  });

  test('生产能力不可用时不伪造 Demo 登录成功', () async {
    final controller = AppController(backend: const UnavailableBackend());
    await controller.initialize();
    expect(controller.phase, AppPhase.login);
    expect(controller.error?.code, UbaaErrorCode.unsupported);
    controller.dispose();
  });

  test('安全保险箱明确开启自动登录时恢复会话并清理密码', () async {
    final controller = AppController(
      backend: DemoBackend(loginDelay: Duration.zero),
      credentialVault: MemoryCredentialVault(
        initial: const Credential(
          username: '2020000000',
          password: 'saved-secret',
          autoLogin: true,
        ),
      ),
    );
    await controller.initialize();
    expect(controller.phase, AppPhase.home);
    expect(controller.user?.username, '2020000000');
    expect(controller.loginForm.password, isEmpty);
    expect(controller.loginForm.autoLogin, isTrue);
    controller.dispose();
  });

  test('退出登录与退出并清除本机账号保持分离', () async {
    final vault = MemoryCredentialVault(
      initial: const Credential(
        username: '2020000000',
        password: 'saved-secret',
      ),
    );
    final controller = AppController(
      backend: DemoBackend(loginDelay: Duration.zero),
      credentialVault: vault,
    );
    await controller.initialize();

    await controller.logout();
    expect(vault.hasValue, isTrue);
    await controller.logout(clearSavedCredential: true);
    expect(vault.hasValue, isFalse);
    controller.dispose();
  });

  test('错误映射不暴露上游细节', () {
    final error = UbaaErrorMapper.fromCode(UbaaErrorCode.networkError);
    expect(error.message, contains('校园网'));
    expect(error.message, isNot(contains('http')));
    expect(error.retryable, isTrue);
  });

  test('刷新失败时保留上次数据并标记 stale', () async {
    var loads = 0;
    final backend = _FlakyBackend(
      load: (_) async {
        loads++;
        if (loads > 1) {
          throw const BackendException(UbaaErrorCode.networkError);
        }
        return const FeatureResult.success(
          summary: '上次成功数据',
          details: <FeatureDetail>[
            FeatureDetail(title: '课程', subtitle: '保留内容'),
          ],
        );
      },
    );
    final controller = AppController(backend: backend);
    await controller.refreshHome(only: const <FeatureId>[FeatureId.schedule]);
    expect(
      controller.snapshots[FeatureId.schedule]!.status,
      FeatureLoadStatus.success,
    );
    await controller.refreshHome(only: const <FeatureId>[FeatureId.schedule]);
    final snapshot = controller.snapshots[FeatureId.schedule]!;
    expect(snapshot.status, FeatureLoadStatus.stale);
    expect(snapshot.details.single.title, '课程');
    expect(snapshot.error?.code, UbaaErrorCode.networkError);
    controller.dispose();
  });

  test('Core 明确返回空结果时清除上次成功摘要和详情', () async {
    var loads = 0;
    final backend = _FlakyBackend(
      load: (_) async {
        loads++;
        return loads == 1
            ? const FeatureResult.success(
                summary: '上次成功数据',
                details: <FeatureDetail>[FeatureDetail(title: '课程')],
              )
            : const FeatureResult.empty();
      },
    );
    final controller = AppController(backend: backend);
    await controller.refreshHome(only: const <FeatureId>[FeatureId.schedule]);
    await controller.refreshHome(only: const <FeatureId>[FeatureId.schedule]);
    final snapshot = controller.snapshots[FeatureId.schedule]!;
    expect(snapshot.status, FeatureLoadStatus.empty);
    expect(snapshot.summary, isNull);
    expect(snapshot.details, isEmpty);
    controller.dispose();
  });

  test('读取结果保留 Core 实际解析路线而不使用配置策略替代', () async {
    final backend = _FlakyBackend(
      load: (_) async => const FeatureResult.success(
        summary: 'WebVPN 数据',
        details: <FeatureDetail>[FeatureDetail(title: '课程')],
        resolvedRoute: ConnectionMode.webvpn,
      ),
    );
    final controller = AppController(backend: backend);
    await controller.refreshHome(only: const <FeatureId>[FeatureId.schedule]);
    expect(
      controller.snapshots[FeatureId.schedule]!.resolvedRoute,
      ConnectionMode.webvpn,
    );
    controller.dispose();
  });

  test('切换到未认证固定路线时清除用户状态并回到登录页', () async {
    final backend = _RouteStateBackend(
      activeRoutes: const <ConnectionMode>[ConnectionMode.webvpn],
    );
    final controller = AppController(backend: backend);
    await controller.initialize();
    expect(controller.phase, AppPhase.home);
    expect(controller.loginForm.routePolicy, RoutePolicy.auto);

    await controller.setRoutePolicy(RoutePolicy.direct);

    expect(controller.phase, AppPhase.login);
    expect(controller.user, isNull);
    expect(controller.loginForm.routePolicy, RoutePolicy.direct);
    expect(
      controller.snapshots.values.every(
        (snapshot) => snapshot.status == FeatureLoadStatus.idle,
      ),
      isTrue,
    );
    controller.dispose();
  });

  test('领域查询参数通过 FeatureQueryBackend typed 传递', () async {
    FeatureQuery? received;
    final backend = _QueryBackend(
      onQuery: (_, query) {
        received = query;
        return const FeatureResult.success(
          summary: '指定查询',
          details: <FeatureDetail>[FeatureDetail(title: '查询结果')],
        );
      },
    );
    final controller = AppController(backend: backend);
    await controller.refreshFeatureQuery(
      FeatureId.classroom,
      FeatureQuery(
        date: DateTime(2026, 9, 2),
        campus: 2,
        week: 3,
        page: 1,
        size: 10,
      ),
    );
    expect(received?.campus, 2);
    expect(received?.week, 3);
    expect(received?.page, 1);
    expect(controller.snapshots[FeatureId.classroom]!.summary, '指定查询');
    controller.dispose();
  });

  test('宿主重建 backend 后重新读取认证和路线状态', () async {
    final first = _RebuildBackend(
      signedIn: false,
      activeRoutes: const <ConnectionMode>[],
    );
    final second = _RebuildBackend(
      signedIn: true,
      activeRoutes: const <ConnectionMode>[ConnectionMode.webvpn],
    );
    var factoryCalls = 0;
    final controller = AppController(
      backend: first,
      backendFactory: () {
        factoryCalls++;
        return second;
      },
    );
    await controller.initialize();
    expect(controller.phase, AppPhase.login);

    expect(await controller.rebuildBackend(), isTrue);
    expect(factoryCalls, 1);
    expect(first.disposed, isTrue);
    expect(controller.phase, AppPhase.home);
    expect(controller.user?.username, 'student');
    expect(controller.activeRoutes, <ConnectionMode>[ConnectionMode.webvpn]);
    controller.dispose();
  });

  test('博雅写意图通过 typed backend 准备且控制器不替换请求参数', () async {
    final backend = _BykcWriteBackend();
    final controller = AppController(backend: backend);

    final intent = await controller.prepareBykcWrite(
      WriteOperation.bykcSelectCourse,
      42,
    );
    expect(intent.operation, WriteOperation.bykcSelectCourse);
    expect(backend.selectedCourseId, 42);
    expect(backend.commitCalls, 0);

    final committed = await controller.commitWrite(intent.intentId);
    expect(committed.success, isTrue);
    expect(backend.commitCalls, 1);
    controller.dispose();
  });

  test('博雅写意图拒绝非正课程 ID 和未接入的操作', () async {
    final controller = AppController(backend: _BykcWriteBackend());
    await expectLater(
      controller.prepareBykcWrite(WriteOperation.bykcSelectCourse, 0),
      throwsA(
        isA<BackendException>().having(
          (error) => error.code,
          'code',
          UbaaErrorCode.invalidInput,
        ),
      ),
    );
    await expectLater(
      controller.prepareBykcWrite(WriteOperation.signinPerform, 42),
      throwsA(
        isA<BackendException>().having(
          (error) => error.code,
          'code',
          UbaaErrorCode.invalidInput,
        ),
      ),
    );
    controller.dispose();
  });

  test('课堂签到写意图只接受读取结果中的非空课程编号', () async {
    final backend = _SigninWriteBackend();
    final controller = AppController(backend: backend);

    final intent = await controller.prepareSigninWrite(' course-7 ');
    expect(intent.operation, WriteOperation.signinPerform);
    expect(backend.courseId, 'course-7');
    expect(backend.commitCalls, 0);
    await controller.commitWrite(intent.intentId);
    expect(backend.commitCalls, 1);

    await expectLater(
      controller.prepareSigninWrite('  '),
      throwsA(
        isA<BackendException>().having(
          (error) => error.code,
          'code',
          UbaaErrorCode.invalidInput,
        ),
      ),
    );
    controller.dispose();
  });

  test('可逆取消写意图按领域严格校验公开编号', () async {
    final backend = _CancellationWriteBackend();
    final controller = AppController(backend: backend);

    final libraryIntent = await controller.prepareCancellationWrite(
      WriteOperation.libbookCancelBooking,
      ' booking-3 ',
    );
    expect(libraryIntent.operation, WriteOperation.libbookCancelBooking);
    expect(backend.bookingId, 'booking-3');

    final venueIntent = await controller.prepareCancellationWrite(
      WriteOperation.cgyyCancelOrder,
      '17',
    );
    expect(venueIntent.operation, WriteOperation.cgyyCancelOrder);
    expect(backend.orderId, 17);

    await expectLater(
      controller.prepareCancellationWrite(
        WriteOperation.cgyyCancelOrder,
        'not-a-number',
      ),
      throwsA(isA<BackendException>()),
    );
    controller.dispose();
  });

  test('博雅签到写意图只接受冻结 signType 1 或 2', () async {
    final backend = _BykcWriteBackend();
    final controller = AppController(backend: backend);

    final intent = await controller.prepareBykcSignWrite(42, 1);
    expect(intent.operation, WriteOperation.bykcSignCourse);
    expect(backend.signCourseId, 42);
    expect(backend.signType, 1);

    await expectLater(
      controller.prepareBykcSignWrite(42, 3),
      throwsA(isA<BackendException>()),
    );
    controller.dispose();
  });

  test('图书馆预约写意图要求完整的公开选座参数', () async {
    final backend = _LibbookWriteBackend();
    final controller = AppController(backend: backend);
    final intent = await controller.prepareLibbookReserveWrite(
      areaId: 'area-1',
      seatId: 'seat-2',
      day: '2026-09-02',
      segment: '3',
      startTime: '10:00',
      endTime: '12:00',
    );
    expect(intent.operation, WriteOperation.libbookReserve);
    expect(backend.seatId, 'seat-2');
    await expectLater(
      controller.prepareLibbookReserveWrite(
        areaId: ' ',
        seatId: 'seat-2',
        day: '2026-09-02',
        segment: '3',
        startTime: '10:00',
        endTime: '12:00',
      ),
      throwsA(isA<BackendException>()),
    );
    controller.dispose();
  });
}

class _FlakyBackend implements UbaaBackend {
  _FlakyBackend({required this.load});

  final Future<FeatureResult> Function(FeatureId) load;

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedOut;

  @override
  Future<UserSummary?> userInfo() async => null;

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) => load(feature);
}

class _QueryBackend implements UbaaBackend, FeatureQueryBackend {
  _QueryBackend({required this.onQuery});

  final FeatureResult Function(FeatureId, FeatureQuery) onQuery;

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedOut;

  @override
  Future<UserSummary?> userInfo() async => null;

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async => onQuery(feature, query);
}

class _RouteStateBackend implements UbaaBackend, RouteSettingsBackend {
  _RouteStateBackend({required this.activeRoutes});

  final List<ConnectionMode> activeRoutes;
  RoutePolicy defaultPolicy = RoutePolicy.auto;

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;

  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'student');

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {
    defaultPolicy = policy;
  }

  @override
  Future<void> login(LoginInput input) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();

  @override
  Future<BackendRouteSettings> routeSettings() async => BackendRouteSettings(
    defaultPolicy: defaultPolicy,
    activeRoutes: activeRoutes,
  );
}

class _RebuildBackend
    implements UbaaBackend, RouteSettingsBackend, BackendLifecycle {
  _RebuildBackend({required this.signedIn, required this.activeRoutes});

  final bool signedIn;
  final List<ConnectionMode> activeRoutes;
  bool disposed = false;

  @override
  Future<AuthStatus> authStatus() async =>
      signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;

  @override
  Future<UserSummary?> userInfo() async =>
      signedIn ? const UserSummary(username: 'student') : null;

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();

  @override
  Future<BackendRouteSettings> routeSettings() async => BackendRouteSettings(
    defaultPolicy: RoutePolicy.auto,
    activeRoutes: activeRoutes,
  );

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _BykcWriteBackend implements UbaaBackend, BykcWriteBackend {
  int? selectedCourseId;
  int? signCourseId;
  int? signType;
  int commitCalls = 0;

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;

  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'student');

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();

  @override
  Future<WriteIntent> prepareBykcSelectCourse({required int courseId}) async {
    selectedCourseId = courseId;
    return _intent(WriteOperation.bykcSelectCourse);
  }

  @override
  Future<WriteIntent> prepareBykcDeselectCourse({required int courseId}) async {
    selectedCourseId = courseId;
    return _intent(WriteOperation.bykcDeselectCourse);
  }

  @override
  Future<WriteIntent> prepareBykcSignCourse({
    required int courseId,
    double? lat,
    double? lng,
    required int signType,
  }) async {
    this.signCourseId = courseId;
    this.signType = signType;
    return _intent(WriteOperation.bykcSignCourse);
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    commitCalls++;
    return const WriteCommitResult(
      operation: WriteOperation.bykcSelectCourse,
      success: true,
      message: 'ok',
      outcomeUnknown: false,
    );
  }

  WriteIntent _intent(WriteOperation operation) => WriteIntent(
    intentId: 'intent-${selectedCourseId ?? 0}',
    operation: operation,
    targetSummary: '课程 ${selectedCourseId ?? 0}',
    resolvedRoute: ConnectionMode.direct,
    warnings: const <String>[],
    expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    requestDigest: 'digest',
  );
}

class _SigninWriteBackend implements UbaaBackend, SigninWriteBackend {
  String? courseId;
  int commitCalls = 0;

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;

  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'student');

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();

  @override
  Future<WriteIntent> prepareSigninPerform({required String courseId}) async {
    this.courseId = courseId;
    return _intent();
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    commitCalls++;
    return const WriteCommitResult(
      operation: WriteOperation.signinPerform,
      success: true,
      message: 'ok',
      outcomeUnknown: false,
    );
  }

  WriteIntent _intent() => WriteIntent(
    intentId: 'signin-intent',
    operation: WriteOperation.signinPerform,
    targetSummary: '课程 ${courseId ?? ''}',
    resolvedRoute: ConnectionMode.direct,
    warnings: const <String>[],
    expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    requestDigest: 'digest',
  );
}

class _CancellationWriteBackend
    implements UbaaBackend, CancellationWriteBackend {
  String? bookingId;
  int? orderId;

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;

  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'student');

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();

  @override
  Future<WriteIntent> prepareLibbookCancelBooking({required String id}) async {
    bookingId = id;
    return _intent(WriteOperation.libbookCancelBooking, id);
  }

  @override
  Future<WriteIntent> prepareCgyyCancelOrder({required int id}) async {
    orderId = id;
    return _intent(WriteOperation.cgyyCancelOrder, '$id');
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async =>
      const WriteCommitResult(
        operation: WriteOperation.libbookCancelBooking,
        success: true,
        message: 'ok',
        outcomeUnknown: false,
      );

  WriteIntent _intent(WriteOperation operation, String target) => WriteIntent(
    intentId: 'cancel-intent',
    operation: operation,
    targetSummary: '取消 $target',
    resolvedRoute: ConnectionMode.direct,
    warnings: const <String>[],
    expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    requestDigest: 'digest',
  );
}

class _LibbookWriteBackend implements UbaaBackend, LibbookWriteBackend {
  String? seatId;

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;

  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'student');

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();

  @override
  Future<WriteIntent> prepareLibbookReserve({
    required String areaId,
    required String seatId,
    required String day,
    required String segment,
    required String startTime,
    required String endTime,
  }) async {
    this.seatId = seatId;
    return WriteIntent(
      intentId: 'reserve-intent',
      operation: WriteOperation.libbookReserve,
      targetSummary: '$areaId/$seatId $day $segment',
      resolvedRoute: ConnectionMode.direct,
      warnings: const <String>[],
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      requestDigest: 'digest',
    );
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async =>
      const WriteCommitResult(
        operation: WriteOperation.libbookReserve,
        success: true,
        message: 'ok',
        outcomeUnknown: false,
      );
}
