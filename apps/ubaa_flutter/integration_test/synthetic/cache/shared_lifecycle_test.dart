import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_platform/shared_accounts.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../../../../packages/ubaa_app/test/runtime/shared_recovery_probe.dart'
    as fixtures;
import '../../support/rust_library.dart';

AgendaTime get now =>
    AgendaTime(rfc3339: '2026-11-02T10:00:00+08:00', timezone: 'Asia/Shanghai');
AgendaDraft draft(String title) => AgendaDraft(
  content: AgendaContent(kind: AgendaKind.task, title: title, allDay: false),
  exdates: [],
);

/// 退出协议由 Rust Mock 验证；此原生用例只验证真实本机库与应用接线。
class _LocalOnlyLogoutClient implements BridgeClient {
  _LocalOnlyLogoutClient(this._delegate);
  final BridgeClient _delegate;
  int logoutCalls = 0;
  @override
  int contractVersion() => _delegate.contractVersion();
  @override
  Future<void> bindSharedAccount({required BridgeSharedAccount scope}) =>
      _delegate.bindSharedAccount(scope: scope);
  @override
  Future<void> logoutWithSharedAccount({
    required BridgeSharedAccount scope,
  }) async {
    logoutCalls++;
  }

  @override
  Future<void> dispose() => _delegate.dispose();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('本机退出用例不得触发其他客户端入口');
}

