import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

/// 真实只读会话和独立原生密钥；计时从宿主装配开始，不冒充进程冷启动。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('真实只读缓存首页先于挂起恢复显示，放行后逐批原位更新', (tester) async {
    final config = Platform.environment['UBAA_CONFIG_DIR'];
    final scope = Platform.environment['UBAA_LIVE_MATERIAL_SCOPE'];
    const route = String.fromEnvironment('UBAA_EXPECTED_ROUTE');
    if (!const bool.fromEnvironment('UBAA_LIVE_READONLY') ||
        config == null ||
        !Directory(config).isAbsolute ||
        !config.contains('UBAA-ui-readonly-offline-') ||
        scope == null ||
        !RegExp(r'^offline-live-[a-f0-9]{32}$').hasMatch(scope) ||
        (route != 'direct' && route != 'webvpn')) {
      throw StateError('必须显式指定本轮私有目录、独立安全命名空间及只读路线');
    }
    await RustLib.init();
    final transport = _IsolatedMaterials(scope);
    final materials = SecureMaterialStore(transport: transport);
    final accounts = SecureLocalAccountStore(materials);
    BridgeBackend? seed;
    _ReadonlyBackend? backend;
    try {
      await materials.probe();
      expect(materials.isAvailable, isTrue);
      seed = await BridgeBackend.open(config);
      final recovered = await seed.recoverRequiredSession(FeatureId.schedule);
      expect(recovered.route.name, route);
      final identity = recovered.profile.username;
      if (identity.isEmpty) throw StateError('只读身份缺少可核对标识');
      final account = (await accounts.retain(
        identity,
        retainSession: true,
      )).account!;
      final key = await accounts.cacheKey(account);
      try {
        await seed.openOfflineAccount(account, key);
      } finally {
        key.fillRange(0, key.length, 0);
      }
      for (final feature in [FeatureId.schedule, FeatureId.spoc]) {
        final saved = await seed.loadFeature(feature);
        expect(saved.error, isNull);
        expect(saved.evidence?.savedForOffline, isTrue);
        debugPrint(
          '离线首页只读 seed=${feature.name} count=${saved.details.length} saved=true',
        );
      }
      await seed.dispose();
      seed = null;
      backend = _ReadonlyBackend(
        await BridgeClient.open(configDir: config),
        config,
      );
      final elapsed = backend.elapsed..start();
      await tester.pumpWidget(
        UbaaAppHost(
          backend: backend,
          localAccountStore: accounts,
          credentialVault: const NoopCredentialVault(),
        ),
      );
      Future<void> until(
        bool Function() ready,
        String reason, {
        Duration timeout = const Duration(minutes: 10),
      }) async {
        final deadline = DateTime.now().add(timeout);
        while (!ready() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(ready(), isTrue, reason: reason);
      }

      UbaaMainShell shell() =>
          tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
      await until(
        () => find.byType(UbaaMainShell).evaluate().isNotEmpty,
        '本机账号首页缺失',
      );
      final shellMs = elapsed.elapsedMilliseconds;
      await until(
        () =>
            shell().homeSnapshots![FeatureId.schedule]!.evidence?.origin ==
                DataOrigin.persisted &&
            shell().homeSnapshots![FeatureId.spoc]!.evidence?.origin ==
                DataOrigin.persisted,
        '认证挂起时本地课表和作业不可读',
      );
      final cachedMs = elapsed.elapsedMilliseconds;
      await until(
        () => backend!.recoveryCalls > 0,
        '首帧后恢复RPC未开始',
        timeout: const Duration(seconds: 3),
      );
      expect(backend.recoveryCalls, 1);
      final rail = find.byType(NavigationRail);
      if (rail.evaluate().isNotEmpty) {
        await tester.tap(
          find.descendant(of: rail, matching: find.byIcon(Icons.apps_outlined)),
        );
      } else {
        await tester.tap(find.byType(NavigationDestination).at(1));
      }
      await tester.pump(const Duration(milliseconds: 100));
      if (rail.evaluate().isNotEmpty) {
        expect(tester.widget<NavigationRail>(rail).selectedIndex, 1);
        await tester.tap(
          find.descendant(of: rail, matching: find.byIcon(Icons.home_outlined)),
        );
      } else {
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          1,
        );
        await tester.tap(find.byType(NavigationDestination).at(0));
      }
      await tester.pump(const Duration(milliseconds: 100));
      expect(backend.release.isCompleted, isFalse);
      debugPrint(
        '离线首页只读 route=$route shell_ms=$shellMs cached_ms=$cachedMs recovery_started_ms=${backend.recoveryStartedMs} held=true processCold=false',
      );
      backend.release.complete();
      const features = [
        FeatureId.schedule,
        FeatureId.signin,
        FeatureId.spoc,
        FeatureId.judge,
        FeatureId.ygdk,
      ];
      await until(
        () => features.every((feature) {
          final value = shell().homeSnapshots![feature]!;
          return value.status != FeatureLoadStatus.idle &&
              value.status != FeatureLoadStatus.loading;
        }),
        '五个首页来源未完成更新',
      );
      for (final feature in features) {
        final value = shell().homeSnapshots![feature]!;
        debugPrint(
          '离线首页只读 feature=${feature.name} state=${value.status.name} route=${value.resolvedRoute?.name} count=${value.details.length} error=${value.error?.code.name} origin=${value.evidence?.origin.name} complete=${value.evidence?.complete}',
        );
        expect(
          value.status == FeatureLoadStatus.success ||
              value.status == FeatureLoadStatus.empty,
          isTrue,
          reason: '首页来源未成功完成',
        );
        expect(value.resolvedRoute?.name, route);
      }
      final usage = await backend.cacheUsage(accountId: account.id);
      debugPrint(
        '离线首页只读 route=$route all_done_ms=${elapsed.elapsedMilliseconds} judge_first_batch_ms=${backend.firstJudgeMs} cache_entries=${usage.entryCount} cache_content_bytes=${usage.contentBytes} businessWrites=0 processCold=false',
      );
      expect(backend.commits, 0);
      for (final feature in [
        FeatureId.exam,
        FeatureId.grades,
        FeatureId.bykc,
        FeatureId.classroom,
        FeatureId.libbook,
        FeatureId.cgyy,
        FeatureId.evaluation,
      ]) {
        expect(shell().snapshots[feature]!.status, FeatureLoadStatus.idle);
      }
    } finally {
      if (backend != null && !backend.release.isCompleted) {
        backend.release.complete();
      }
      await tester.pumpWidget(const SizedBox());
      await backend?.dispose();
      await seed?.dispose();
      await transport.clearOwned();
    }
  }, timeout: const Timeout(Duration(minutes: 12)));
}

