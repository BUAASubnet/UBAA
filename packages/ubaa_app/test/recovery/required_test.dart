import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_app/runtime.dart'
    show RecoveryScope, RecoveryInterrupted, RecoveryStopReason;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/recovery.dart' as support;

void main() {
  test('legacy authStatus 挂起时切号，不提交保存账号的密码（基线既有缺口）', () async {
    final backend = support.FakeRecoveryBackend();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
      credentialVault: MemoryCredentialVault(
        initial: const Credential(
          username: 'fixture-user',
          password: 'synthetic',
          autoLogin: true,
        ),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.setAutoLogin(true);
    backend.gate = Completer<AuthStatus>();
    final calls = backend.authCalls;
    final recovering = controller.recoverSession(refreshHomeAfter: false);
    await Future<void>.delayed(Duration.zero);
    expect(backend.authCalls, calls + 1);
    controller.setUsername('other-user');
    backend.gate!.complete(AuthStatus.signedOut);
    await recovering;
    expect(backend.loginCalls, 0);
    expect(controller.loginForm.username, 'other-user');
  });
  for (final option in ['autoLogin', 'rememberPassword']) {
    test('legacy 凭据挂起后关闭 $option 撤销旧许可', () async {
      final backend = support.FakeRecoveryBackend()..signedIn = false;
      final entered = Completer<void>(), gate = Completer<Credential?>();
      var armed = false;
      final controller = AppController(
        backend: backend,
        localAccountStore: await support.savedAccounts(),
        credentialVault: CallbackCredentialVault(
          loader: () {
            if (!armed) return Future.value(null);
            if (!entered.isCompleted) entered.complete();
            return gate.future;
          },
          saver: (_) async {},
          clearer: () async {},
        ),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.setAutoLogin(true);
      armed = true;
      final recovering = controller.recoverSession(refreshHomeAfter: false);
      await entered.future;
      if (option == 'autoLogin')
        controller.setAutoLogin(false);
      else
        controller.setRememberPassword(false);
      gate.complete(
        const Credential(
          username: 'fixture-user',
          password: 'synthetic',
          autoLogin: true,
        ),
      );
      await recovering;
      expect(backend.loginCalls, 0);
    });
  }
  test('替换后端关闭并移除旧恢复服务，继任服务可用', () async {
    final first = _Backend(), next = _Backend();
    final controller = AppController(
      backend: first,
      backendFactory: () => next,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession(refreshHomeAfter: false);
    final old = controller.internalRequiredRecoveryServices[first]!;
    await controller.rebuildBackend();
    expect(
      controller.internalRequiredRecoveryServices.containsKey(first),
      isFalse,
    );
    await expectLater(
      old.ensureRequiredSession(
        feature: FeatureId.schedule,
        scope: RecoveryScope(
          accountAlias: 'synthetic',
          expectedUsername: 'fixture-user',
          accountGeneration: 1,
          routeGeneration: 1,
          backendGeneration: 1,
          credentialGeneration: 1,
          routePolicy: RoutePolicy.direct,
          allowAutomaticLogin: false,
          isCurrent: () => true,
        ),
        deadline: DateTime.now().add(const Duration(seconds: 1)),
      ),
      throwsA(
        isA<RecoveryInterrupted>().having(
          (e) => e.reason,
          '已关闭',
          RecoveryStopReason.closed,
        ),
      ),
    );
    await controller.recoverSession(refreshHomeAfter: false);
    expect(next.features, isNotEmpty);
  });
  for (final change in [
    'route',
    'autoLogin',
    'autoLoginDefault',
    'rememberPassword',
  ]) {
    test('凭据挂起后修改 $change，旧恢复不登录且不覆盖新界面', () async {
      final backend = _Backend()
        ..requiredError = const BackendException(
          UbaaErrorCode.authenticationRequired,
          resolvedRoute: ConnectionMode.direct,
        );
      final entered = Completer<void>(), gate = Completer<Credential?>();
      var armed = false;
      final vault = CallbackCredentialVault(
        loader: () {
          if (!armed) return Future.value(null);
          if (!entered.isCompleted) entered.complete();
          return gate.future;
        },
        saver: (_) async {},
        clearer: () async {},
      );
      final controller = AppController(
        backend: backend,
        localAccountStore: await support.savedAccounts(),
        credentialVault: vault,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      if (change != 'autoLoginDefault') controller.setAutoLogin(true);
      armed = true;
      final recovering = controller.recoverSession(refreshHomeAfter: false);
      await entered.future;
      if (change == 'route')
        await controller.setRoutePolicy(RoutePolicy.webvpn);
      if (change.startsWith('autoLogin')) controller.setAutoLogin(false);
      if (change == 'rememberPassword') controller.setRememberPassword(false);
      gate.complete(
        const Credential(
          username: 'fixture-user',
          password: 'synthetic',
          autoLogin: true,
        ),
      );
      await recovering;
      expect(backend.loginRoutes, isEmpty);
      expect(
        controller.sessionRecoveryStatus,
        isNot(SessionRecoveryStatus.needsLogin),
      );
      if (change == 'route')
        expect(controller.loginForm.routePolicy, RoutePolicy.webvpn);
      else {
        await controller.recoverSession(
          feature: FeatureId.signin,
          refreshHomeAfter: false,
        );
        expect(backend.loginRoutes, isEmpty);
      }
    });
  }
  test('恢复读取凭据挂起时销毁，消费者及时结束且迟到材料不登录', () async {
    final backend = _Backend()
      ..requiredError = const BackendException(
        UbaaErrorCode.authenticationRequired,
        resolvedRoute: ConnectionMode.direct,
      );
    final gate = Completer<Credential?>();
    final entered = Completer<void>();
    var armed = false;
    final vault = CallbackCredentialVault(
      loader: () {
        if (!armed) return Future.value(null);
        if (!entered.isCompleted) entered.complete();
        return gate.future;
      },
      saver: (_) async {},
      clearer: () async {},
    );
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
      credentialVault: vault,
    );
    await controller.initialize();
    armed = true;
    final recovering = controller.recoverSession();
    await entered.future;
    controller.dispose();
    try {
      await recovering.timeout(const Duration(milliseconds: 500));
    } finally {
      gate.complete(
        const Credential(
          username: 'fixture-user',
          password: 'synthetic',
          autoLogin: true,
        ),
      );
      await recovering;
    }
    expect(backend.loginRoutes, isEmpty);
  });
  test('首页恢复只调用所需路线合同，直接使用已验证身份而不再双路线校验', () async {
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession();
    await backend.firstStarted.future;
    expect(backend.features, [FeatureId.schedule]);
    expect(backend.authCalls, 0);
    expect(backend.profileCalls, 0);
    expect(controller.recoveredRoute, ConnectionMode.direct);
    expect(controller.user?.username, 'fixture-user');
  });
  test('首页恢复期间的显式查询不会被随后默认刷新覆盖', () async {
    final backend = _QueryBackend()..firstGate = Completer<void>();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final recovering = controller.recoverSession();
    final reading = controller.refreshFeatureQuery(
      FeatureId.schedule,
      const FeatureQuery(
        view: FeatureQueryView.scheduleWeek,
        term: 'synthetic',
        week: 3,
      ),
    );
    backend.firstGate!.complete();
    await Future.wait([recovering, reading]);
    expect(
      controller.snapshots[FeatureId.schedule]!.details.single.title,
      '用户当前查询',
    );
    expect(
      controller.snapshots[FeatureId.schedule]!.readContext?.query?.week,
      3,
    );
    expect(controller.homeSnapshots[FeatureId.schedule]!.details, isEmpty);
  });
  test('目标恢复失败保留具体错误和路线，不提交密码也不改写成普通网络错误', () async {
    final backend = _QueryBackend()
      ..requiredError = const BackendException(
        UbaaErrorCode.timeout,
        kind: UbaaErrorKind.network,
        retryable: true,
        resolvedRoute: ConnectionMode.webvpn,
      );
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
      credentialVault: MemoryCredentialVault(
        initial: const Credential(
          username: 'fixture-user',
          password: 'synthetic',
          autoLogin: true,
        ),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.refreshFeatureQuery(
      FeatureId.signin,
      const FeatureQuery(),
    );
    final error = controller.snapshots[FeatureId.signin]!.error!;
    expect(error.code, UbaaErrorCode.timeout);
    expect(error.kind, UbaaErrorKind.network);
    expect(error.resolvedRoute, ConnectionMode.webvpn);
    expect(backend.loginRoutes, isEmpty);
  });
  test('只有明确失效才把获准材料交给返回的目标路线', () async {
    final backend = _Backend()
      ..requiredError = const BackendException(
        UbaaErrorCode.authenticationRequired,
        resolvedRoute: ConnectionMode.webvpn,
      );
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
      credentialVault: MemoryCredentialVault(
        initial: const Credential(
          username: 'fixture-user',
          password: 'synthetic',
          autoLogin: true,
        ),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession();
    expect(backend.loginRoutes, [ConnectionMode.webvpn]);
    expect(backend.loginCalls, 0);
    expect(controller.recoveredRoute, ConnectionMode.webvpn);
  });
  for (final route in ConnectionMode.values) {
    test('登录遇上游异常后暂停本次自动提交，重启保留恢复许可 $route', () async {
      final backend = _Backend()
        ..requiredError = BackendException(
          UbaaErrorCode.authenticationRequired,
          resolvedRoute: route,
        )
        ..loginFailure = const BackendException(UbaaErrorCode.upstreamChanged);
      final accounts = await support.savedAccounts();
      const saved = Credential(
        username: 'fixture-user',
        password: 'synthetic',
        autoLogin: true,
      );
      final vault = MemoryCredentialVault(initial: saved);
      final controller = AppController(
        backend: backend,
        localAccountStore: accounts,
        credentialVault: vault,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.recoverSession();
      await controller.recoverSession(
        feature: FeatureId.signin,
        refreshHomeAfter: false,
      );
      expect(backend.loginRoutes, [route]);
      expect(
        controller.sessionRecoveryStatus,
        SessionRecoveryStatus.needsLogin,
      );
      expect((await accounts.read())!.canRestore, isTrue);
      expect(await vault.read(), saved);
      controller.dispose();

      final nextBackend = _Backend()..requiredError = backend.requiredError;
      final reopened = AppController(
        backend: nextBackend,
        localAccountStore: accounts,
        credentialVault: vault,
      );
      addTearDown(reopened.dispose);
      await reopened.initialize();
      expect(reopened.phase, AppPhase.home);
      await reopened.recoverSession(refreshHomeAfter: false);
      expect(nextBackend.loginRoutes, [route]);
      expect(reopened.sessionRecoveryStatus, SessionRecoveryStatus.ready);
    });
  }
  for (final saveFails in [false, true]) {
    test('手动更新材料保存失败=$saveFails 时不误解除旧材料的自动使用限制', () async {
      final backend = _Backend()
        ..requiredError = const BackendException(
          UbaaErrorCode.authenticationRequired,
          resolvedRoute: ConnectionMode.webvpn,
        )
        ..loginFailure = const BackendException(UbaaErrorCode.upstreamChanged);
      final vault = _UpdateVault(saveFails);
      final controller = AppController(
        backend: backend,
        localAccountStore: await support.savedAccounts(),
        credentialVault: vault,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.recoverSession();
      backend.loginFailure = null;
      controller.setUsername('fixture-user');
      controller.setPassword('synthetic-updated');
      controller.setRememberPassword(true);
      controller.setAutoLogin(true);
      await controller.submitLogin(preserveHome: true);
      await controller.recoverSession(
        feature: FeatureId.signin,
        refreshHomeAfter: false,
      );
      expect(backend.loginRoutes.length, saveFails ? 1 : 2);
    });
  }
  test('已有用户目标等待时，首次恢复不抢先发出首页整批读取', () async {
    final backend = _Backend()..firstGate = Completer<void>();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final first = controller.recoverSession();
    final urgent = controller.recoverSession(
      feature: FeatureId.signin,
      refreshHomeAfter: false,
    );
    backend.firstGate!.complete();
    await Future.wait([first, urgent]);
    await Future<void>.delayed(Duration.zero);
    expect(
      backend.events.indexOf('恢复signin'),
      lessThan(backend.events.indexOf('读取judge')),
    );
  });
  test('用户当前目标可提升已排队恢复，而不是重复创建或留在后台顺序', () async {
    final backend = _Backend()..firstGate = Completer<void>();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final first = controller.recoverSession();
    final older = controller.recoverSession(feature: FeatureId.judge);
    final background = controller.recoverSession(feature: FeatureId.spoc);
    final promoted = controller.recoverSession(
      feature: FeatureId.spoc,
      refreshHomeAfter: false,
    );
    expect(identical(background, promoted), isTrue);
    backend.firstGate!.complete();
    await Future.wait([first, older, promoted]);
    expect(backend.features, [
      FeatureId.schedule,
      FeatureId.spoc,
      FeatureId.judge,
    ]);
  });
  test('不同目标的恢复在已发送检查收尾后执行，同目标请求合并', () async {
    final backend = _Backend()..firstGate = Completer<void>();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final first = controller.recoverSession();
    final target = controller.recoverSession(
      feature: FeatureId.signin,
      refreshHomeAfter: false,
    );
    final sameTarget = controller.recoverSession(
      feature: FeatureId.signin,
      refreshHomeAfter: false,
    );
    expect(identical(target, sameTarget), isTrue);
    await backend.firstStarted.future;
    expect(backend.features, [FeatureId.schedule]);
    backend.firstGate!.complete();
    await Future.wait([first, target]);
    expect(backend.features, [FeatureId.schedule, FeatureId.signin]);
  });
}

class _Backend extends support.FakeRecoveryBackend
    implements RequiredSessionBackend {
  final features = <FeatureId>[];
  final events = <String>[];
  final firstStarted = Completer<void>();
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    events.add('读取${feature.name}');
    return super.loadFeature(feature);
  }

  final loginRoutes = <ConnectionMode>[];
  BackendException? requiredError;
  BackendException? loginFailure;
  Completer<void>? firstGate;
  int profileCalls = 0;
  @override
  Future<UserSummary?> userInfo() async {
    profileCalls++;
    return super.userInfo();
  }

  @override
  Future<RecoveredRouteSession> recoverRequiredSession(
    FeatureId feature,
  ) async {
    features.add(feature);
    if (!firstStarted.isCompleted) firstStarted.complete();
    events.add('恢复${feature.name}');
    if (features.length == 1) await firstGate?.future;
    if (requiredError case final error?) throw error;
    return const RecoveredRouteSession(
      route: ConnectionMode.direct,
      profile: UserSummary(username: 'fixture-user'),
    );
  }

  @override
  Future<RecoveredRouteSession> loginRequiredRoute(
    ConnectionMode route,
    LoginInput input,
  ) async {
    loginRoutes.add(route);
    if (loginFailure case final failure?) throw failure;
    return RecoveredRouteSession(
      route: route,
      profile: const UserSummary(username: 'fixture-user'),
    );
  }
}

class _QueryBackend extends _Backend implements FeatureQueryBackend {
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async =>
      const FeatureResult.success(details: [FeatureDetail(title: '用户当前查询')]);
}

class _UpdateVault extends MemoryCredentialVault {
  _UpdateVault(this.fail)
    : super(
        initial: const Credential(
          username: 'fixture-user',
          password: 'synthetic',
          autoLogin: true,
        ),
      );
  final bool fail;
  @override
  Future<void> save(Credential credential) async {
    if (fail)
      throw const CredentialVaultException(
        CredentialVaultErrorCode.storageFailure,
      );
    await super.save(credential);
  }
}
