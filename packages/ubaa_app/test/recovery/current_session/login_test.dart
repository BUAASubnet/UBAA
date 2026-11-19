import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/src/contracts/session_recovery.dart';
import 'package:ubaa_app/src/controller/state/models.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/materials.dart';
import 'package:ubaa_test_support/recovery.dart';

void main() {
  test('D1 不记住密码的手动登录可以刷新完整首页', () async {
    final fixture = await _login();
    final controller = fixture.controller;
    await controller.refreshHome();
    for (final feature in controllerHomeDefaultFeatures) {
      final snapshot = controller.homeSnapshots[feature];
      expect(snapshot?.error, isNull, reason: feature.name);
      expect(snapshot?.updatedAt, isNotNull, reason: feature.name);
      expect(fixture.backend.reads, contains(feature));
      await controller.internalEnsureReadTarget(feature, force: true);
      expect(
        controller.recoveryStatusFor(feature),
        SessionRecoveryStatus.ready,
      );
      expect(fixture.backend.targets, contains(feature));
    }
    expect((await fixture.accounts.read())!.canRestore, isFalse);
    expect(await fixture.vault.read(), isNull);
    expect(fixture.backend.routeLogins, 0);
  });

  for (final saved in [false, true]) {
    test('D2 当前会话失效要求手动登录，凭据库已补写=$saved', () async {
      final fixture = await _login();
      final before = (await fixture.accounts.read())!.generation;
      if (saved) {
        await fixture.vault.write(
          const Credential(
            username: 'fixture-user',
            password: 'fixture-secret',
            autoLogin: true,
          ),
        );
      }
      final credentialReads = fixture.vault.reads;
      fixture.backend.targetError = const BackendException(
        UbaaErrorCode.authenticationRequired,
        resolvedRoute: ConnectionMode.direct,
      );
      await fixture.controller.refreshHome(only: [FeatureId.spoc]);
      expect(fixture.backend.targets, [FeatureId.spoc]);
      expect(
        fixture.controller.recoveryStatusFor(FeatureId.spoc),
        SessionRecoveryStatus.needsLogin,
      );
      expect(fixture.backend.routeLogins, 0);
      expect(fixture.vault.reads, credentialReads);
      expect((await fixture.accounts.read())!.generation, before);
    });
  }

  test('D3 退出期间挂起的校验不得交付，之后直接要求登录', () async {
    final fixture = await _login();
    final controller = fixture.controller;
    final result = fixture.pauseTarget();
    final interrupted = expectLater(result, throwsA(_superseded));
    await fixture.backend.started.future;
    final logout = controller.logout();
    expect(controller.internalCurrentSessionGrant, isNull);
    fixture.backend.release.complete();
    await logout;
    await interrupted;
    await expectLater(
      controller.internalEnsureReadTarget(FeatureId.spoc, force: true),
      throwsA(
        isA<BackendException>().having(
          (e) => e.code,
          '错误码',
          UbaaErrorCode.authenticationRequired,
        ),
      ),
    );
    expect(fixture.backend.targets, [FeatureId.spoc]);
  }, timeout: const Timeout(Duration(seconds: 5)));

  for (final switchAccount in [false, true]) {
    test('D4 其他账号索引实例作废在途校验，切换账号=$switchAccount', () async {
      final fixture = await _login();
      final result = fixture.pauseTarget();
      final interrupted = expectLater(result, throwsA(_superseded));
      await fixture.backend.started.future;
      final external = SecureLocalAccountStore(fixture.accounts.materials);
      if (switchAccount) {
        await external.retain('other-fixture-user', retainSession: true);
      } else {
        await external.signOut();
      }
      fixture.backend.release.complete();
      await interrupted;
    }, timeout: const Timeout(Duration(seconds: 5)));
  }

  test('D5 同一账号索引上的新控制器停在登录页', () async {
    final fixture = await _login();
    final backend = _Backend();
    final restarted = AppController(
      backend: backend,
      localAccountStore: fixture.accounts,
      credentialVault: fixture.vault,
    );
    addTearDown(restarted.dispose);
    await restarted.initialize();
    expect(restarted.phase, AppPhase.login);
    expect(backend.targets, isEmpty);
    expect(backend.loginCalls, 0);
  });

  test('D6 后端替换后不能使用显式登录取得的授权', () async {
    final replacement = _Backend()..signedIn = false;
    final fixture = await _login(backendFactory: () => replacement);
    final controller = fixture.controller;
    await controller.internalEnsureReadTarget(FeatureId.spoc, force: true);
    expect(fixture.backend.targets, [FeatureId.spoc]);
    expect(await controller.rebuildBackend(), isTrue);
    expect(controller.phase, AppPhase.login);
    expect(controller.internalCurrentSessionGrant, isNull);
    await expectLater(
      controller.internalEnsureReadTarget(FeatureId.spoc, force: true),
      throwsA(
        isA<BackendException>().having(
          (error) => error.code,
          '错误码',
          UbaaErrorCode.authenticationRequired,
        ),
      ),
    );
    expect(replacement.targets, isEmpty);
  });

  test('复审 B2 首页中的后端实例不匹配时拒绝当前会话授权', () async {
    final fixture = await _login();
    final controller = fixture.controller;
    controller.internalCurrentSessionGrant = CurrentSessionGrant(
      controller.internalCurrentSessionGrant!.binding,
      _Backend(),
    );
    expect(controller.phase, AppPhase.home);
    await expectLater(
      controller.internalRecoverTargetSession(
        fixture.backend,
        RecoveryTarget.fromFeature(FeatureId.spoc),
        controller.internalLifecycleEpoch,
        publishReusedSession: false,
      ),
      throwsA(_superseded),
    );
    expect(fixture.backend.targets, isEmpty);
  });

  test('复审 B3 原位换账号先清空旧授权，再授予新账号', () async {
    final fixture = await _login();
    final controller = fixture.controller;
    await controller.recoverSession(
      feature: FeatureId.spoc,
      refreshHomeAfter: false,
    );
    expect(controller.internalSharedRecoveryScope, isNotNull);
    final observed = <(CurrentSessionGrant?, RecoveryScope?)>[];
    controller.addListener(() {
      if (controller.user == null && controller.phase == AppPhase.home) {
        observed.add((
          controller.internalCurrentSessionGrant,
          controller.internalSharedRecoveryScope,
        ));
      }
    });
    fixture.backend.username = 'other-fixture-user';
    controller.setUsername('other-fixture-user');
    controller.setPassword('other-fixture-secret');
    await controller.submitLogin(preserveHome: true);
    expect(observed, isNotEmpty);
    expect(observed, everyElement((null, null)));
    expect(
      controller.internalCurrentSessionGrant!.binding.account.username,
      'other-fixture-user',
    );
  });

  test('复审 B4 控制器销毁时清空当前会话授权', () async {
    final fixture = await _login();
    await fixture.controller.recoverSession(refreshHomeAfter: false);
    expect(fixture.controller.internalCurrentSessionGrant, isNotNull);
    expect(fixture.controller.internalSharedRecoveryScope, isNotNull);
    fixture.controller.dispose();
    expect(fixture.controller.internalCurrentSessionGrant, isNull);
    expect(fixture.controller.internalSharedRecoveryScope, isNull);
  });

  test('复审 B1 当前会话后端销毁时清空授权并转到登录页', () async {
    final replacement = _Backend()..signedIn = false;
    var created = 0;
    final fixture = await _login(
      backendFactory: () {
        created++;
        return replacement;
      },
    );
    fixture.backend.targetError = const BackendException(
      UbaaErrorCode.internalError,
      clientDisposed: true,
    );
    final controller = fixture.controller;
    await controller.recoverSession(
      feature: FeatureId.spoc,
      refreshHomeAfter: false,
    );
    expect(controller.internalCurrentSessionGrant, isNull);
    expect(controller.internalSharedRecoveryScope, isNull);
    expect(controller.phase, AppPhase.login);
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.needsLogin);
    expect(controller.internalBackend, same(replacement));
    expect(created, 1);
    await controller.recoverSession(
      feature: FeatureId.spoc,
      refreshHomeAfter: false,
    );
    expect(fixture.backend.targets, [FeatureId.spoc]);
    expect(created, 1);
    expect(replacement.targets, isEmpty);
    expect(replacement.authCalls, 0);
  });

  test('复审 C 当前会话连续交付只读取一次本地写回提示', () async {
    final fixture = await _login();
    for (final feature in [FeatureId.spoc, FeatureId.signin]) {
      await fixture.controller.recoverSession(
        feature: feature,
        refreshHomeAfter: false,
      );
      await fixture.controller.internalWriteReadbackRead?.completion.future;
      expect(
        fixture.controller.recoveryStatusFor(feature),
        SessionRecoveryStatus.ready,
      );
    }
    expect(fixture.backend.targets, [FeatureId.spoc, FeatureId.signin]);
    expect(fixture.backend.readbackReads, 1);
  });

  test('D8 记住密码的手动登录沿用持久作用域', () async {
    final fixture = await _login(rememberPassword: true);
    final controller = fixture.controller;
    expect(controller.internalCurrentSessionGrant, isNull);
    final result = await controller.internalRecoverTargetSession(
      fixture.backend,
      RecoveryTarget.fromFeature(FeatureId.spoc),
      controller.internalLifecycleEpoch,
      publishReusedSession: false,
    );
    expect(result?.scope?.isShared, isTrue);
    expect(result?.scope?.sharedSnapshot?.state.canRestore, isTrue);
    expect(fixture.backend.targets, [FeatureId.spoc]);
  });
}