class _IsolatedMaterials implements SecureMaterialTransport {
  _IsolatedMaterials(this.scope);
  final String scope;
  final _transport = const PlatformSecureMaterialTransport();
  final _written = <String>{};
  String key(String value) => '$scope.$value';
  @override
  Future<String?> read(String value) => _transport.read(key(value));
  @override
  Future<void> write(String value, String body) async {
    _written.add(key(value));
    await _transport.write(key(value), body);
  }

  @override
  Future<void> delete(String value) => _transport.delete(key(value));
  Future<void> clearOwned() async {
    for (final value in _written) {
      await _transport.delete(value);
    }
  }
}

class _ReadonlyBackend extends BridgeBackend {
  _ReadonlyBackend(super.client, String config)
    : super(configDirectory: config);
  final release = Completer<void>();
  final elapsed = Stopwatch();
  int recoveryCalls = 0, commits = 0;
  int? recoveryStartedMs, firstJudgeMs;
  @override
  Future<RecoveredRouteSession> recoverRequiredSession(
    FeatureId feature,
  ) async {
    recoveryCalls++;
    recoveryStartedMs ??= elapsed.elapsedMilliseconds;
    await release.future;
    return super.recoverRequiredSession(feature);
  }

  @override
  Future<FeatureReadTask?> beginAccountFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
    LocalAccount account,
  ) async {
    final task = await super.beginAccountFeatureRead(feature, query, account);
    if (task == null) return null;
    return _ObservedTask(task, () {
      if (feature == FeatureId.judge) {
        firstJudgeMs ??= elapsed.elapsedMilliseconds;
      }
    });
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    commits++;
    throw StateError('真实只读验收禁止任何业务提交');
  }

  @override
  Future<WriteCommitResult> commitWriteWithCache(
    String intentId, {
    required String accountId,
  }) => commitWrite(intentId);
}

class _ObservedTask implements FeatureReadTask {
  _ObservedTask(this.task, this.onBatch);
  final FeatureReadTask task;
  final void Function() onBatch;
  @override
  Future<FeatureReadBatch> next() async {
    final result = await task.next();
    onBatch();
    return result;
  }

  @override
  void cancel() => task.cancel();
}
