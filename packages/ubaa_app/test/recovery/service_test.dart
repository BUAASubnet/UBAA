import 'dart:async';
import 'backend_rebuild/fakes.dart' as base;
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_app/runtime.dart'
    show RecoveryInterrupted, RecoveryStopReason;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/recovery.dart' as support;

const expired = UiError(
  code: UbaaErrorCode.authenticationRequired,
  kind: UbaaErrorKind.authentication,
  resolvedRoute: ConnectionMode.direct,
  title: '需要登录',
  message: '合成会话失效',
);

Future<AppController> start(_Backend backend, {bool automatic = true}) async {
  final controller = AppController(
    backend: backend,
    localAccountStore: await support.savedAccounts(),
    credentialVault: MemoryCredentialVault(
      initial: Credential(
        username: 'fixture-user',
        password: 'synthetic',
        autoLogin: automatic,
      ),
    ),
  );
  addTearDown(controller.dispose);
  await controller.initialize();
  controller.setAutoLogin(automatic);
  controller.internalSessionRecoveryStatus = SessionRecoveryStatus.ready;
  return controller;
}

void main() {
  test('我的余额与流量缺少直连会话时按实际目标补认证并完成读取', () async {
    final backend = _Backend();
    final controller = await start(backend);
    final service = controller.campusAccountService!;
    await Future.wait([service.metrics(), service.networkUsage()]);
    expect(
      backend.targets,
      containsAll([RecoveryTarget.portal, RecoveryTarget.network]),
    );
    expect(backend.loginRoutes, [ConnectionMode.direct]);
    expect(backend.metricsReads, 2);
    expect(backend.networkReads, 2);
    expect(controller.diagnostics.records, isEmpty);
  });

  test('专用服务恢复期间阻塞其他操作，完成后解除阻塞', () async {
    final backend = _Backend()..recoveryGate = Completer<void>();
    final controller = await start(backend);
    final pending = controller.campusAccountService!.networkUsage();
    await backend.recoveryStarted.future.timeout(const Duration(seconds: 2));
    expect(controller.homeTodoProjectionBlocked, isTrue);
    expect(controller.internalReadTransitionBlocked, isTrue);
    expect(controller.canClearBusinessCache, isFalse);
    backend.recoveryGate!.complete();
    await pending;
    expect(controller.homeTodoProjectionBlocked, isFalse);
    expect(controller.internalReadTransitionBlocked, isFalse);
  });

  test('所需路线为 WebVPN 时仅恢复 WebVPN', () async {
    final backend = _Backend()..route = ConnectionMode.webvpn;
    final controller = await start(backend);
    await controller.campusAccountService!.networkUsage();
    expect(backend.loginRoutes, [ConnectionMode.webvpn]);
  });

  test('待确认写入期间保留确认内容，不开始自动认证', () async {
    final backend = _Backend();
    final controller = await start(backend);
    final intent = base.intent();
    controller.writeCoordinator.setIntent(intent);
    await expectLater(
      controller.campusAccountService!.metrics(),
      throwsA(isA<UiError>()),
    );
    expect(backend.targets, isEmpty);
    expect(backend.loginRoutes, isEmpty);
    expect(controller.writeCoordinator.intent, same(intent));
  });

  test('恢复超时保留超时分类并记入诊断', () async {
    final backend = _Backend()
      ..recoveryFailure = const RecoveryInterrupted(
        RecoveryStopReason.deadline,
      );
    final controller = await start(backend);
    await expectLater(
      controller.campusAccountService!.networkUsage(),
      throwsA(
        isA<UiError>().having(
          (error) => error.code,
          '错误码',
          UbaaErrorCode.timeout,
        ),
      ),
    );
    expect(controller.diagnostics.records.single.code, UbaaErrorCode.timeout);
  });

  test('云盘明确不支持当前路线时不尝试另一条路线', () async {
    final backend = _Backend()
      ..recoveryFailure = const BackendException(
        UbaaErrorCode.unsupported,
        resolvedRoute: ConnectionMode.webvpn,
      );
    final controller = await start(backend);
    await expectLater(
      controller.bhpanService!.login(),
      throwsA(
        isA<UiError>().having(
          (error) => error.code,
          '错误码',
          UbaaErrorCode.unsupported,
        ),
      ),
    );
    expect(backend.loginRoutes, isEmpty);
  });

  test('云盘的认证类权限错误可以恢复，普通权限不足直接返回', () async {
    for (final authentication in [true, false]) {
      final backend = _Backend()
        ..failure = UiError(
          code: UbaaErrorCode.permissionDenied,
          kind: authentication
              ? UbaaErrorKind.authentication
              : UbaaErrorKind.input,
          title: '合成权限错误',
          message: '合成',
        );
      final controller = await start(backend);
      if (authentication) {
        await controller.bhpanService!.login();
        expect(backend.loginRoutes, [ConnectionMode.direct]);
      } else {
        await expectLater(
          controller.bhpanService!.login(),
          throwsA(isA<UiError>()),
        );
        expect(backend.targets, isEmpty);
      }
    }
  });

  test('余额单项失败保留其他值并记录真实错误，不重试网络失败', () async {
    final backend = _Backend()
      ..ready = true
      ..metricError = const UiError(
        code: UbaaErrorCode.networkError,
        resolvedRoute: ConnectionMode.direct,
        title: '合成',
        message: '合成',
      );
    final controller = await start(backend);
    final metrics = await controller.campusAccountService!.metrics();
    expect(metrics.cardBalance, isA<CampusMetricValue<CampusAmount>>());
    expect(metrics.networkBalance, isA<CampusMetricFailure<CampusAmount>>());
    expect(backend.targets, isEmpty);
    expect(
      controller.diagnostics.records.single.code,
      UbaaErrorCode.networkError,
    );
  });

  test('逐项认证恢复未获自动登录许可时保留本次已成功的余额', () async {
    final backend = _Backend()..metricError = expired;
    final controller = await start(backend, automatic: false);
    final metrics = await controller.campusAccountService!.metrics();
    expect(metrics.cardBalance, isA<CampusMetricValue<CampusAmount>>());
    expect(metrics.networkBalance, isA<CampusMetricFailure<CampusAmount>>());
    expect(backend.loginRoutes, isEmpty);
    expect(
      controller.diagnostics.records.single.code,
      UbaaErrorCode.authenticationRequired,
    );
  });

  test('余额结果中的认证失败也会恢复一次', () async {
    final backend = _Backend()..metricError = expired;
    final controller = await start(backend);
    final metrics = await controller.campusAccountService!.metrics();
    expect(backend.loginRoutes, [ConnectionMode.direct]);
    expect(metrics.networkBalance, isNull);
    expect(controller.diagnostics.records, isEmpty);
  });

  test('关闭自动登录时不提交密码，保留实际路线并记录读取失败', () async {
    final backend = _Backend();
    final controller = await start(backend, automatic: false);
    await expectLater(
      controller.campusAccountService!.networkUsage(),
      throwsA(isA<UiError>()),
    );
    expect(backend.loginRoutes, isEmpty);
    final error = controller.diagnostics.records.single;
    expect(error.code, UbaaErrorCode.authenticationRequired);
    expect(error.route, ConnectionMode.direct);
  });

  test('网络失败不触发认证，错误进入诊断且不保存上游正文', () async {
    final backend = _Backend()
      ..failure = const UiError(
        code: UbaaErrorCode.networkError,
        title: '合成',
        message: '禁止进入诊断的原始正文',
      );
    final controller = await start(backend);
    await expectLater(
      controller.campusAccountService!.metrics(),
      throwsA(isA<UiError>()),
    );
    expect(backend.targets, isEmpty);
    expect(backend.loginRoutes, isEmpty);
    expect(
      controller.diagnostics.records.single.code,
      UbaaErrorCode.networkError,
    );
    expect(controller.exportDiagnostics(), isNot(contains('禁止进入诊断的原始正文')));
  });

  test('恢复完成后读取仍失败时只尝试一次并记录最终错误', () async {
    final backend = _Backend()..alwaysExpired = true;
    final controller = await start(backend);
    await expectLater(
      controller.campusAccountService!.metrics(),
      throwsA(isA<UiError>()),
    );
    expect(backend.loginRoutes, [ConnectionMode.direct]);
    expect(backend.metricsReads, 2);
    expect(controller.diagnostics.records, hasLength(1));
  });

  test('凭据读取期间切换账号，旧服务不能补认证或污染诊断', () async {
    final backend = _Backend()..recoveryGate = Completer<void>();
    final controller = await start(backend);
    final pending = expectLater(
      controller.campusAccountService!.metrics(),
      throwsA(isA<UiError>()),
    );
    await backend.recoveryStarted.future.timeout(const Duration(seconds: 2));
    controller.setUsername('other-user');
    backend.recoveryGate!.complete();
    await pending;
    expect(backend.loginRoutes, isEmpty);
    expect(controller.diagnostics.records, isEmpty);
  });

  test('云盘首次读取与重新登录可补认证，写入准备失败不自动重放', () async {
    final backend = _Backend();
    final controller = await start(backend);
    await controller.bhpanService!.read(
      const BhpanRead(BhpanReadView.personalRoot),
    );
    expect(backend.targets, [RecoveryTarget.bhpan]);
    expect(backend.loginRoutes, [ConnectionMode.direct]);
    backend.ready = false;
    await controller.bhpanService!.login();
    expect(backend.loginRoutes, [ConnectionMode.direct, ConnectionMode.direct]);
    backend.ready = false;
    await expectLater(
      controller.bhpanService!.prepare(
        const BhpanMutation(BhpanMutationKind.recycle, target: 'synthetic'),
      ),
      throwsA(isA<UiError>()),
    );
    expect(backend.disk.prepares, 1);
    expect(backend.loginRoutes, hasLength(2));
  });
}

