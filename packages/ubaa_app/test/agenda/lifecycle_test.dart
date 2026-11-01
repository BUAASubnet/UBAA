import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/recovery.dart' as support;
import '../recovery/backend_rebuild/fakes.dart' as rebuild;

void main() {
  test('退出等待旧写入时安全索引先禁止恢复', () async {
    final accounts = _ObservedAccounts(await support.savedAccounts());
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await backend.agenda.unsyncedCount();
    backend.data.writeGate = Completer<void>();
    final writing = expectLater(
      backend.agenda.clearLocalData(),
      throwsA(isA<AgendaException>()),
    );
    await backend.data.writeStarted.future;
    var done = false;
    final signingOut = controller.logout().then((_) => done = true);
    try {
      // 文件锁不保证根事务 FIFO；等待真实退出持久化，日程写入仍保持挂起。
      await accounts.signedOut.future;
      expect((await accounts.read())!.canRestore, isFalse);
      expect(backend.data.rows, 5);
      expect(done, isFalse);
      await expectLater(
        backend.agenda.unsyncedCount(),
        throwsA(isA<AgendaException>()),
      );
    } finally {
      backend.data.writeGate!.complete();
      await writing;
      await signingOut;
    }
    expect(backend.data.rows, 0);
    expect(backend.data.active, isFalse);
  });

  test('后端工厂等待旧日程写入收尾后才建立继任服务', () async {
    final first = _RebuildBackend()..dead = true;
    final next = _RebuildBackend();
    var built = false;
    final controller = AppController(
      backend: first,
      backendFactory: () {
        built = true;
        return next;
      },
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await rebuild.cachedHome(controller, first);
    await first.agenda.unsyncedCount();
    first.data.writeGate = Completer<void>();
    final writing = expectLater(
      first.agenda.clearLocalData(),
      throwsA(isA<AgendaException>()),
    );
    await first.data.writeStarted.future;
    final recovering = controller.resumeSession();
    try {
      await Future<void>(() {});
      expect(first.agenda.accountId, isNull);
      expect(built, isFalse);
      expect(first.data.rows, 5);
    } finally {
      first.data.writeGate!.complete();
      await writing;
      await recovering;
    }
    expect(first.data.rows, 0);
    expect(built, isTrue);
    expect(controller.agenda, same(next.agenda));
    expect(first.data.active, isFalse);
  });

  test('日程停用尚未返回也先持久禁止账号自动恢复', () async {
    final accounts = _MissingKey(await support.savedAccounts());
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await backend.agenda.unsyncedCount();
    backend.data.deactivateGate = Completer<void>();
    var done = false;
    final signingOut = controller.logout().then((_) => done = true);
    await accounts.signedOut.future;
    try {
      expect((await accounts.read())!.canRestore, isFalse);
      expect(done, isFalse);
    } finally {
      backend.data.deactivateGate!.complete();
      await signingOut;
    }
  });

  test('退出等待安全索引时立即撤销旧日程引用和迟到结果', () async {
    final accounts = _SlowSignOut(await support.savedAccounts());
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    backend.data.countGate = Completer<int>();
    final reading = backend.agenda.unsyncedCount();
    await backend.data.countStarted.future;
    final rejected = expectLater(reading, throwsA(isA<AgendaException>()));
    final signingOut = controller.logout();
    await accounts.started.future;
    backend.data.countGate!.complete(99);
    try {
      await rejected;
      await expectLater(
        backend.agenda.unsyncedCount(),
        throwsA(isA<AgendaException>()),
      );
    } finally {
      accounts.gate.complete();
      await signingOut;
    }
  });

  test('核实新账号后等待旧索引关闭时不交付旧日程结果', () async {
    final accounts = _SlowSignOut(await support.savedAccounts());
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    backend.data.countGate = Completer<int>();
    final reading = backend.agenda.unsyncedCount();
    await backend.data.countStarted.future;
    final rejected = expectLater(reading, throwsA(isA<AgendaException>()));
    backend.username = 'fixture-other';
    controller.setUsername('fixture-other');
    controller.setPassword('synthetic');
    final login = controller.submitLogin(preserveHome: true);
    await accounts.started.future;
    backend.data.countGate!.complete(99);
    try {
      await rejected;
    } finally {
      accounts.gate.complete();
      await login;
    }
    expect(controller.phase, AppPhase.home);
    expect(backend.data.accounts, hasLength(2));
    expect(backend.data.accounts.first, isNot(backend.data.accounts.last));
  });
  for (final failed in [false, true]) {
    test('等待重建工厂时撤销日程，工厂${failed ? "失败恢复原服务" : "成功启用继任服务"}', () async {
      final first = _RebuildBackend()..dead = true;
      final next = _RebuildBackend();
      final factoryStarted = Completer<void>();
      final factoryGate = Completer<UbaaBackend>();
      final controller = AppController(
        backend: first,
        backendFactory: () {
          factoryStarted.complete();
          return factoryGate.future;
        },
        localAccountStore: await support.savedAccounts(),
      );
      addTearDown(controller.dispose);
      await rebuild.cachedHome(controller, first);
      await Future<void>.delayed(Duration.zero);
      final account = first.agenda.accountId;
      first.data.countGate = Completer<int>();
      final reading = first.agenda.unsyncedCount();
      await first.data.countStarted.future;
      final rejected = expectLater(reading, throwsA(isA<AgendaException>()));
      final recovering = controller.resumeSession();
      await factoryStarted.future;
      first.data.countGate!.complete(99);
      try {
        await rejected;
      } finally {
        if (failed) {
          factoryGate.completeError(StateError('合成工厂失败'));
        } else {
          factoryGate.complete(next);
        }
        await recovering;
      }
      await Future<void>.delayed(Duration.zero);
      expect(controller.agenda, same(failed ? first.agenda : next.agenda));
      expect(controller.agenda!.accountId, account);
      if (failed) {
        first.data.countGate = null;
        expect(await controller.agenda!.unsyncedCount(), 5);
      }
    });
  }

  test('后端重建关闭旧日程服务，同账号继任服务拒绝旧结果', () async {
    final first = _RebuildBackend()..dead = true;
    final next = _RebuildBackend();
    final controller = AppController(
      backend: first,
      backendFactory: () => next,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await rebuild.cachedHome(controller, first);
    await Future<void>.delayed(Duration.zero);
    final account = first.agenda.accountId;
    first.data.countGate = Completer<int>();
    final reading = first.agenda.unsyncedCount();
    await first.data.countStarted.future;
    final rejected = expectLater(
      reading,
      throwsA(
        isA<AgendaException>().having(
          (e) => e.failure,
          '旧实例结果',
          AgendaFailure.superseded,
        ),
      ),
    );
    await controller.resumeSession();
    first.data.countGate!.complete(99);
    await rejected;
    await Future<void>.delayed(Duration.zero);
    expect(controller.agenda, same(next.agenda));
    expect(next.agenda.accountId, account);
    expect(first.data.active, isFalse);
    await expectLater(
      first.agenda.openAccount(account!),
      throwsA(isA<AgendaException>()),
    );
  });

  test('已知账号缺少缓存密钥仍打开日程，换路线共用同一日程身份', () async {
    final accounts = _MissingKey(await support.savedAccounts());
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(controller.phase, AppPhase.home);
    expect(controller.agenda, same(backend.agenda));
    expect(await controller.agenda!.unsyncedCount(), 5);
    final id = backend.agenda.accountId;
    await controller.setRoutePolicy(RoutePolicy.webvpn);
    expect(controller.agenda!.accountId, id);
    expect(backend.data.accounts, [id]);
    expect(controller.localCacheError, isNotNull);
    await controller.logout(clearSavedCredential: true);
    expect(controller.agenda, isNull);
    expect(accounts.removals, 0);
    expect((await accounts.read())!.account!.id, id);
    await expectLater(
      backend.agenda.unsyncedCount(),
      throwsA(isA<AgendaException>()),
    );
  });
  test('日程损坏单独报告，不触发学校缓存恢复或丢失已核实账号', () async {
    final accounts = await support.savedAccounts();
    final backend = _Backend()
      ..data.openError = const AgendaException(AgendaFailure.corrupt);
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(controller.localAgendaFailure, AgendaFailure.corrupt);
    expect(controller.localCacheError, isNull);
    expect(controller.phase, AppPhase.home);
    expect((await accounts.read())!.account, isNotNull);
    await expectLater(
      controller.agenda!.unsyncedCount(),
      throwsA(isA<AgendaException>()),
    );
    expect(backend.data.accounts, hasLength(1));
  });
  test('销毁后迟到打开会关闭，旧服务不能重新激活', () async {
    final backend = _Backend()..data.openGate = Completer<void>();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    await controller.initialize();
    controller.dispose();
    backend.data.openGate!.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(backend.data.active, isFalse);
    await expectLater(
      backend.agenda.openAccount('old'),
      throwsA(isA<AgendaException>()),
    );
  });
}

class _Backend extends support.FakeRecoveryBackend
    implements AgendaProvider, OfflineCacheBackend {
  @override
  Future<void> openOfflineAccount(LocalAccount account, List<int> key) async {}
  @override
  Future<OfflineHomeRead> readCachedHome(RoutePolicy policy) async =>
      OfflineHomeRead([]);
  @override
  Future<void> deactivateOfflineAccount() async {}
  @override
  Future<void> clearOfflineAccount({required String accountId}) async {}
  final data = _Agenda();
  @override
  late final AgendaService agenda = AgendaService(data);
}

class _Agenda implements AgendaBackend {
  final accounts = <String>[];
  Object? openError;
  Completer<int>? countGate;
  final countStarted = Completer<void>();
  Completer<void>? openGate;
  bool active = false;
  Completer<void>? deactivateGate;
  Completer<void>? writeGate;
  final writeStarted = Completer<void>();
  int rows = 5;
  @override
  Future<int> clearLocalData() async {
    if (!writeStarted.isCompleted) writeStarted.complete();
    await writeGate?.future;
    final count = rows;
    rows = 0;
    return count;
  }

  @override
  Future<void> openAccount(String id) async {
    accounts.add(id);
    await openGate?.future;
    if (openError != null) throw openError!;
    active = true;
  }

  @override
  Future<void> deactivate() async {
    await deactivateGate?.future;
    active = false;
  }

  @override
  Future<int> unsyncedCount() async {
    if (!countStarted.isCompleted) countStarted.complete();
    return countGate == null ? 5 : countGate!.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ObservedAccounts implements LocalAccountStore {
  _ObservedAccounts(this.delegate);
  final LocalAccountStore delegate;
  int removals = 0;
  @override
  Future<LocalAccountState?> read() => delegate.read();
  @override
  Future<LocalAccountState> retain(
    String username, {
    required bool retainSession,
  }) => delegate.retain(username, retainSession: retainSession);
  @override
  Future<Uint8List> cacheKey(LocalAccount account) =>
      delegate.cacheKey(account);
  final signedOut = Completer<void>();
  @override
  Future<void> signOut() async {
    await delegate.signOut();
    if (!signedOut.isCompleted) signedOut.complete();
  }

  @override
  Future<void> removeAccount(String id) async {
    removals++;
    await delegate.removeAccount(id);
  }
}

class _MissingKey extends _ObservedAccounts {
  _MissingKey(super.delegate);
  @override
  Future<Uint8List> cacheKey(LocalAccount account) async =>
      throw const SecureMaterialException();
}

class _RebuildBackend extends rebuild.Backend implements AgendaProvider {
  final data = _Agenda();
  @override
  late final AgendaService agenda = AgendaService(data);
}

class _SlowSignOut extends _MissingKey {
  _SlowSignOut(super.delegate);
  final gate = Completer<void>();
  final started = Completer<void>();
  @override
  Future<void> signOut() async {
    started.complete();
    await gate.future;
    await super.signOut();
  }
}
