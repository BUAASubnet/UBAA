import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/recovery.dart' as support;
import '../recovery/backend_rebuild/fakes.dart' as rebuild;

void main() {
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
  @override
  Future<void> openAccount(String id) async {
    accounts.add(id);
    await openGate?.future;
    if (openError != null) throw openError!;
    active = true;
  }

  @override
  Future<void> deactivate() async {
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

class _MissingKey implements LocalAccountStore {
  _MissingKey(this.delegate);
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
  Future<Uint8List> cacheKey(LocalAccount account) async =>
      throw const SecureMaterialException();
  @override
  Future<void> signOut() => delegate.signOut();
  @override
  Future<void> removeAccount(String id) async {
    removals++;
    await delegate.removeAccount(id);
  }
}

class _RebuildBackend extends rebuild.Backend implements AgendaProvider {
  final data = _Agenda();
  @override
  late final AgendaService agenda = AgendaService(data);
}
