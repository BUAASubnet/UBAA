import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_app/runtime.dart';
import 'package:ubaa_platform/shared_accounts.dart';
import 'package:ubaa_test_support/recovery.dart' as support;
import '../runtime/shared_recovery_probe.dart' as probe;
import '../runtime/session_recovery_probe.dart' show profile, saved, expired;

class _Backend extends support.FakeRecoveryBackend
    implements RequiredSessionBackend {
  _Backend(this.root) {
    username = profile.username;
  }
  final Directory root;
  bool rejected = false;
  int profileReads = 0;
  @override
  Future<UserSummary?> userInfo() async {
    profileReads++;
    return super.userInfo();
  }

  @override
  Future<RecoveredRouteSession> recoverRequiredSession(
    FeatureId feature,
  ) async {
    if (rejected) throw expired;
    return RecoveredRouteSession(
      route: ConnectionMode.direct,
      profile: UserSummary(username: profile.username, displayName: '合成待发布资料'),
    );
  }

  @override
  Future<RecoveredRouteSession> loginRequiredRoute(
    ConnectionMode route,
    LoginInput input,
  ) async {
    throw const BackendException(UbaaErrorCode.invalidCredentials);
  }
}

class _SettingsBackend extends _Backend implements RouteSettingsBackend {
  _SettingsBackend(super.root);
  int calls = 0;
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<BackendRouteSettings> routeSettings() async {
    calls++;
    if (calls == 3) {
      entered.complete();
      await release.future;
    }
    return const BackendRouteSettings(
      defaultPolicy: RoutePolicy.direct,
      activeRoutes: [ConnectionMode.direct],
    );
  }
}

class _PausingClear implements PlatformSecureCredentialStore {
  _PausingClear(this.delegate);
  final MaterialCredentialStore delegate;
  final entered = Completer<void>(), release = Completer<void>();
  @override
  bool get isAvailable => delegate.isAvailable;
  @override
  Future<Credential?> read(String namespace) => delegate.read(namespace);
  @override
  Future<void> write(String namespace, Credential credential) =>
      delegate.write(namespace, credential);
  int clearCalls = 0;
  @override
  Future<void> clear(String namespace) async {
    clearCalls++;
    entered.complete();
    await release.future;
    await delegate.clear(namespace);
  }
}

class _ScopedLogoutBackend extends _Backend
    implements SharedAccountBackend, SharedAccountLogoutBackend {
  _ScopedLogoutBackend(super.root, this.external);
  final SecureLocalAccountStore external;
  LocalAccountState? fresh;
  @override
  Future<void> bindSharedAccount(SharedAccountBinding binding) =>
      binding.validate();
  @override
  Future<void> logoutSharedAccount(
    SharedAccountBinding revoked, {
    required bool clearCache,
  }) async {
    await revoked.validate();
    // 模拟本次撤销后、凭据清理前另一进程完成同 alias 显式登录。
    fresh = await external.retain(profile.username, retainSession: true);
  }
}