// 本文件的后端统一经过此工厂，未列入本机白名单的客户端 RPC 一律拒绝。
Future<BridgeBackend> _openLocalBackend(String directory) async =>
    BridgeBackend(
      _LocalOnlyLogoutClient(await BridgeClient.open(configDir: directory)),
      configDirectory: directory,
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('普通消费者关闭保留另一消费者的真实日程和缓存能力', (tester) async {
    await initializeRustLibrary();
    final root = await Directory.systemTemp.createTemp('ubaa-shared-close-');
    final accounts = await fixtures.openAccounts(root);
    await accounts.retain('synthetic-user', retainSession: true);
    final a = await _openLocalBackend(root.path),
        b = await _openLocalBackend(root.path);
    final one = AppController(backend: a, localAccountStore: accounts);
    final two = AppController(
      backend: b,
      localAccountStore: await fixtures.openAccounts(root),
    );
    try {
      await one.initialize();
      await two.initialize();
      await a.agenda.unsyncedCount();
      await b.agenda.unsyncedCount();
      final before = (await accounts.read())!;
      one.dispose();
      await a.dispose();
      final item = await b.agenda.create(draft('合成关闭后事项'), now);
      expect((await b.agenda.get(item.id))!.content.title, '合成关闭后事项');
      expect((await b.cacheUsage(accountId: before.account!.id)).entryCount, 0);
      expect((await accounts.read())!.generation, before.generation);
      expect((await accounts.read())!.canRestore, isTrue);
    } finally {
      one.dispose();
      two.dispose();
      await a.dispose();
      await b.dispose();
      await root.delete(recursive: true);
    }
  });
  testWidgets('显式全局退出后本进程也不能读取或重新打开旧缓存', (tester) async {
    await initializeRustLibrary();
    final root = await Directory.systemTemp.createTemp('ubaa-global-logout-');
    final accounts = await fixtures.openAccounts(root);
    final retained = await accounts.retain(
      'synthetic-user',
      retainSession: true,
    );
    final localClient = _LocalOnlyLogoutClient(
      await BridgeClient.open(configDir: root.path),
    );
    final backend = BridgeBackend(localClient, configDirectory: root.path);
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
    );
    try {
      await controller.initialize();
      await backend.agenda.unsyncedCount();
      await controller.logout();
      expect(localClient.logoutCalls, 1);
      // 生产远端入口不能透传给真实客户端；此断言不执行 delegate 的 HTTP。
      expect(() => localClient.logout(), throwsStateError);
      expect(() => localClient.prepareLogin(), throwsStateError);
      expect((await accounts.read())!.canRestore, isFalse);
      await expectLater(
        backend.readCachedHome(RoutePolicy.direct),
        throwsA(isA<BackendException>()),
      );
      final key = await accounts.cacheKey(retained.account!);
      try {
        await expectLater(
          backend.openOfflineAccount(retained.account!, key),
          throwsA(isA<BackendException>()),
        );
        final inspector = await BridgeOfflineCache.open(
          configDir: root.path,
          accountId: retained.account!.id,
          expectedIdentity: retained.account!.username,
          key: key,
        );
        try {
          await expectLater(
            backend.clearOrRebuildBusinessCache(
              account: retained.account!,
              key: key,
            ),
            throwsA(isA<BackendException>()),
          );
          // 旧调用不应实际清理库或推进缓存代次，独立句柄继续可读。
          expect((await inspector.usage()).entryCount, BigInt.zero);
        } finally {
          await inspector.close();
          inspector.dispose();
        }
      } finally {
        key.fillRange(0, key.length, 0);
      }
      final fresh = await accounts.retain(
        'synthetic-user',
        retainSession: true,
      );
      await expectLater(
        controller.logout(clearSavedCredential: true),
        throwsA(isA<Exception>()),
      );
      expect((await accounts.read())!.generation, fresh.generation);
      expect((await accounts.read())!.canRestore, isTrue);
    } finally {
      controller.dispose();
      await backend.dispose();
      await root.delete(recursive: true);
    }
  });
  testWidgets('Core事务已提交但共享身份随后撤销，交付拒绝且真实记录仍存在', (tester) async {
    await initializeRustLibrary();
    final root = await Directory.systemTemp.createTemp('ubaa-shared-delivery-');
    final accounts = await fixtures.openAccounts(root);
    final state = await accounts.retain('synthetic-user', retainSession: true);
    final binding = await accounts.bindSnapshot((await accounts.capture())!);
    final scope = await BridgeSharedAccount.capture(
      directory: binding.directory,
      generation: BigInt.from(binding.generation),
    );
    final handle = await BridgeAgendaStore.openShared(
      configDir: root.path,
      accountId: state.account!.id,
      scope: scope,
    );
    BridgeAgendaStore? inspect;
    try {
      final item = await handle.create(
        draft: BridgeAgendaDraft(
          content: const BridgeAgendaContent(
            kind: BridgeAgendaKind.task,
            title: '合成已提交事项',
            allDay: false,
          ),
          exdates: const [],
        ),
        now: const BridgeAgendaTime(
          rfc3339: '2026-11-02T10:00:00+08:00',
          timezone: 'Asia/Shanghai',
        ),
      );
      await (await fixtures.openAccounts(root)).signOut();
      var delivered = false;
      await expectLater(
        binding.commit(() {
          delivered = true;
        }),
        throwsA(isA<LocalAccountConflict>()),
      );
      expect(delivered, isFalse);
      inspect = await BridgeAgendaStore.open(
        configDir: root.path,
        accountId: state.account!.id,
      );
      expect((await inspect.get_(itemId: item.id))!.content.title, '合成已提交事项');
      expect(await inspect.unsyncedCount(), 1);
    } finally {
      handle.dispose();
      inspect?.dispose();
      scope.dispose();
      await root.delete(recursive: true);
    }
  });
  for (final action in ['退出', '切号', '退出重登', '撤销许可']) {
    testWidgets('外部$action后旧消费者不能提交真实日程事务', (tester) async {
      await initializeRustLibrary();
      final root = await Directory.systemTemp.createTemp('ubaa-shared-revoke-');
      final accounts = await fixtures.openAccounts(root);
      await accounts.retain('synthetic-user', retainSession: true);
      final backend = await _openLocalBackend(root.path);
      final controller = AppController(
        backend: backend,
        localAccountStore: accounts,
      );
      try {
        await controller.initialize();
        await backend.agenda.unsyncedCount();
        final external = await fixtures.openAccounts(root);
        if (action == '撤销许可') {
          await external.revokeIfCurrent((await external.capture())!);
        } else {
          await external.signOut();
        }
        if (action == '切号')
          await external.retain('synthetic-other', retainSession: true);
        if (action == '退出重登')
          await external.retain('synthetic-user', retainSession: true);
        await expectLater(
          backend.agenda.create(draft('禁止迟到事项'), now),
          throwsA(isA<AgendaException>()),
        );
      } finally {
        controller.dispose();
        await backend.dispose();
        await root.delete(recursive: true);
      }
    });
  }
}
