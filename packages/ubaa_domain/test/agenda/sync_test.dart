import 'dart:async';
import 'package:test/test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

final now = AgendaTime(
  rfc3339: '2026-03-01T00:00:00+08:00',
  timezone: 'Asia/Shanghai',
);
const unknown = AgendaSyncReport(
  status: AgendaSyncStatus.outcomeUnknown,
  pendingCount: 1,
  changedCount: 0,
);
void main() {
  test('本机修改触发一次上传，unknown 保留状态且不自行重试', () async {
    final backend = Backend();
    final service = AgendaService(backend);
    await service.openAccount('same-account');
    await service.complete('item', null, true, now);
    await Future<void>.delayed(Duration.zero);
    expect(backend.calls, [AgendaSyncAction.push]);
    expect(service.syncState.report?.status, AgendaSyncStatus.outcomeUnknown);
    expect(service.syncState.report?.pendingCount, 1);
    await Future<void>.delayed(Duration.zero);
    expect(backend.calls, [AgendaSyncAction.push]);
    await service.dispose();
  });
  test('拉取等待不阻止本机保存，同账号重新打开拒绝旧同步结果', () async {
    final backend = Backend()..gate = Completer<AgendaSyncReport>();
    final service = AgendaService(backend);
    await service.openAccount('same-account');
    final pulling = service.sync(AgendaSyncAction.pull, now);
    final rejected = expectLater(
      pulling,
      throwsA(
        isA<AgendaException>().having(
          (e) => e.failure,
          '类别',
          AgendaFailure.superseded,
        ),
      ),
    );
    await backend.started.future;
    await service.complete('item', null, true, now);
    expect(backend.localWrites, 1);
    await service.close();
    await service.openAccount('same-account');
    backend.gate!.complete(unknown);
    await rejected;
    await Future<void>.delayed(Duration.zero);
    expect(backend.calls, [AgendaSyncAction.pull]);
    expect(service.syncState.report, isNull);
    expect(service.syncState.error, isNull);
    await service.dispose();
  });
  test('显式同步失败保留原错误且不自行发起后续作业', () async {
    final failure = StateError('合成网络失败');
    final backend = Backend()..failure = failure;
    final service = AgendaService(backend);
    await service.openAccount('same-account');
    await expectLater(
      service.sync(AgendaSyncAction.push, now),
      throwsA(same(failure)),
    );
    expect(service.syncState.error, same(failure));
    await Future<void>.delayed(Duration.zero);
    expect(backend.calls, [AgendaSyncAction.push]);
    await service.dispose();
  });
  test('清除本机资料不触发云端上传', () async {
    final backend = Backend();
    final service = AgendaService(backend);
    await service.openAccount('same-account');
    await service.clearLocalData();
    await Future<void>.delayed(Duration.zero);
    expect(backend.calls, isEmpty);
    await service.dispose();
  });
}

class Backend implements AgendaBackend, AgendaSyncBackend {
  final calls = <AgendaSyncAction>[];
  final started = Completer<void>();
  Completer<AgendaSyncReport>? gate;
  Object? failure;
  int localWrites = 0;
  @override
  Future<void> openAccount(String accountId) async {}
  @override
  Future<void> deactivate() async {}
  @override
  Future<void> complete(
    String itemId,
    AgendaTime? at,
    bool completed,
    AgendaTime now,
  ) async {
    localWrites++;
  }

  @override
  Future<int> clearLocalData() async => 0;
  @override
  AgendaSyncJob prepareSync(AgendaSyncAction action, AgendaTime now) =>
      () => sync(action, now);

  Future<AgendaSyncReport> sync(AgendaSyncAction action, AgendaTime now) async {
    calls.add(action);
    if (!started.isCompleted) started.complete();
    if (failure != null) throw failure!;
    return gate?.future ?? unknown;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
