import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_test_support/ubaa_test_support.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  _registerRecoveryRegressions();

  test('取消记住密码时同时关闭自动登录', () async {
    final controller = AppController(
      backend: _LoginBackend(),
      credentialVault: MemoryCredentialVault(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    controller.setAutoLogin(true);
    expect(controller.loginForm.rememberPassword, isTrue);
    controller.setRememberPassword(false);

    expect(controller.loginForm.rememberPassword, isFalse);
    expect(controller.loginForm.autoLogin, isFalse);
  });

  test('记住密码但未开启自动登录时恢复遮罩输入且不发起认证', () async {
    final backend = _LoginBackend();
    final controller = AppController(
      backend: backend,
      credentialVault: MemoryCredentialVault(
        initial: const Credential(
          username: 'fixture-student',
          password: 'fixture-password',
        ),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    expect(backend.loginCalls, 0);
    expect(controller.phase, AppPhase.login);
    expect(controller.loginForm.username, 'fixture-student');
    expect(controller.loginForm.password, 'fixture-password');
    expect(controller.loginForm.rememberPassword, isTrue);
    expect(controller.loginForm.autoLogin, isFalse);
  });

  test('本地保存失败不撤销已经成功的登录并保留可解释反馈', () async {
    final backend = _LoginBackend();
    final vault = _FaultVault()..failSave = true;
    final controller = AppController(backend: backend, credentialVault: vault);
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.setUsername('fixture-student');
    controller.setPassword('fixture-password');
    controller.setRememberPassword(true);

    await controller.submitLogin();

    expect(backend.loginCalls, 1);
    expect(await backend.authStatus(), AuthStatus.signedIn);
    expect(controller.phase, AppPhase.home);
    expect(controller.user, isNotNull);
    expect(controller.loginForm.password, isEmpty);
    expect(controller.error, isNotNull);
    expect(vault.hasValue, isFalse);
  });

  test('退出清除失败仍清空用户和业务页面并如实报告持久化失败', () async {
    final backend = _LoginBackend();
    final vault = _FaultVault();
    final controller = AppController(backend: backend, credentialVault: vault);
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.setUsername('fixture-student');
    controller.setPassword('fixture-password');
    controller.setRememberPassword(true);
    await controller.submitLogin();
    await controller.refreshHome();
    expect(controller.phase, AppPhase.home);
    expect(controller.activeRoutes, <ConnectionMode>[ConnectionMode.direct]);
    expect(
      controller.homeSnapshots.values.any(
        (snapshot) => snapshot.status != FeatureLoadStatus.idle,
      ),
      isTrue,
    );
    expect(vault.hasValue, isTrue);
    vault.failClear = true;

    await expectLater(
      controller.logout(clearSavedCredential: true),
      throwsA(isA<CredentialVaultException>()),
    );

    expect(await backend.authStatus(), AuthStatus.signedOut);
    expect(controller.phase, AppPhase.login);
    expect(controller.user, isNull);
    expect(controller.loginForm.password, isEmpty);
    expect(controller.activeRoutes, isEmpty);
    expect(
      controller.snapshots.values.every(
        (snapshot) => snapshot.status == FeatureLoadStatus.idle,
      ),
      isTrue,
    );
    expect(
      controller.homeSnapshots.values.every(
        (snapshot) => snapshot.status == FeatureLoadStatus.idle,
      ),
      isTrue,
    );
    expect(vault.hasValue, isTrue);
  });

  test('认证失败且保险箱清除失败时仍退出忙碌状态并保留认证错误', () async {
    final backend = _LoginBackend()..rejectLogin = true;
    final vault = _FaultVault()..failClear = true;
    final controller = AppController(backend: backend, credentialVault: vault);
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.setUsername('fixture-student');
    controller.setPassword('fixture-password');

    await controller.submitLogin();

    expect(backend.loginCalls, 1);
    expect(controller.phase, AppPhase.login);
    expect(controller.error?.code, UbaaErrorCode.invalidCredentials);
    expect(controller.user, isNull);
  });

  test('退出并清除成功后不在登录页残留账号和自动登录选项', () async {
    final vault = _FaultVault();
    final controller = AppController(
      backend: _LoginBackend(),
      credentialVault: vault,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.setUsername('fixture-student');
    controller.setPassword('fixture-password');
    controller.setAutoLogin(true);
    await controller.submitLogin();

    await controller.logout(clearSavedCredential: true);

    expect(controller.phase, AppPhase.login);
    expect(vault.hasValue, isFalse);
    expect(controller.loginForm.username, isEmpty);
    expect(controller.loginForm.password, isEmpty);
    expect(controller.loginForm.rememberPassword, isFalse);
    expect(controller.loginForm.autoLogin, isFalse);
  });

  test('自动登录认证失败与本地删除失败分别记录且释放保存密码', () async {
    final backend = _LoginBackend()..rejectLogin = true;
    final vault = _FaultVault(initial: _savedAutomaticCredential)
      ..clearFailure = StateError('合成系统错误 fixture-secret');
    final controller = AppController(backend: backend, credentialVault: vault);
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.initialize();

    expect(backend.loginCalls, 1);
    expect(controller.phase, AppPhase.login);
    expect(controller.error?.code, UbaaErrorCode.invalidCredentials);
    expect(controller.loginForm.password, isEmpty);
    expect(controller.diagnostics.records, hasLength(2));
    expect(
      controller.diagnostics.records.map((record) => record.code),
      containsAll(<UbaaErrorCode>[
        UbaaErrorCode.invalidCredentials,
        UbaaErrorCode.internalError,
      ]),
    );
    expect(controller.exportDiagnostics(), isNot(contains('fixture-secret')));
    expect(controller.exportDiagnostics(), isNot(contains('合成系统错误')));
  });

  test('自动登录网络失败只尝试一次并释放表单密码且保留主动保存值', () async {
    final backend = _LoginBackend()..rejection = UbaaErrorCode.networkError;
    final vault = _FaultVault(initial: _savedAutomaticCredential);
    final controller = AppController(backend: backend, credentialVault: vault);
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.initialize();

    expect(backend.loginCalls, 1);
    expect(controller.phase, AppPhase.login);
    expect(controller.error?.code, UbaaErrorCode.networkError);
    expect(controller.loginForm.password, isEmpty);
    expect(vault.hasValue, isTrue);
    expect(vault.clearCount, 0);
  });

  test('迟到的已保存凭据不能覆盖用户新填写的账号密码或启动自动登录', () async {
    final backend = _LoginBackend();
    final vault = _DelayedReadVault();
    final controller = AppController(backend: backend, credentialVault: vault);
    addTearDown(controller.dispose);
    final initializing = controller.initialize();
    await vault.started.future;
    controller.setUsername('fixture-new-account');
    controller.setPassword('fixture-new-password');
    vault.release.complete(_savedAutomaticCredential);

    await initializing;

    expect(controller.phase, AppPhase.login);
    expect(controller.loginForm.username, 'fixture-new-account');
    expect(controller.loginForm.password, 'fixture-new-password');
    expect(controller.loginForm.autoLogin, isFalse);
    expect(backend.loginCalls, 0);
  });

  test('销毁后迟到的保险箱读取不能恢复表单或发起认证', () async {
    final backend = _LoginBackend();
    final vault = _DelayedReadVault();
    final controller = AppController(backend: backend, credentialVault: vault);
    final initializing = controller.initialize();
    await vault.started.future;
    controller.dispose();
    vault.release.complete(_savedAutomaticCredential);

    await initializing;

    expect(controller.loginForm.username, isEmpty);
    expect(controller.loginForm.password, isEmpty);
    expect(backend.loginCalls, 0);
  });

  test('保险箱不可用时不读取或恢复其内存凭据也不能开启保存选项', () async {
    final vault = _UnavailableVault(initial: _savedAutomaticCredential);
    final backend = _LoginBackend();
    final controller = AppController(backend: backend, credentialVault: vault);
    addTearDown(controller.dispose);

    await controller.initialize();
    controller.setRememberPassword(true);
    controller.setAutoLogin(true);

    expect(vault.loadCalls, 0);
    expect(controller.loginForm.username, isEmpty);
    expect(controller.loginForm.password, isEmpty);
    expect(controller.loginForm.rememberPassword, isFalse);
    expect(controller.loginForm.autoLogin, isFalse);
    expect(backend.loginCalls, 0);
  });

  test('更换已恢复凭据的账号时清除旧密码并要求重新输入', () async {
    final backend = _LoginBackend();
    final controller = AppController(
      backend: backend,
      credentialVault: _FaultVault(
        initial: _savedAutomaticCredential.copyWith(autoLogin: false),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.loginForm.password, isNotEmpty);

    controller.setUsername('fixture-new-account');
    await controller.submitLogin();

    expect(controller.loginForm.password, isEmpty);
    expect(controller.phase, AppPhase.login);
    expect(backend.loginCalls, 0);
    expect(controller.error?.code, UbaaErrorCode.invalidInput);
  });

  test('销毁时清理提交密码且迟到的认证失败不再删除保险箱', () async {
    final backend = _DelayedLoginBackend();
    final vault = _FaultVault();
    final controller = AppController(backend: backend, credentialVault: vault);
    await controller.initialize();
    controller.setUsername('fixture-student');
    controller.setPassword('fixture-password');
    final loggingIn = controller.submitLogin();
    await backend.started.future;
    controller.dispose();
    expect(controller.loginForm.password, isEmpty);
    backend.release.completeError(
      const BackendException(UbaaErrorCode.invalidCredentials),
    );

    await loggingIn;

    expect(controller.loginForm.password, isEmpty);
    expect(vault.clearCount, 0);
    expect(controller.user, isNull);
  });

  test('销毁后迟到的用户信息不能重新进入协调器', () async {
    final backend = _DelayedUserBackend();
    final controller = AppController(
      backend: backend,
      credentialVault: _FaultVault(),
    );
    await controller.initialize();
    controller.setUsername('fixture-student');
    controller.setPassword('fixture-password');
    final loggingIn = controller.submitLogin();
    await backend.started.future;
    controller.dispose();
    expect(controller.loginForm.password, isEmpty);
    backend.release.complete(const UserSummary(username: 'fixture-student'));

    await loggingIn;

    expect(controller.user, isNull);
    expect(controller.loginForm.password, isEmpty);
  });

  test('退出后的迟到登录结果不能恢复首页或保存凭据', () async {
    final backend = _DelayedLoginBackend();
    final vault = _FaultVault();
    final controller = AppController(backend: backend, credentialVault: vault);
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.setUsername('fixture-student');
    controller.setPassword('fixture-password');
    controller.setRememberPassword(true);
    final loggingIn = controller.submitLogin();
    await backend.started.future;

    await controller.logout(clearSavedCredential: true);
    backend.release.complete();
    await loggingIn;

    expect(controller.phase, AppPhase.login);
    expect(controller.user, isNull);
    expect(controller.loginForm.password, isEmpty);
    expect(vault.saveCount, 0);
    expect(vault.hasValue, isFalse);
  });

  test('退出清除等待已发起的保存结束且不会被迟到保存重新留下凭据', () async {
    final vault = _DelayedSaveVault();
    final controller = AppController(
      backend: _LoginBackend(),
      credentialVault: vault,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.setUsername('fixture-student');
    controller.setPassword('fixture-password');
    controller.setRememberPassword(true);
    final loggingIn = controller.submitLogin();
    await vault.started.future;

    final loggingOut = controller.logout(clearSavedCredential: true);
    await Future<void>.delayed(Duration.zero);
    vault.release.complete();
    await Future.wait(<Future<void>>[loggingIn, loggingOut]);

    expect(controller.phase, AppPhase.login);
    expect(controller.user, isNull);
    expect(controller.loginForm.username, isEmpty);
    expect(controller.loginForm.password, isEmpty);
    expect(vault.hasValue, isFalse);
  });
}

void _registerRecoveryRegressions() {
  for (final blockedStage in <String>['会话退出', '保险箱清除']) {
    test('R1：$blockedStage在途时后台重建不能取消已确认清除', () async {
      final state = _RecoveryState()..signedIn = true;
      final backend = _RecoveryBackend(state);
      final vault = _FaultVault(initial: _recoveryCredential);
      final gate = Completer<void>();
      if (blockedStage == '会话退出') {
        backend.logoutGate = gate;
      } else {
        vault.clearGate = gate;
      }
      var factories = 0;
      final controller = AppController(
        backend: backend,
        backendFactory: () {
          factories++;
          return _RecoveryBackend(state);
        },
        credentialVault: vault,
      );
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
        controller.dispose();
      });
      await controller.initialize();
      await controller.refreshHome();
      expect(controller.phase, AppPhase.home);
      expect(controller.activeRoutes, <ConnectionMode>[ConnectionMode.direct]);
      final loggingOut = controller.logout(clearSavedCredential: true);
      await (blockedStage == '会话退出'
          ? backend.logoutStarted.future
          : vault.clearStarted.future);

      final rebuilt = await controller.rebuildBackend();
      gate.complete();
      await loggingOut;

      expect(rebuilt, isFalse);
      expect(factories, 0);
      expect(vault.clearCount, 1);
      expect(vault.hasValue, isFalse);
      expect(controller.phase, AppPhase.login);
      expect(controller.user, isNull);
      expect(controller.loginForm.username, isEmpty);
      expect(controller.loginForm.password, isEmpty);
      expect(controller.activeRoutes, isEmpty);
      expect(
        <FeatureSnapshot>[
          ...controller.snapshots.values,
          ...controller.homeSnapshots.values,
        ].every((snapshot) => snapshot.status == FeatureLoadStatus.idle),
        isTrue,
      );
    });
  }

  test('R1：退出清除失败不能被后台重建吞掉且仍清空页面', () async {
    final state = _RecoveryState()..signedIn = true;
    final backend = _RecoveryBackend(state)..logoutGate = Completer<void>();
    final vault = _FaultVault(initial: _recoveryCredential)..failClear = true;
    final controller = AppController(
      backend: backend,
      backendFactory: () => _RecoveryBackend(state),
      credentialVault: vault,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final loggingOut = controller.logout(clearSavedCredential: true);
    await backend.logoutStarted.future;

    await controller.rebuildBackend();
    backend.logoutGate!.complete();
    await expectLater(loggingOut, throwsA(isA<CredentialVaultException>()));

    expect(controller.phase, AppPhase.login);
    expect(controller.user, isNull);
    expect(controller.loginForm.password, isEmpty);
    expect(vault.hasValue, isTrue);
    expect(
      controller.diagnostics.records.last.operation,
      DiagnosticOperation.logout,
    );
  });

  test('R1：重建已开始时退出清除等待替换完成并注销有效的新 backend', () async {
    final state = _RecoveryState()..signedIn = true;
    final first = _RecoveryBackend(state)..disposeGate = Completer<void>();
    final replacement = _RecoveryBackend(state);
    final vault = _FaultVault(initial: _recoveryCredential);
    final controller = AppController(
      backend: first,
      backendFactory: () => replacement,
      credentialVault: vault,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final rebuilding = controller.rebuildBackend();
    await first.disposeStarted.future;
    final loggingOut = controller.logout(clearSavedCredential: true);
    await Future<void>.delayed(Duration.zero);
    first.disposeGate!.complete();

    await rebuilding;
    await loggingOut;

    expect(first.logoutCalls, 0);
    expect(replacement.logoutCalls, 1);
    expect(state.signedIn, isFalse);
    expect(controller.phase, AppPhase.login);
    expect(controller.user, isNull);
    expect(vault.hasValue, isFalse);
  });

  test('R1：销毁取消尚未执行的清除时返回稳定失败而不宣称已删除', () async {
    final state = _RecoveryState()..signedIn = true;
    final backend = _RecoveryBackend(state)..logoutGate = Completer<void>();
    final vault = _FaultVault(initial: _recoveryCredential);
    final controller = AppController(backend: backend, credentialVault: vault);
    await controller.initialize();
    final loggingOut = controller.logout(clearSavedCredential: true);
    await backend.logoutStarted.future;
    controller.dispose();
    backend.logoutGate!.complete();

    await expectLater(loggingOut, throwsA(isA<CredentialVaultException>()));

    expect(vault.clearCount, 0);
    expect(vault.hasValue, isTrue);
    expect(controller.loginForm.password, isEmpty);
  });

  test('R2：账号已改填后开始的后台重建不能恢复旧账号或旧密码', () async {
    final state = _RecoveryState();
    final controller = AppController(
      backend: _RecoveryBackend(state),
      backendFactory: () => _RecoveryBackend(state),
      credentialVault: _FaultVault(initial: _recoveryCredential),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.setUsername('fixture-new-account');
    controller.setPassword('fixture-new-password');

    expect(await controller.rebuildBackend(), isTrue);

    expect(controller.loginForm.username, 'fixture-new-account');
    expect(controller.loginForm.password, isEmpty);
    expect(controller.phase, AppPhase.login);
    expect(state.loginCalls, 0);
  });

  test('R1：退出后后台恢复不接受注销失败留下的旧会话且仍可手动重登', () async {
    final state = _RecoveryState()
      ..signedIn = true
      ..failLogout = true;
    final controller = AppController(
      backend: _RecoveryBackend(state),
      backendFactory: () => _RecoveryBackend(state),
      credentialVault: _FaultVault(initial: _recoveryCredential),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await expectLater(
      controller.logout(clearSavedCredential: true),
      throwsStateError,
    );

    await controller.rebuildBackend();

    expect(controller.phase, AppPhase.login);
    expect(controller.user, isNull);
    expect(controller.loginForm.password, isEmpty);
    expect(controller.activeRoutes, isEmpty);
    controller.setUsername('fixture-new-account');
    controller.setPassword('fixture-new-password');
    await controller.submitLogin();
    await controller.rebuildBackend();

    expect(state.loginCalls, 1);
    expect(controller.phase, AppPhase.home);
  });

  test('R2：恢复会话期间改填账号后迟到的用户资料不能重新打开旧账号', () async {
    final state = _RecoveryState()..signedIn = true;
    final backend = _RecoveryBackend(state)..userGate = Completer<void>();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    final initializing = controller.initialize();
    await backend.userStarted.future;
    controller.setUsername('fixture-new-account');
    controller.setPassword('fixture-new-password');
    backend.userGate!.complete();

    await initializing;

    expect(controller.phase, AppPhase.login);
    expect(controller.user, isNull);
    expect(controller.loginForm.username, 'fixture-new-account');
    expect(controller.loginForm.password, 'fixture-new-password');
  });

  test('R2：尚未改填或提交的已保存手动账号仍可安全恢复', () async {
    final state = _RecoveryState();
    final controller = AppController(
      backend: _RecoveryBackend(state),
      backendFactory: () => _RecoveryBackend(state),
      credentialVault: _FaultVault(initial: _recoveryCredential),
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    await controller.rebuildBackend();

    expect(controller.loginForm.username, _recoveryCredential.username);
    expect(controller.loginForm.password, _recoveryCredential.password);
    expect(controller.phase, AppPhase.login);
    expect(state.loginCalls, 0);
  });

  for (final rejection in <UbaaErrorCode>[
    UbaaErrorCode.invalidCredentials,
    UbaaErrorCode.networkError,
  ]) {
    test('R3：自动认证 $rejection 后后台重建保留错误且只允许手动重试', () async {
      final state = _RecoveryState()..rejection = rejection;
      final vault = _FaultVault(
        initial: _recoveryCredential.copyWith(autoLogin: true),
      )..failClear = true;
      final controller = AppController(
        backend: _RecoveryBackend(state),
        backendFactory: () => _RecoveryBackend(state),
        credentialVault: vault,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final originalError = controller.error;
      expect(originalError?.code, rejection);

      await controller.rebuildBackend();
      await controller.rebuildBackend();

      expect(state.loginCalls, 1);
      expect(controller.error, same(originalError));
      expect(controller.phase, AppPhase.login);
      expect(controller.loginForm.password, isEmpty);
      expect(vault.hasValue, isTrue);
      state.rejection = null;
      controller.setPassword('fixture-corrected-password');
      await controller.submitLogin();

      expect(state.loginCalls, 2);
      expect(controller.phase, AppPhase.home);
      expect(controller.error, isNull);
      expect(controller.loginForm.password, isEmpty);
    });
  }
}

const _recoveryCredential = Credential(
  username: 'fixture-old-account',
  password: 'fixture-old-password',
);

const _savedAutomaticCredential = Credential(
  username: 'fixture-student',
  password: 'fixture-password',
  autoLogin: true,
);

class _LoginBackend extends DemoBackend implements RouteSettingsBackend {
  _LoginBackend() : super(loginDelay: Duration.zero);

  int loginCalls = 0;
  bool rejectLogin = false;
  UbaaErrorCode? rejection;

  @override
  Future<BackendRouteSettings> routeSettings() async => BackendRouteSettings(
    defaultPolicy: RoutePolicy.auto,
    activeRoutes: await authStatus() == AuthStatus.signedIn
        ? const <ConnectionMode>[ConnectionMode.direct]
        : const <ConnectionMode>[],
  );

  @override
  Future<void> login(LoginInput input) async {
    loginCalls++;
    if (rejectLogin) {
      throw const BackendException(UbaaErrorCode.invalidCredentials);
    }
    if (rejection case final code?) throw BackendException(code);
    await super.login(input);
  }
}

class _FaultVault extends MemoryCredentialVault {
  _FaultVault({super.initial});

  bool failSave = false;
  bool failClear = false;
  Object? clearFailure;
  final clearStarted = Completer<void>();
  Completer<void>? clearGate;

  @override
  Future<void> save(Credential credential) async {
    if (failSave) {
      throw const CredentialVaultException(
        CredentialVaultErrorCode.storageFailure,
      );
    }
    await super.save(credential);
  }

  @override
  Future<void> clear() async {
    if (!clearStarted.isCompleted) clearStarted.complete();
    await clearGate?.future;
    if (clearFailure case final failure?) throw failure;
    if (failClear) {
      throw const CredentialVaultException(
        CredentialVaultErrorCode.storageFailure,
      );
    }
    await super.clear();
  }
}

class _RecoveryState {
  bool signedIn = false;
  bool failLogout = false;
  int loginCalls = 0;
  UbaaErrorCode? rejection;
}

class _RecoveryBackend
    implements UbaaBackend, BackendLifecycle, RouteSettingsBackend {
  _RecoveryBackend(this.state);
  final _RecoveryState state;
  final logoutStarted = Completer<void>();
  final disposeStarted = Completer<void>();
  final userStarted = Completer<void>();
  Completer<void>? logoutGate;
  Completer<void>? disposeGate;
  Completer<void>? userGate;
  int logoutCalls = 0;
  bool disposed = false;

  @override
  Future<AuthStatus> authStatus() async =>
      state.signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;

  @override
  Future<UserSummary?> userInfo() async {
    if (!userStarted.isCompleted) userStarted.complete();
    await userGate?.future;
    return state.signedIn
        ? const UserSummary(
            username: 'fixture-old-account',
            displayName: '合成用户',
          )
        : null;
  }

  @override
  Future<BackendRouteSettings> routeSettings() async => BackendRouteSettings(
    defaultPolicy: RoutePolicy.auto,
    activeRoutes: state.signedIn
        ? const <ConnectionMode>[ConnectionMode.direct]
        : const <ConnectionMode>[],
  );

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {
    state.loginCalls++;
    if (state.rejection case final code?) throw BackendException(code);
    state.signedIn = true;
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    if (disposed) throw StateError('合成 backend 已释放');
    if (!logoutStarted.isCompleted) logoutStarted.complete();
    await logoutGate?.future;
    if (state.failLogout) throw StateError('合成注销失败');
    state.signedIn = false;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    if (!disposeStarted.isCompleted) disposeStarted.complete();
    await disposeGate?.future;
  }

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();
}

class _DelayedReadVault extends MemoryCredentialVault {
  final started = Completer<void>();
  final release = Completer<Credential?>();

  @override
  Future<Credential?> load() {
    started.complete();
    return release.future;
  }
}

class _UnavailableVault extends MemoryCredentialVault {
  _UnavailableVault({super.initial});
  int loadCalls = 0;

  @override
  bool get isAvailable => false;

  @override
  Future<Credential?> load() async {
    loadCalls++;
    return super.load();
  }
}

class _DelayedLoginBackend extends DemoBackend {
  _DelayedLoginBackend() : super(loginDelay: Duration.zero);
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> login(LoginInput input) async {
    started.complete();
    await release.future;
    await super.login(input);
  }
}

class _DelayedUserBackend extends DemoBackend {
  _DelayedUserBackend() : super(loginDelay: Duration.zero);
  final started = Completer<void>();
  final release = Completer<UserSummary?>();

  @override
  Future<UserSummary?> userInfo() {
    started.complete();
    return release.future;
  }
}

class _DelayedSaveVault extends MemoryCredentialVault {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> save(Credential credential) async {
    started.complete();
    await release.future;
    await super.save(credential);
  }
}