void main() {
  test('退出凭据清理被新登录拒绝后，不得无归属执行本机偏好回调', () async {
    final root = await probe.fixture();
    final accounts = await probe.openAccounts(root);
    final external = await probe.openAccounts(root);
    final vault = MemoryCredentialVault(initial: saved);
    final backend = _ScopedLogoutBackend(root, external);
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
      credentialVault: vault,
    );
    var clears = 0;
    try {
      await controller.initialize();
      await expectLater(
        controller.logout(
          clearSavedCredential: true,
          clearLocalData: () async {
            clears++;
          },
        ),
        throwsA(isA<LocalAccountConflict>()),
      );
      expect(backend.fresh, isNotNull);
      expect(clears, 0);
      expect((await vault.read())!.password, saved.password);
      expect((await accounts.read())!.generation, backend.fresh!.generation);
      expect((await accounts.read())!.canRestore, isTrue);
    } finally {
      controller.dispose();
      await controller.internalDisposeBackendOnce(backend);
      await root.delete(recursive: true);
    }
  });

  test('共享后端没有所属快照时，退出不能撤销另一消费者的新登录', () async {
    final root = await probe.fixture();
    final accounts = await probe.openAccounts(root);
    final external = await probe.openAccounts(root);
    final vault = MemoryCredentialVault(initial: saved);
    final backend = _ScopedLogoutBackend(root, external);
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
      credentialVault: vault,
    );
    var clears = 0;
    try {
      // 未 initialize 的消费者没有所属快照，不能使用外部最新账号作为退出目标。
      final fresh = await external.retain(
        profile.username,
        retainSession: true,
      );
      await expectLater(
        controller.logout(
          clearSavedCredential: true,
          clearLocalData: () async {
            clears++;
          },
        ),
        throwsA(isA<LocalAccountConflict>()),
      );
      expect((await accounts.read())!.generation, fresh.generation);
      expect((await accounts.read())!.canRestore, isTrue);
      expect((await vault.read())!.password, saved.password);
      expect(clears, 0);
    } finally {
      controller.dispose();
      await controller.internalDisposeBackendOnce(backend);
      await root.delete(recursive: true);
    }
  });

  for (final action in ['退出', '退出重登', '切号', '撤销许可']) {
    test('最终路线设置 await 期间退出，外部操作=$action，旧恢复不得发布 ready', () async {
      final root = await probe.fixture();
      final accounts = await probe.openAccounts(root);
      final backend = _SettingsBackend(root);
      final controller = AppController(
        backend: backend,
        localAccountStore: accounts,
        credentialVault: MemoryCredentialVault(initial: saved),
      );
      try {
        await controller.initialize();
        final pending = controller.recoverSession(refreshHomeAfter: false);
        await backend.entered.future.timeout(const Duration(seconds: 5));
        final external = await probe.openAccounts(root);
        if (action == '撤销许可') {
          await external.revokeIfCurrent((await external.capture())!);
        } else {
          await external.signOut();
        }
        if (action == '退出重登')
          await external.retain(profile.username, retainSession: true);
        if (action == '切号')
          await external.retain('synthetic-other', retainSession: true);
        backend.release.complete();
        await pending;
        expect(
          await accounts.validate(controller.internalSharedAccountSnapshot!),
          isFalse,
        );
        expect(controller.user!.displayName, isNull);
        expect(backend.profileReads, 0);
        expect(backend.readCalls, 0);
        expect(
          controller.sessionRecoveryStatus,
          isNot(SessionRecoveryStatus.ready),
        );
      } finally {
        if (!backend.release.isCompleted) backend.release.complete();
        controller.dispose();
        await controller.internalDisposeBackendOnce(backend);
        await root.delete(recursive: true);
      }
    });
  }
  test('旧恢复被拒后的无条件清理不得删除同 alias 新登录材料或撤销其许可', () async {
    final root = await probe.fixture();
    final accounts = await probe.openAccounts(root);
    final store = _PausingClear(MaterialCredentialStore(accounts.materials));
    final vault = PlatformCredentialVault(store: store);
    await vault.write(saved);
    await accounts.retain(profile.username, retainSession: true);
    final backend = _Backend(root)..rejected = true;
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
      credentialVault: vault,
    );
    try {
      await controller.initialize();
      final pending = controller.recoverSession(refreshHomeAfter: false);
      await Future.any([
        store.entered.future,
        pending,
      ]).timeout(const Duration(seconds: 5));
      final external = await probe.openAccounts(root);
      final newStore = MaterialCredentialStore(external.materials);
      const namespace = 'com.buaa.ubaa.credentials.v1';
      await newStore.write(
        namespace,
        saved.copyWith(password: 'synthetic-new-only'),
      );
      final fresh = await external.retain(
        profile.username,
        retainSession: true,
      );
      expect(fresh.canRestore, isTrue);
      store.release.complete();
      await pending;
      final state = (await external.read())!;
      final present = await newStore.read(namespace) != null;
      expect(state.canRestore, isTrue);
      expect(present, isTrue);
      expect((await newStore.read(namespace))!.password, 'synthetic-new-only');
      expect(state.generation, fresh.generation);
      expect(store.clearCalls, 0);
    } finally {
      if (!store.release.isCompleted) store.release.complete();
      controller.dispose();
      await controller.internalDisposeBackendOnce(backend);
      await root.delete(recursive: true);
    }
  });
}
