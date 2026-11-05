import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_app/src/bridge/agenda/backend.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_domain/ubaa_domain.dart';

final now = AgendaTime(
  rfc3339: '2026-03-01T00:00:00+08:00',
  timezone: 'Asia/Shanghai',
);
void main() {
  final api = Api();
  setUpAll(() => RustLib.initMock(api: api));
  setUp(api.reset);
  test('本机打开不建立网络同步句柄，同一账号同步复用原句柄并保留未验证数量', () async {
    final client = Client();
    final backend = BridgeAgendaBackend(
      BridgeContext(client, configDirectory: '/synthetic'),
    );
    await backend.openAccount('00000000000000000000000000000001');
    expect(api.created, 0);
    final first = await backend.prepareSync(AgendaSyncAction.pull, now)();
    final second = await backend.prepareSync(AgendaSyncAction.push, now)();
    expect(first.status, AgendaSyncStatus.unverified);
    expect(second.pendingCount, 7);
    expect(api.created, 1);
    expect(client.actions, [
      BridgeAgendaSyncAction.pull,
      BridgeAgendaSyncAction.push,
    ]);
    await backend.deactivate();
    expect(api.lastSync!.disposed, isTrue);
  });
  test('日程损坏与云盘超时保持独立的类型错误', () async {
    final client = Client();
    final backend = BridgeAgendaBackend(
      BridgeContext(client, configDirectory: '/synthetic'),
    );
    await backend.openAccount('00000000000000000000000000000001');
    client.error = const BridgeAgendaSyncError(
      local: BridgeAgendaFailure.corrupt,
      remote: null,
    );
    await expectLater(
      backend.prepareSync(AgendaSyncAction.pull, now)(),
      throwsA(
        isA<AgendaException>().having(
          (e) => e.failure,
          '日程错误',
          AgendaFailure.corrupt,
        ),
      ),
    );
    client.error = const BridgeAgendaSyncError(
      local: null,
      remote: BridgeError(
        code: BridgeErrorCode.timeout,
        kind: BridgeErrorKind.network,
        retryable: true,
        message: '合成超时',
        resolvedRoute: null,
        cacheFailure: null,
      ),
    );
    await expectLater(
      backend.prepareSync(AgendaSyncAction.pull, now)(),
      throwsA(
        isA<BackendException>().having(
          (e) => e.code,
          '云盘错误',
          UbaaErrorCode.timeout,
        ),
      ),
    );
    expect(client.actions, [
      BridgeAgendaSyncAction.pull,
      BridgeAgendaSyncAction.pull,
    ]);
    await backend.deactivate();
  });
  test('切号期间迟到的同步句柄被释放且不能替换新账号句柄', () async {
    final client = Client();
    final backend = BridgeAgendaBackend(
      BridgeContext(client, configDirectory: '/synthetic'),
    );
    await backend.openAccount('00000000000000000000000000000001');
    api.gate = Completer<BridgeAgendaSyncService>();
    final old = backend.prepareSync(AgendaSyncAction.pull, now)();
    final rejected = expectLater(
      old,
      throwsA(
        isA<AgendaException>().having(
          (e) => e.failure,
          '旧账号',
          AgendaFailure.superseded,
        ),
      ),
    );
    await api.started.future;
    await backend.deactivate();
    await backend.openAccount('00000000000000000000000000000002');
    final oldHandle = SyncHandle();
    api.gate!.complete(oldHandle);
    await rejected;
    expect(oldHandle.disposed, isTrue);
    expect(client.actions, isEmpty);
    api.gate = null;
    await backend.prepareSync(AgendaSyncAction.pull, now)();
    expect(client.actions, [BridgeAgendaSyncAction.pull]);
    await backend.deactivate();
  });
}

class Api extends RustLibApi {
  int created = 0;
  SyncHandle? lastSync;
  Completer<BridgeAgendaSyncService>? gate;
  Completer<void> started = Completer<void>();
  void reset() {
    created = 0;
    lastSync = null;
    gate = null;
    started = Completer<void>();
  }

  @override
  Future<BridgeAgendaStore> crateApiAgendaBridgeAgendaStoreOpen({
    required String configDir,
    required String accountId,
  }) async => StoreHandle();
  @override
  Future<BridgeAgendaSyncService>
  crateApiAgendaSyncBridgeAgendaSyncServiceOpen({
    required BridgeAgendaStore agenda,
    required String configDir,
  }) async {
    created++;
    if (!started.isCompleted) started.complete();
    if (gate != null) return gate!.future;
    return lastSync = SyncHandle();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class StoreHandle implements BridgeAgendaStore {
  bool enabled = false;
  @override
  Future<bool> syncEnabled() async => enabled;
  @override
  Future<int> unsyncedCount() async => 0;
  @override
  Future<void> activate() async {}
  @override
  void dispose() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SyncHandle implements BridgeAgendaSyncService {
  bool disposed = false;
  @override
  void dispose() {
    disposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Client implements BridgeClient {
  final actions = <BridgeAgendaSyncAction>[];
  BridgeAgendaSyncError? error;
  @override
  Future<BridgeAgendaSyncReport> syncAgenda({
    required BridgeAgendaSyncService service,
    required BridgeAgendaSyncAction action,
    required BridgeAgendaTime now,
  }) async {
    actions.add(action);
    if (error != null) throw error!;
    return const BridgeAgendaSyncReport(
      status: BridgeAgendaSyncStatus.unverified,
      pendingCount: 7,
      changedCount: 0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
