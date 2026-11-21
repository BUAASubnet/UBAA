import 'package:flutter/material.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_platform/telemetry.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

import 'package:ubaa_test_support/privacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/ubaa_test_support.dart';

void main() {
  testWidgets('拒绝启动同意后保留凭据且不自动登录', (tester) async {
    final saved = Credential(
      username: 'fixture-account',
      password: 'fixture-password',
      autoLogin: true,
    );
    final vault = MemoryCredentialVault(initial: saved);
    final backend = _Backend();
    await tester.pumpWidget(
      UbaaAppHost(
        backend: backend,
        credentialVault: vault,
        preferenceValues: MemoryPreferenceValues(),
      ),
    );
    await tester.pumpAndSettle();
    expect(backend.logins, 0);
    await tester.tap(find.text('不同意'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);
    expect(backend.logins, 0);
    expect((await vault.read())?.password, saved.password);
    expect((await vault.read())?.autoLogin, isTrue);
  });

  testWidgets('旧版本重新询问，接受后继续自动登录并在重启时复用记录', (tester) async {
    final prefs = MemoryPreferenceValues();
    await prefs.write(
      acceptedPrivacyVersionKey,
      '${bundledPrivacyPolicy.version - 1}',
    );
    final vault = MemoryCredentialVault(
      initial: const Credential(
        username: 'fixture-account',
        password: 'fixture-password',
        autoLogin: true,
      ),
    );
    final backend = _Backend();
    await tester.pumpWidget(
      UbaaAppHost(
        backend: backend,
        credentialVault: vault,
        preferenceValues: prefs,
      ),
    );
    await tester.pumpAndSettle();
    expect(backend.logins, 0);
    expect(find.textContaining('同意后将开启产品改进统计'), findsNothing);
    await tester.tap(find.text('同意'));
    await tester.pumpAndSettle();
    expect(backend.logins, 1);
    expect(find.byType(UbaaMainShell), findsOneWidget);
    expect(
      await prefs.read(acceptedPrivacyVersionKey),
      '${bundledPrivacyPolicy.version}',
    );
    await tester.pumpWidget(const SizedBox());
    final restarted = _Backend();
    await tester.pumpWidget(
      UbaaAppHost(
        backend: restarted,
        credentialVault: vault,
        preferenceValues: prefs,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(restarted.logins, 1);
  });

  for (final initial in [
    AppServiceConsent.reconsentRequired,
    AppServiceConsent.basic,
  ]) {
    testWidgets('确认前不发应用服务请求或校验会话，确认后保持基础模式选择：$initial', (tester) async {
      final prefs = MemoryPreferenceValues();
      final backend = _ServiceBackend(initial);
      await tester.pumpWidget(
        UbaaAppHost(backend: backend, preferenceValues: prefs),
      );
      await tester.pumpAndSettle();
      expect(backend.authChecks, 0);
      expect(backend.calls, isEmpty);
      expect(find.byType(UbaaMainShell), findsNothing);
      await tester.pump(const Duration(minutes: 30));
      expect(backend.calls, isEmpty);
      await tester.tap(find.text('同意'));
      await tester.pumpAndSettle();
      expect(backend.authChecks, 1);
      expect(find.byType(UbaaMainShell), findsOneWidget);
      expect(
        await prefs.read(acceptedPrivacyVersionKey),
        '${bundledPrivacyPolicy.version}',
      );
      if (initial == AppServiceConsent.basic) {
        expect(backend.calls, isEmpty);
        expect(backend.consent, initial);
      } else {
        expect(backend.calls, containsAll(['同意', '启动配置', '记录', '上传']));
        expect(backend.consent, AppServiceConsent.agreed);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}

class _Backend extends DemoBackend {
  _Backend() : super(loginDelay: Duration.zero);

  int logins = 0;

  @override
  Future<void> login(LoginInput input) async {
    logins++;
    await super.login(input);
  }
}

class _ServiceBackend extends _Backend
    implements SavedSessionBackend, AppBootstrapBackend {
  _ServiceBackend(this.consent);

  AppServiceConsent consent;
  int authChecks = 0;
  bool enabled = false;
  final calls = <String>[];

  @override
  Future<bool> hasSavedSession() async => true;

  @override
  Future<AuthStatus> authStatus() async {
    authChecks++;
    return AuthStatus.signedIn;
  }

  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'fixture-account');

  @override
  Future<AppServiceView> appServiceState() async => AppServiceView(
    available: true,
    telemetryAllowed: true,
    consent: consent,
    policyVersion: bundledPrivacyPolicy.version,
    agreedPolicyVersion: consent == AppServiceConsent.agreed
        ? bundledPrivacyPolicy.version
        : null,
    telemetryEnabled: enabled,
    canErase: false,
    erase: AppServiceEraseStatus.idle,
  );

  @override
  Future<AppServiceView> agreeAppService() async {
    calls.add('同意');
    consent = AppServiceConsent.agreed;
    enabled = true;
    return appServiceState();
  }

  @override
  Future<void> refreshAppBootstrap({required bool force}) async =>
      calls.add('启动配置');

  @override
  Future<void> recordAppService(TelemetryRecord record) async {
    if (enabled) calls.add('记录');
  }

  @override
  Future<void> uploadAppService({required bool force}) async => calls.add('上传');

  @override
  Future<AppServiceView> setAppServiceTelemetry(bool enabled) async {
    this.enabled = enabled;
    return appServiceState();
  }

  @override
  Future<AppServiceView> enterBasicAppService() => throw UnimplementedError();

  @override
  Future<AppServiceEraseOutcome> eraseAppService() =>
      throw UnimplementedError();

  @override
  Future<AppServiceView> markAppAnnouncementRead(String id) =>
      throw UnimplementedError();

  @override
  Future<AppServiceView> dismissAppUpdateAvailable(String latestVersion) =>
      throw UnimplementedError();
}
