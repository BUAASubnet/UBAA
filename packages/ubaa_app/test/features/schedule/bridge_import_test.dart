import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  setUpAll(() => RustLib.initMock(api: _Api()));
  test('指定学期逐批投影，全部读取但保存失败不能称为已保存', () async {
    final client = _Client();
    final backend = await _backend(client);
    final task = await backend.beginScheduleImport('2025-2026-1');
    expect(client.term, '2025-2026-1');
    client.result = _progress(
      finished: true,
      failure: BridgeCacheFailure.capacity,
    );
    final result = await task.next();
    expect(result.term, '2025-2026-1');
    expect(result.finished, isTrue);
    expect(result.saved, isFalse);
    expect(result.saveFailure, CacheMaintenanceFailure.capacity);
    expect(result.route, ConnectionMode.webvpn);
    task.cancel();
    expect(client.task.cancelled, isTrue);
  });
  test('未打开仓库拒绝创建计划，不退回普通整学期大读取', () async {
    final client = _Client();
    final backend = BridgeBackend(client);
    await expectLater(
      backend.beginScheduleImport('2025-2026-1'),
      throwsA(isA<BackendException>()),
    );
    expect(client.begins, 0);
  });
  test('退出过程中迟到进度被拒绝，下一批不再到达Bridge', () async {
    final client = _Client();
    final backend = await _backend(client);
    final task = await backend.beginScheduleImport('2025-2026-1');
    client.pending = Completer();
    final reading = task.next();
    final rejected = expectLater(reading, throwsA(isA<BackendException>()));
    await Future<void>.delayed(Duration.zero);
    await backend.deactivateOfflineAccount();
    client.pending!.complete(_progress(finished: true));
    await rejected;
    await expectLater(task.next(), throwsA(isA<BackendException>()));
    expect(client.nexts, 1);
    expect(client.task.cancelled, isTrue);
  });
  test('取消与创建期间账号替换都释放原计划且不交付旧任务', () async {
    final client = _Client();
    final backend = await _backend(client);
    final first = await backend.beginScheduleImport('2025-2026-1');
    first.cancel();
    await expectLater(first.next(), throwsA(isA<BackendException>()));
    expect(client.nexts, 0);
    client.beginPending = Completer();
    final starting = backend.beginScheduleImport('2025-2026-1');
    final rejected = expectLater(starting, throwsA(isA<BackendException>()));
    await Future<void>.delayed(Duration.zero);
    await backend.openOfflineAccount(
      const LocalAccount(id: 'other', username: 'other'),
      List.filled(32, 8),
    );
    client.task.cancelled = false;
    client.beginPending!.complete(client.task);
    await rejected;
    expect(client.task.cancelled, isTrue);
  });
}

Future<BridgeBackend> _backend(_Client client) async {
  final backend = BridgeBackend(client, configDirectory: '/synthetic');
  await backend.openOfflineAccount(
    const LocalAccount(id: 'synthetic', username: 'synthetic'),
    List.filled(32, 9),
  );
  return backend;
}

class _Api implements RustLibApi {
  @override
  Future<BridgeOfflineCache> crateApiOfflineBridgeOfflineCacheOpen({
    required String configDir,
    required String accountId,
    required String expectedIdentity,
    required List<int> key,
  }) async => _Cache();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cache implements BridgeOfflineCache {
  @override
  Future<void> activate() async {}
  @override
  Future<void> deactivate() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Task implements BridgeScheduleImportTask {
  bool cancelled = false;
  @override
  void cancel() => cancelled = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements BridgeClient {
  int begins = 0, nexts = 0;
  String? term;
  final task = _Task();
  Completer<BridgeScheduleImportTask>? beginPending;
  Completer<BridgeScheduleImportProgress>? pending;
  BridgeScheduleImportProgress result = _progress();
  @override
  int contractVersion() => 40;
  @override
  Future<BridgeScheduleImportTask> beginScheduleImport({
    required BridgeOfflineCache cache,
    required String term,
  }) async {
    begins++;
    this.term = term;
    return beginPending?.future ?? task;
  }

  @override
  Future<BridgeScheduleImportProgress> nextScheduleImport({
    required BridgeScheduleImportTask task,
  }) async {
    nexts++;
    return pending?.future ?? result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BridgeScheduleImportProgress _progress({
  bool finished = false,
  BridgeCacheFailure? failure,
}) => BridgeScheduleImportProgress(
  termCode: '2025-2026-1',
  completedWeeks: finished ? 2 : 1,
  totalWeeks: 2,
  finished: finished,
  saveError: failure,
  route: const BridgeRouteDecision(
    policy: BridgeRoutePolicy.auto,
    resolvedRoute: BridgeConnectionMode.webVpn,
    network: BridgeNetworkState.unknown,
    initialRoute: BridgeConnectionMode.webVpn,
    usedFallback: false,
  ),
);
