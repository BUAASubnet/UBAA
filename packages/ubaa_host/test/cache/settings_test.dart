import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_test_support/ubaa_test_support.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('生产宿主把清理接到控制器并保留本机账号及已登录首页', (tester) async {
    final materials = SecureMaterialStore(transport: _Materials());
    await materials.probe();
    final accounts = SecureLocalAccountStore(materials);
    final account = await accounts.retain('synthetic', retainSession: true);
    final backend = _Backend();
    await tester.pumpWidget(
      UbaaAppHost(backend: backend, localAccountStore: accounts),
    );
    await tester.pumpAndSettle();
    var shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    expect(shell.cacheAccountId, account.account!.id);
    expect(shell.canClearBusinessCache, isTrue);
    final usage = await shell.onReadCacheUsage!(account.account!.id);
    expect(usage.entryCount, 1);
    await shell.onClearBusinessCache!(account.account!.id);
    await tester.pumpAndSettle();
    shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    expect(shell.businessCacheEpoch, 1);
    expect(shell.user!.username, 'synthetic');
    expect(shell.cacheAccountId, account.account!.id);
    expect((await accounts.read())!.canRestore, isTrue);
    expect(backend.cleared, 1);
    expect(backend.loggedOut, 0);
    await tester.pumpWidget(const SizedBox());
  });
}

class _Materials implements SecureMaterialTransport {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _Backend extends DemoBackend
    implements OfflineCacheBackend, CacheManagementBackend {
  int cleared = 0, loggedOut = 0;
  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;
  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'synthetic');
  @override
  Future<void> logout() async {
    loggedOut++;
  }

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();
  @override
  Future<void> openOfflineAccount(LocalAccount account, List<int> key) async {}
  @override
  Future<OfflineHomeRead> readCachedHome(RoutePolicy policy) async =>
      OfflineHomeRead([]);
  @override
  Future<void> deactivateOfflineAccount() async {}
  @override
  Future<void> clearOfflineAccount() async {}
  @override
  Future<CacheUsageSummary> cacheUsage({required String accountId}) async =>
      CacheUsageSummary(
        accountId: accountId,
        entryCount: 1,
        contentBytes: 100,
        databaseBytes: 4096,
        reusableBytes: 0,
        softLimitBytes: 50 * 1024 * 1024,
        hardLimitBytes: 100 * 1024 * 1024,
      );
  @override
  Future<CacheClearOutcome> clearBusinessCache({
    required String accountId,
  }) async {
    cleared++;
    return const CacheClearOutcome(compacted: true);
  }
}

/// 原生检查使用相同明确合成backend，保持界面供人工/工具复核。
Future<Widget> buildSyntheticCacheInspection() async {
  final materials = SecureMaterialStore(transport: _Materials());
  await materials.probe();
  final accounts = SecureLocalAccountStore(materials);
  await accounts.retain('synthetic', retainSession: true);
  return UbaaAppHost(backend: _Backend(), localAccountStore: accounts);
}
