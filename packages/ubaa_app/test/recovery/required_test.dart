import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'startup_test.dart' as support;

void main() {
  test('首页恢复只调用所需路线合同，直接使用已验证身份而不再双路线校验', () async {
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession();
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
  test('登录遇未支持交互后其他目标不自动重复提交同一密码', () async {
    final backend = _Backend()
      ..requiredError = const BackendException(
        UbaaErrorCode.authenticationRequired,
        resolvedRoute: ConnectionMode.webvpn,
      )
      ..loginFailure = const BackendException(UbaaErrorCode.upstreamChanged);
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
    await controller.recoverSession(
      feature: FeatureId.signin,
      refreshHomeAfter: false,
    );
    expect(backend.loginRoutes, [ConnectionMode.webvpn]);
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.needsLogin);
  });
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