Matcher get _superseded => isA<RecoveryInterrupted>().having(
  (error) => error.reason,
  '中断原因',
  RecoveryStopReason.superseded,
);

Future<_Fixture> _login({
  UbaaBackend Function()? backendFactory,
  bool rememberPassword = false,
}) async {
  final materials = syntheticMaterials(MemoryMaterials());
  await materials.probe();
  final accounts = SecureLocalAccountStore(materials);
  final vault = _Vault();
  final backend = _Backend()..signedIn = false;
  final controller = _Controller(
    backend: backend,
    backendFactory: backendFactory,
    localAccountStore: accounts,
    credentialVault: vault,
  );
  addTearDown(controller.dispose);
  await controller.initialize();
  controller.setUsername('fixture-user');
  controller.setPassword('fixture-secret');
  controller.setRememberPassword(rememberPassword);
  expect(controller.loginForm.autoLogin, isFalse);
  await controller.submitLogin();
  controller.deferHomeRefresh = false;
  expect(controller.phase, AppPhase.home);
  return _Fixture(accounts, vault, backend, controller);
}

class _Controller extends AppController {
  _Controller({
    required super.backend,
    super.backendFactory,
    super.localAccountStore,
    super.credentialVault,
  });

  // 各用例自行决定何时开始首页读取，避免与登录完成时的预取并发。
  bool deferHomeRefresh = true;