class _Backend extends support.FakeRecoveryBackend
    implements
        CampusAccountBackend,
        CampusAccountService,
        BhpanProvider,
        RequiredTargetSessionBackend {
  bool ready = false, alwaysExpired = false;
  ConnectionMode route = ConnectionMode.direct;
  BackendException? recoveryFailure;
  UiError? failure, metricError;
  int metricsReads = 0, networkReads = 0;
  final targets = <RecoveryTarget>[], loginRoutes = <ConnectionMode>[];
  Completer<void>? recoveryGate;
  final recoveryStarted = Completer<void>();
  late final disk = _Disk(this);
  @override
  CampusAccountService get campusAccount => this;
  @override
  BhpanService get bhpan => disk;
  @override
  Future<CampusAccountSnapshot> cached() async => const CampusAccountSnapshot();
  void check() {
    if (failure != null) throw failure!;
    if (!ready || alwaysExpired) throw expired;
  }

  @override
  Future<PortalIdentity> identity() async {
    check();
    return PortalIdentity(
      identity: '学生',
      department: '合成学院',
      fetchedAt: DateTime.utc(2026),
    );
  }

  @override
  Future<CampusMetrics> metrics() async {
    metricsReads++;
    if (metricError case final error?) {
      return CampusMetrics(
        networkBalance: CampusMetricFailure(
          error.message,
          error: error,
          fetchedAt: DateTime.utc(2026),
        ),
        cardBalance: CampusMetricValue(
          const CampusAmount(value: '1', unit: '元'),
          fetchedAt: DateTime.utc(2026),
        ),
        unreadMail: null,
        borrowedBooks: null,
        cloudStorageRemaining: null,
      );
    }
    check();
    return const CampusMetrics(
      networkBalance: null,
      cardBalance: null,
      unreadMail: null,
      borrowedBooks: null,
      cloudStorageRemaining: null,
    );
  }

  @override
  Future<NetworkUsage> networkUsage() async {
    networkReads++;
    check();
    return NetworkUsage(products: const [], fetchedAt: DateTime.utc(2026));
  }

  @override
  Future<RecoveredRouteSession> recoverTargetSession(
    RecoveryTarget target,
  ) async {
    targets.add(target);
    if (recoveryFailure != null) throw recoveryFailure!;
    if (!recoveryStarted.isCompleted) recoveryStarted.complete();
    await recoveryGate?.future;
    if (!ready)
      throw BackendException(
        UbaaErrorCode.authenticationRequired,
        resolvedRoute: route,
      );
    return RecoveredRouteSession(
      route: ConnectionMode.direct,
      profile: UserSummary(username: username),
    );
  }

  @override
  Future<RecoveredRouteSession> recoverRequiredSession(FeatureId feature) =>
      recoverTargetSession(RecoveryTarget.fromFeature(feature));
  @override
  Future<RecoveredRouteSession> loginRequiredRoute(
    ConnectionMode route,
    LoginInput input,
  ) async {
    loginRoutes.add(route);
    ready = true;
    failure = null;
    metricError = null;
    return RecoveredRouteSession(
      route: route,
      profile: UserSummary(username: username),
    );
  }
}

class _Disk implements BhpanService {
  _Disk(this.backend);
  final _Backend backend;
  int prepares = 0;
  @override
  Future<void> login() async => backend.check();
  @override
  Future<BhpanPage> read(BhpanRead query) async {
    backend.check();
    return BhpanPage(
      items: const [],
      range: BhpanListRange.unknown,
      route: ConnectionMode.direct,
      fetchedAt: DateTime.utc(2026),
    );
  }

  @override
  Future<WriteIntent> prepare(BhpanMutation request) async {
    prepares++;
    backend.check();
    throw StateError('测试不提交写入');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
