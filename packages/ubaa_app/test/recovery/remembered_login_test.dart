import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/src/contracts/session_recovery.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/materials.dart';
import 'package:ubaa_test_support/recovery.dart';

void main() {
  for (final automatic in [false, true]) {
    for (final reopen in [false, true]) {
      test('普通退出后恢复保存的表单且等待手动登录：重启=$reopen 自动登录=$automatic', () async {
        final materials = syntheticMaterials(MemoryMaterials());
        await materials.probe();
        final accounts = SecureLocalAccountStore(materials);
        final vault = PlatformCredentialVault(
          store: MaterialCredentialStore(materials),
        );
        final backend = FakeRecoveryBackend();
        final controller = AppController(
          backend: backend,
          localAccountStore: accounts,
          credentialVault: vault,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        controller.setUsername('fixture-user');
        controller.setPassword('fixture-secret');
        controller.setRememberPassword(true);
        controller.setAutoLogin(automatic);
        await controller.submitLogin();
        expect(controller.phase, AppPhase.home);
        expect(controller.internalCurrentSessionGrant, isNull);
        final persistentScope = await RecoveryScope.capture(
          accounts: accounts,
          snapshot: controller.internalSharedAccountSnapshot,
          routeGeneration: 0,
          backendGeneration: 0,
          credentialGeneration: 0,
          routePolicy: RoutePolicy.auto,
          allowAutomaticLogin: automatic,
          isCurrent: () => true,
        );
        expect(persistentScope.isShared, isTrue);
        expect(persistentScope.sharedSnapshot?.state.canRestore, isTrue);
        await controller.logout();

        var login = controller;
        final restartedBackend = FakeRecoveryBackend();
        if (reopen) {
          controller.dispose();
          login = AppController(
            backend: restartedBackend,
            localAccountStore: accounts,
            credentialVault: vault,
          );
          addTearDown(login.dispose);
          await login.initialize();
        }
        expect(login.phase, AppPhase.login);
        expect(login.loginForm.username, 'fixture-user');
        expect(login.loginForm.password, 'fixture-secret');
        expect(login.loginForm.rememberPassword, isTrue);
        expect(login.loginForm.autoLogin, automatic);
        expect(backend.loginCalls, 1);
        expect(restartedBackend.loginCalls, 0);
        expect((await accounts.read())!.canRestore, isFalse);
      });
    }
  }
}