  @override
  Future<void> internalRefreshHome({
    Iterable<FeatureId>? only,
    bool writeReadback = false,
    bool firstBatch = false,
  }) async {
    if (deferHomeRefresh) return;
    await super.internalRefreshHome(
      only: only,
      writeReadback: writeReadback,
      firstBatch: firstBatch,
    );
  }
}

class _Fixture {
  _Fixture(this.accounts, this.vault, this.backend, this.controller);
  final SecureLocalAccountStore accounts;
  final _Vault vault;
  final _Backend backend;
  final AppController controller;

  Future<RecoveryResult?> pauseTarget() {
    backend.paused = true;
    return controller.internalRecoverTargetSession(
      backend,
      RecoveryTarget.fromFeature(FeatureId.spoc),
      controller.internalLifecycleEpoch,
      publishReusedSession: false,
    );
  }
}

class _Vault extends MemoryCredentialVault {
  int reads = 0;
  @override
  Future<Credential?> read() {
    reads++;
    return super.read();
  }
}

class _Backend extends FakeRecoveryBackend
    implements
        RequiredSessionBackend,
        ProgressiveReadBackend,
        SharedAccountBackend,
        WriteReadbackBackend {
  final targets = <FeatureId>[];
  final reads = <FeatureId>[];
  final started = Completer<void>();
  final release = Completer<void>();
  BackendException? targetError;
  int routeLogins = 0;
  int readbackReads = 0;
  bool paused = false;

  @override
  Future<RecoveredRouteSession> recoverRequiredSession(
    FeatureId feature,
  ) async {
    targets.add(feature);
    if (paused) {
      started.complete();
      await release.future;
    }
    if (targetError case final error?) throw error;
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
    routeLogins++;
    throw StateError('当前会话不得再次登录');
  }

  @override
  Future<void> bindSharedAccount(SharedAccountBinding binding) =>
      binding.validate();

  @override
  Future<List<WriteReadbackHint>> readWriteReadbackHints({
    required String accountId,
  }) async {
    readbackReads++;
    return const [];
  }

  @override
  Future<void> dismissWriteReadbackHint(
    String id, {
    required String accountId,
  }) async {}

  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async => null;

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    reads.add(feature);
    return super.loadFeature(feature);
  }
}
