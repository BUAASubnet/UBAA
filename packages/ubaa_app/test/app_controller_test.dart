import 'dart:async';

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

  test('明确空结果后刷新失败不伪造成 stale 旧数据', () async {
    var loads = 0;
    final backend = _FlakyBackend(
      load: (_) async {
        loads++;
        if (loads == 1) return const FeatureResult.empty();
        throw const BackendException(UbaaErrorCode.networkError);
      },
    );
    final controller = AppController(backend: backend);
    await controller.refreshHome(only: const <FeatureId>[FeatureId.schedule]);
    await controller.refreshHome(only: const <FeatureId>[FeatureId.schedule]);
    final snapshot = controller.snapshots[FeatureId.schedule]!;
    expect(snapshot.status, FeatureLoadStatus.failure);
    expect(snapshot.summary, isNull);
    expect(snapshot.details, isEmpty);
    expect(snapshot.error?.code, UbaaErrorCode.networkError);
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

  test('初始化进行中时生命周期重建安全拒绝且不释放旧 backend', () async {
    final first = _DelayedInitializeBackend();
    final second = _RebuildBackend(
      signedIn: true,
      activeRoutes: const <ConnectionMode>[ConnectionMode.direct],
    );
    final controller = AppController(
      backend: first,
      backendFactory: () => second,
    );
    final initializing = controller.initialize();
    await first.authStarted.future;

    expect(controller.phase, AppPhase.checkingSession);
    expect(await controller.rebuildBackend(), isFalse);
    expect(first.disposed, isFalse);
    expect(second.disposed, isFalse);

    first.releaseAuth.complete();
    await initializing;
    expect(controller.phase, AppPhase.login);
    controller.dispose();
  });

  test('controller 销毁后初始化不会继续读取用户或刷新首页', () async {
    final backend = _DelayedSignedInInitializeBackend();
    final controller = AppController(backend: backend);
    final initializing = controller.initialize();
    await backend.authStarted.future;

    controller.dispose();
    backend.releaseAuth.complete();
    await initializing;

    expect(backend.userInfoCalls, 0);
    expect(backend.featureLoads, 0);
  });

  test('controller 销毁后延迟登录不会继续读取用户或保存凭据', () async {
    final backend = _DelayedLoginBackend();
    final vault = MemoryCredentialVault();
    final controller = AppController(
      backend: backend,
      credentialVault: vault,
    );
    controller.setUsername('student');
    controller.setPassword('secret');

    final loggingIn = controller.submitLogin();
    await backend.loginStarted.future;
    controller.dispose();
    backend.releaseLogin.complete();
    await loggingIn;

    expect(backend.userInfoCalls, 0);
    expect(vault.saveCount, 0);
  });

  test('controller 销毁后延迟路线设置不会回写策略', () async {
    final backend = _DelayedRoutePolicyBackend();
    final controller = AppController(backend: backend);

    final changing = controller.setRoutePolicy(RoutePolicy.webvpn);
    await backend.prepareStarted.future;
    controller.dispose();
    backend.releasePrepare.complete();
    await changing;

    expect(backend.routeSettingsCalls, 0);
    expect(controller.loginForm.routePolicy, RoutePolicy.auto);
  });

  test('controller 销毁后延迟注销不会回写登录状态', () async {
    final backend = _DelayedLogoutBackend();
    final controller = AppController(backend: backend);

    final loggingOut = controller.logout();
    await backend.logoutStarted.future;
    controller.dispose();
    backend.releaseLogout.complete();
    await loggingOut;

    expect(controller.phase, AppPhase.splash);
  });

  test('controller 销毁后延迟的功能读取不会回写快照', () async {
    final backend = _DelayedFeatureBackend();
    final controller = AppController(backend: backend);
    final refreshing = controller.refreshHome(
      only: const <FeatureId>[FeatureId.schedule],
    );
    await backend.loadStarted.future;

    expect(
      controller.snapshots[FeatureId.schedule]!.status,
      FeatureLoadStatus.loading,
    );
    controller.dispose();
    backend.releaseLoad.complete(
      const FeatureResult.success(
        summary: '不应回写',
        details: <FeatureDetail>[FeatureDetail(title: '不应回写')],
      ),
    );
    await refreshing;

    final snapshot = controller.snapshots[FeatureId.schedule]!;
    expect(snapshot.status, FeatureLoadStatus.loading);
    expect(snapshot.summary, isNull);
    expect(snapshot.details, isEmpty);
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

  test('阳光打卡写意图只保留内存输入并拒绝空照片', () async {
    final backend = _YgdkWriteBackend();
    final controller = AppController(backend: backend);
    final intent = await controller.prepareYgdkWrite(
      const YgdkSubmitInput(
        itemId: 7,
        startTime: '09:00',
        endTime: '10:00',
        place: '校园',
        shareToSquare: false,
        photo: YgdkPhotoInput(
          bytes: <int>[1, 2, 3],
          fileName: 'safe.jpg',
          mimeType: 'image/jpeg',
        ),
      ),
    );
    expect(intent.operation, WriteOperation.ygdkSubmit);
    expect(backend.input?.itemId, 7);
    expect(backend.commitCalls, 0);
    await expectLater(
      controller.prepareYgdkWrite(
        const YgdkSubmitInput(
          photo: YgdkPhotoInput(
            bytes: <int>[],
            fileName: 'empty.jpg',
            mimeType: 'image/jpeg',
          ),
        ),
      ),
      throwsA(isA<BackendException>()),
    );
    controller.dispose();
  });

  test('场馆预约写意图校验公开站点、时段和参与信息', () async {
    final backend = _CgyyWriteBackend();
    final controller = AppController(backend: backend);
    final intent = await controller.prepareCgyySubmitWrite(
      const CgyySubmitInput(
        venueSiteId: 3,
        reservationDate: '2026-09-03',
        selections: <CgyyReservationSelectionInput>[
          CgyyReservationSelectionInput(spaceId: 4, timeId: 5),
        ],
        phone: 'phone-placeholder',
        theme: '课程讨论',
        purposeType: 1,
        joinerNum: 2,
        activityContent: '讨论',
        joiners: '张三',
        isPhilosophySocialSciences: false,
        isOffSchoolJoiner: false,
      ),
    );
    expect(intent.operation, WriteOperation.cgyySubmitReservation);
    expect(backend.input?.venueSiteId, 3);
    expect(backend.commitCalls, 0);
    await expectLater(
      controller.prepareCgyySubmitWrite(
        const CgyySubmitInput(
          venueSiteId: 3,
          reservationDate: '2026-09-03',
          selections: <CgyyReservationSelectionInput>[],
          phone: 'phone-placeholder',
          theme: '课程讨论',
          purposeType: 1,
          joinerNum: 1,
          activityContent: '讨论',
          joiners: '',
          isPhilosophySocialSciences: false,
          isOffSchoolJoiner: false,
        ),
      ),
      throwsA(isA<BackendException>()),
    );
    controller.dispose();
  });

  test('教学评教写意图只接受待评课程且至少一门', () async {
    final backend = _EvaluationWriteBackend();
    final controller = AppController(backend: backend);
    final intent = await controller
        .prepareEvaluationWrite(const <EvaluationCourseInput>[
          EvaluationCourseInput(
            id: 'course-1',
            kcmc: '课程',
            bpmc: '教师',
            rwid: 'task-1',
            wjid: 'questionnaire-1',
            kcdm: 'K1',
            msid: 'M1',
          ),
        ]);
    expect(intent.operation, WriteOperation.evaluationSubmitCourses);
    expect(backend.courses.single.id, 'course-1');
    expect(backend.commitCalls, 0);
    await expectLater(
      controller.prepareEvaluationWrite(const <EvaluationCourseInput>[]),
      throwsA(isA<BackendException>()),
    );
    await expectLater(
      controller.prepareEvaluationWrite(const <EvaluationCourseInput>[
        EvaluationCourseInput(
          id: 'done',
          kcmc: '课程',
          bpmc: '教师',
          isEvaluated: true,
          rwid: 'task-1',
          wjid: 'questionnaire-1',
          kcdm: 'K1',
          msid: 'M1',
        ),
      ]),
      throwsA(isA<BackendException>()),
    );
    controller.dispose();
  });

  test('写入成功核对只刷新对应读取领域', () async {
    final backend = _BykcWriteBackend();
    final controller = AppController(backend: backend);
    await controller.refreshAfterWrite(WriteOperation.libbookCancelBooking);
    expect(backend.loadedFeatures, <FeatureId>[FeatureId.libbook]);
    controller.dispose();
  });

  test('场馆写入成功优先刷新订单列表用于核对', () async {
    final backend = _CgyyQueryWriteBackend();
    final controller = AppController(backend: backend);

    await controller.refreshAfterWrite(WriteOperation.cgyySubmitReservation);

    expect(backend.queries, hasLength(1));
    expect(backend.queries.single.$1, FeatureId.cgyy);
    expect(backend.queries.single.$2.view, FeatureQueryView.cgyyOrders);
    controller.dispose();
  });

  test('场馆提交收据只匹配刷新后订单列表中的公开编号', () async {
    final backend = _CgyyQueryWriteBackend(
      queryResult: const FeatureResult.success(
        details: <FeatureDetail>[
          FeatureDetail(
            title: '场馆订单',
            fields: <FeatureField>[
              FeatureField(label: '订单编号', value: '42'),
            ],
          ),
        ],
      ),
    );
    final controller = AppController(backend: backend);

    await controller.refreshAfterWrite(WriteOperation.cgyySubmitReservation);

    expect(
      await controller.matchesCgyyReceipt(
        const CgyyReservationReceipt(orderId: 42),
      ),
      isTrue,
    );
    expect(
      await controller.matchesCgyyReceipt(
        const CgyyReservationReceipt(orderId: 43),
      ),
      isFalse,
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

class _DelayedFeatureBackend implements UbaaBackend {
  final Completer<void> loadStarted = Completer<void>();
  final Completer<FeatureResult> releaseLoad = Completer<FeatureResult>();

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
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    loadStarted.complete();
    return releaseLoad.future;
  }
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

class _DelayedInitializeBackend
    implements UbaaBackend, BackendLifecycle {
  final Completer<void> authStarted = Completer<void>();
  final Completer<void> releaseAuth = Completer<void>();
  bool disposed = false;

  @override
  Future<AuthStatus> authStatus() async {
    authStarted.complete();
    await releaseAuth.future;
    return AuthStatus.signedOut;
  }

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
  Future<void> dispose() async {
    disposed = true;
  }
}

class _DelayedSignedInInitializeBackend
    implements UbaaBackend, BackendLifecycle {
  final Completer<void> authStarted = Completer<void>();
  final Completer<void> releaseAuth = Completer<void>();
  int userInfoCalls = 0;
  int featureLoads = 0;

  @override
  Future<AuthStatus> authStatus() async {
    authStarted.complete();
    await releaseAuth.future;
    return AuthStatus.signedIn;
  }

  @override
  Future<UserSummary?> userInfo() async {
    userInfoCalls++;
    return const UserSummary(username: 'student');
  }

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    featureLoads++;
    return const FeatureResult.empty();
  }

  @override
  Future<void> dispose() async {}
}

class _DelayedLoginBackend implements UbaaBackend, BackendLifecycle {
  final Completer<void> loginStarted = Completer<void>();
  final Completer<void> releaseLogin = Completer<void>();
  int userInfoCalls = 0;

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedOut;

  @override
  Future<UserSummary?> userInfo() async {
    userInfoCalls++;
    return const UserSummary(username: 'student');
  }

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {
    loginStarted.complete();
    await releaseLogin.future;
  }

  @override
  Future<void> logout() async {}

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();

  @override
  Future<void> dispose() async {}
}

class _DelayedRoutePolicyBackend
    implements UbaaBackend, RouteSettingsBackend, BackendLifecycle {
  final Completer<void> prepareStarted = Completer<void>();
  final Completer<void> releasePrepare = Completer<void>();
  int routeSettingsCalls = 0;

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedOut;

  @override
  Future<UserSummary?> userInfo() async => null;

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {
    prepareStarted.complete();
    await releasePrepare.future;
  }

  @override
  Future<void> login(LoginInput input) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();

  @override
  Future<BackendRouteSettings> routeSettings() async {
    routeSettingsCalls++;
    return const BackendRouteSettings(
      defaultPolicy: RoutePolicy.webvpn,
      activeRoutes: <ConnectionMode>[],
    );
  }

  @override
  Future<void> dispose() async {}
}

class _DelayedLogoutBackend implements UbaaBackend, BackendLifecycle {
  final Completer<void> logoutStarted = Completer<void>();
  final Completer<void> releaseLogout = Completer<void>();

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
  Future<void> logout() async {
    logoutStarted.complete();
    await releaseLogout.future;
  }

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();

  @override
  Future<void> dispose() async {}
}

class _BykcWriteBackend implements UbaaBackend, BykcWriteBackend {
  int? selectedCourseId;
  int? signCourseId;
  int? signType;
  int commitCalls = 0;
  final List<FeatureId> loadedFeatures = <FeatureId>[];

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
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    loadedFeatures.add(feature);
    return const FeatureResult.empty();
  }

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

class _YgdkWriteBackend implements UbaaBackend, YgdkWriteBackend {
  YgdkSubmitInput? input;
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
  Future<WriteIntent> prepareYgdkSubmit(YgdkSubmitInput input) async {
    this.input = input;
    return _intent();
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    commitCalls++;
    return const WriteCommitResult(
      operation: WriteOperation.ygdkSubmit,
      success: true,
      message: 'ok',
      outcomeUnknown: false,
    );
  }

  WriteIntent _intent() => WriteIntent(
    intentId: 'ygdk-intent',
    operation: WriteOperation.ygdkSubmit,
    targetSummary: '阳光打卡',
    resolvedRoute: ConnectionMode.direct,
    warnings: <String>[],
    expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    requestDigest: 'digest',
  );
}

class _CgyyWriteBackend implements UbaaBackend, CgyyWriteBackend {
  CgyySubmitInput? input;
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
  Future<WriteIntent> prepareCgyySubmitReservation(
    CgyySubmitInput input,
  ) async {
    this.input = input;
    return _intent();
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    commitCalls++;
    return const WriteCommitResult(
      operation: WriteOperation.cgyySubmitReservation,
      success: true,
      message: 'ok',
      outcomeUnknown: false,
    );
  }

  WriteIntent _intent() => WriteIntent(
    intentId: 'cgyy-intent',
    operation: WriteOperation.cgyySubmitReservation,
    targetSummary: '场馆预约',
    resolvedRoute: ConnectionMode.direct,
    warnings: <String>[],
    expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    requestDigest: 'digest',
  );
}

class _CgyyQueryWriteBackend extends _CgyyWriteBackend
    implements FeatureQueryBackend {
  _CgyyQueryWriteBackend({this.queryResult = const FeatureResult.empty()});

  final FeatureResult queryResult;
  final List<(FeatureId, FeatureQuery)> queries = <(FeatureId, FeatureQuery)>[];

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    queries.add((feature, query));
    return queryResult;
  }
}

class _EvaluationWriteBackend implements UbaaBackend, EvaluationWriteBackend {
  List<EvaluationCourseInput> courses = const <EvaluationCourseInput>[];
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
  Future<WriteIntent> prepareEvaluationSubmitCourses(
    List<EvaluationCourseInput> courses,
  ) async {
    this.courses = courses;
    return _intent();
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    commitCalls++;
    return const WriteCommitResult(
      operation: WriteOperation.evaluationSubmitCourses,
      success: true,
      message: 'ok',
      outcomeUnknown: false,
    );
  }

  WriteIntent _intent() => WriteIntent(
    intentId: 'evaluation-intent',
    operation: WriteOperation.evaluationSubmitCourses,
    targetSummary: '教学评教',
    resolvedRoute: ConnectionMode.direct,
    warnings: <String>[],
    expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    requestDigest: 'digest',
  );
}
