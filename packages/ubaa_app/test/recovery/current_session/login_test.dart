import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/src/bridge/bridge_backend.dart';
import 'package:ubaa_app/src/contracts/session_recovery.dart';
import 'package:ubaa_app/src/controller/state/models.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/materials.dart';
import 'package:ubaa_test_support/recovery.dart';

import '../../support/bridge/fixtures.dart' show currentBridgeContractVersion;

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

  for (final entry in ['首页批次作废', '单功能路线设置', '专用服务目标校验']) {
    for (final retain in [false, true]) {
      test('第二轮 $entry 遇到已销毁后端，保留登录=$retain', () async {
        final replacement = _Backend()..signedIn = false;
        var created = 0;
        final fixture = await _login(
          rememberPassword: retain,
          backendFactory: () {
            created++;
            return replacement;
          },
        );
        final controller = fixture.controller;
        final old = fixture.backend;
        switch (entry) {
          case '首页批次作废':
            old.batchError = true;
            await controller.recoverSession();
            expect(old.targets, isEmpty);
          case '单功能路线设置':
            old.routeError = _disposed;
            await controller.recoverSession(refreshHomeAfter: false);
            expect(old.targets, isEmpty);
          case '专用服务目标校验':
            old.targetError = _disposed;
            var reads = 0;
            await expectLater(
              controller.internalReadService<int>(
                RecoveryTarget.bhpan,
                DiagnosticOperation.bhpanList,
                () async {
                  reads++;
                  throw const BackendException(
                    UbaaErrorCode.authenticationRequired,
                  );
                },
              ),
              throwsA(isA<UiError>()),
            );
            expect(old.serviceTargets, [RecoveryTarget.bhpan]);
            expect(reads, 1);
        }
        expect(created, 1);
        expect(controller.internalBackend, same(replacement));
        expect(controller.internalCurrentSessionGrant, isNull);
        expect(controller.phase, retain ? AppPhase.home : AppPhase.login);
        if (!retain) {
          expect(
            controller.sessionRecoveryStatus,
            SessionRecoveryStatus.needsLogin,
          );
          expect(replacement.targets, isEmpty);
          expect(replacement.authCalls, 0);
        } else if (entry != '专用服务目标校验') {
          expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.ready);
        }
      });
    }
  }

  test('第二轮 后台结束本次会话，回前台重建且不再调用旧后端', () async {
    final replacement = _Backend()..signedIn = false;
    final factoryStarted = Completer<void>();
    final fixture = await _login(
      backendFactory: () {
        factoryStarted.complete();
        return replacement;
      },
    );
    final controller = fixture.controller;
    fixture.backend.targetError = _disposed;
    final recovery = controller.recoverSession(refreshHomeAfter: false);
    controller.setAppForeground(false);
    await recovery;
    expect(controller.phase, AppPhase.login);
    expect(controller.internalCurrentSessionGrant, isNull);
    expect(factoryStarted.isCompleted, isFalse);
    final oldCalls = fixture.backend.calls;
    controller.setAppForeground(true);
    await factoryStarted.future.timeout(const Duration(seconds: 2));
    await controller.internalBackendRebuildCompletion?.future;
    expect(controller.internalBackend, same(replacement));
    expect(controller.phase, AppPhase.login);
    expect(fixture.backend.calls, oldCalls);
  });

  for (final interactive in [false, true]) {
    test('第二轮 工厂失败后重提登录使用新后端，交互式=$interactive', () async {
      final replacement = interactive ? _InteractiveBackend() : _Backend();
      replacement.signedIn = false;
      final original = interactive ? _InteractiveBackend() : _Backend();
      var attempts = 0;
      final fixture = await _login(
        original: original,
        backendFactory: () {
          if (++attempts <= 2) {
            throw const BackendException(UbaaErrorCode.internalError);
          }
          return replacement;
        },
      );
      final controller = fixture.controller;
      fixture.backend.targetError = _disposed;
      await controller.recoverSession(refreshHomeAfter: false);
      expect(attempts, 1);
      expect(controller.phase, AppPhase.login);
      expect(controller.internalCurrentSessionGrant, isNull);
      final oldCalls = fixture.backend.calls;
      controller.setPassword('fixture-secret');
      await controller.submitLogin();
      expect(attempts, 2);
      expect(controller.phase, AppPhase.login);
      expect(controller.error?.code, UbaaErrorCode.internalError);
      expect(fixture.backend.calls, oldCalls);
      controller.setPassword('fixture-secret');
      await controller.submitLogin();
      expect(attempts, 3);
      expect(controller.internalBackend, same(replacement));
      expect(controller.phase, AppPhase.home);
      expect(controller.user?.username, 'fixture-user');
      expect(fixture.backend.calls, oldCalls);
      expect(
        interactive
            ? (replacement as _InteractiveBackend).begins
            : replacement.loginCalls,
        1,
      );
    });
  }

  for (final cancel in [false, true]) {
    test('第二轮 原位换号撤销旧授权与交付，取消=$cancel', () async {
      final fixture = await _login(
        original: cancel ? _InteractiveBackend() : null,
      );
      final controller = fixture.controller;
      await controller.recoverSession(refreshHomeAfter: false);
      final oldScope = controller.internalSharedRecoveryScope!;
      final oldBinding = controller.internalCurrentSessionGrant!.binding;
      final backend = fixture.backend;
      controller.setUsername('other-fixture-user');
      controller.setPassword('other-fixture-secret');
      if (backend is _InteractiveBackend) {
        backend.waitForVerification = true;
      } else {
        backend.loginError = const BackendException(
          UbaaErrorCode.invalidCredentials,
        );
      }
      await controller.submitLogin(preserveHome: true);
      if (cancel) {
        expect(controller.loginVerification?.hasCaptcha, isTrue);
        controller.cancelLoginVerification();
      } else {
        expect(controller.error?.code, UbaaErrorCode.invalidCredentials);
      }
      expect(controller.phase, AppPhase.home);
      expect(controller.internalCurrentSessionGrant, isNull);
      expect(controller.internalSharedRecoveryScope, isNull);
      await expectLater(
        oldBinding.validate(),
        throwsA(isA<LocalAccountConflict>()),
      );
      await expectLater(
        oldScope.commitDelivery(() => fail('旧结果不得交付')),
        throwsA(_superseded),
      );
    });
  }

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
  _Backend? original,
}) async {
  final materials = syntheticMaterials(MemoryMaterials());
  await materials.probe();
  final accounts = SecureLocalAccountStore(materials);
  final vault = _Vault();
  final backend = (original ?? _Backend())..signedIn = false;
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
        RequiredTargetSessionBackend,
        HomeRecoveryBatchBackend,
        RouteSettingsBackend,
        ProgressiveReadBackend,
        SharedAccountBackend,
        WriteReadbackBackend {
  final targets = <FeatureId>[];
  final serviceTargets = <RecoveryTarget>[];
  final reads = <FeatureId>[];
  final started = Completer<void>();
  final release = Completer<void>();
  BackendException? targetError;
  BackendException? routeError;
  bool batchError = false;
  int routeReads = 0;
  int batchInvalidations = 0;
  int routeLogins = 0;
  int readbackReads = 0;
  bool paused = false;

  int get calls =>
      authCalls +
      loginCalls +
      readCalls +
      routeReads +
      batchInvalidations +
      targets.length +
      serviceTargets.length;

  @override
  Future<int> beginHomeRecoveryBatch() async => 0;

  @override
  Future<void> endHomeRecoveryBatch(int batch) async {}

  @override
  Future<void> invalidateHomeRecoveryBatch() async {
    batchInvalidations++;
    if (batchError) {
      final bridge = BridgeBackend(_DisposedBatchClient());
      await bridge.invalidateHomeRecoveryBatch();
    }
  }

  @override
  Future<BackendRouteSettings> routeSettings() async {
    routeReads++;
    if (routeError case final error?) throw error;
    return const BackendRouteSettings(
      defaultPolicy: RoutePolicy.auto,
      activeRoutes: [],
    );
  }

  @override
  Future<RecoveredRouteSession> recoverTargetSession(
    RecoveryTarget target,
  ) async {
    if (target.feature case final feature?)
      return recoverRequiredSession(feature);
    if (target == RecoveryTarget.connection) {
      return RecoveredRouteSession(
        route: ConnectionMode.direct,
        profile: UserSummary(username: username),
      );
    }
    serviceTargets.add(target);
    if (targetError case final error?) throw error;
    throw StateError('专用服务用例需要设置目标校验失败');
  }

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

const _disposed = BackendException(
  UbaaErrorCode.internalError,
  clientDisposed: true,
);

class _DisposedBatchClient implements BridgeClient {
  @override
  int contractVersion() => currentBridgeContractVersion;

  @override
  Future<void> invalidateReadRecoveryBatch() async => throw const BridgeError(
    code: BridgeErrorCode.clientDisposed,
    kind: BridgeErrorKind.internal,
    retryable: false,
    message: '合成的已销毁后端',
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InteractiveBackend extends _Backend implements InteractiveLoginBackend {
  int begins = 0;
  bool waitForVerification = false;

  @override
  int get calls => super.calls + begins;

  @override
  Future<LoginVerificationState> beginInteractiveLogin(LoginInput input) async {
    begins++;
    return LoginVerificationState(
      routes: [
        if (waitForVerification)
          LoginRouteVerification(
            route: ConnectionMode.direct,
            status: LoginRouteVerificationStatus.captchaRequired,
            frame: CaptchaPixelFrame(width: 1, height: 1, rgba: Uint8List(4)),
            validFor: const Duration(minutes: 1),
          )
        else
          const LoginRouteVerification(
            route: ConnectionMode.direct,
            status: LoginRouteVerificationStatus.ready,
          ),
      ],
    );
  }

  @override
  Future<InteractiveLoginCompletion> continueInteractiveLogin(
    ConnectionMode selectedRoute, {
    bool pinRoute = false,
  }) async {
    return InteractiveLoginCompletion(
      user: UserSummary(username: username),
      settings: await routeSettings(),
    );
  }

  @override
  void cancelInteractiveLogin() {}

  @override
  void discardInteractiveCaptcha(ConnectionMode route) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
