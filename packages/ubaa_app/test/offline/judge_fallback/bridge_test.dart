import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../judge_online/bridge_test.dart' as online;

void main() {
  setUpAll(() => RustLib.initMock(api: Api()));
  for (final failure in [
    BridgeCacheFailure.corrupt,
    BridgeCacheFailure.unavailable,
    BridgeCacheFailure.capacity,
    BridgeCacheFailure.unsupportedVersion,
  ]) {
    test('${failure.name}创建失败仍以当前账号逐批在线读取且不声称保存', () async {
      final client = Client()..failure = failure;
      final backend = await open(client);
      final task = (await backend.beginFeatureRead(FeatureId.judge, null))!;
      FeatureReadBatch batch;
      do {
        batch = await task.next();
      } while (!batch.finished);
      expect(client.options!.expectedIdentity, 'fixture-user');
      expect(batch.result.details.single.title, '合成作业');
      expect(batch.result.evidence!.savedForOffline, isFalse);
      expect(batch.result.evidence!.cacheFailure?.name, failure.name);
      expect(batch.result.error, isNull);
      expect(client.legacyCalls, 0);
      task.cancel();
    });
  }
  test('中途本地失败取消旧计划，在下一批创建在线计划，取消不能继续发请求', () async {
    final client = Client()..failAtNext = true;
    final backend = await open(client);
    final task = (await backend.beginFeatureRead(FeatureId.judge, null))!;
    final transition = await task.next();
    expect(transition.publish, isFalse);
    expect(client.old.cancelled, isTrue);
    expect(client.options, isNull);
    final begin = await task.next();
    expect(begin.publish, isFalse);
    expect(client.options!.expectedIdentity, 'fixture-user');
    task.cancel();
    await expectLater(task.next(), throwsA(isA<BackendException>()));
    expect(client.calls, 0);
  });
  for (final failure in [
    BridgeCacheFailure.inactive,
    BridgeCacheFailure.superseded,
    BridgeCacheFailure.invalidInput,
    null,
  ]) {
    test('终止或未分类错误$failure不得转在线绕过', () async {
      final client = Client()..failure = failure;
      final backend = await open(client);
      await expectLater(
        backend.beginFeatureRead(FeatureId.judge, null),
        throwsA(isA<BackendException>()),
      );
      expect(client.options, isNull);
    });
  }
  test('创建计划期间退出后迟到故障不得启动在线计划', () async {
    final client = Client()..startGate = Completer<BridgeJudgeRefreshTask>();
    final backend = await open(client);
    final pending = backend.beginFeatureRead(FeatureId.judge, null);
    await Future<void>.delayed(Duration.zero);
    await backend.deactivateOfflineAccount();
    client.startGate!.completeError(localError(BridgeCacheFailure.corrupt));
    await expectLater(
      pending,
      throwsA(
        isA<BackendException>().having(
          (e) => e.code,
          '代次',
          UbaaErrorCode.operationConflict,
        ),
      ),
    );
    expect(client.options, isNull);
  });
}

Future<BridgeBackend> open(Client client) async {
  final backend = BridgeBackend(client, configDirectory: '/synthetic');
  await backend.openOfflineAccount(
    const LocalAccount(id: 'synthetic', username: 'fixture-user'),
    List.filled(32, 9),
  );
  return backend;
}

BridgeError localError(BridgeCacheFailure? failure) => BridgeError(
  code: BridgeErrorCode.internalError,
  kind: BridgeErrorKind.internal,
  retryable: false,
  message: '合成本地故障',
  cacheFailure: failure,
);

class Client extends online.OnlineClient {
  BridgeCacheFailure? failure = BridgeCacheFailure.corrupt;
  bool failAtNext = false;
  final old = OldTask();
  Completer<BridgeJudgeRefreshTask>? startGate;
  @override
  Future<BridgeJudgeRefreshTask> beginJudgeRefresh({
    required BridgeOfflineCache cache,
    required BridgeJudgeRefreshOptions options,
  }) async {
    if (startGate case final gate?) return gate.future;
    if (!failAtNext) throw localError(failure);
    return old;
  }

  @override
  Future<BridgeJudgeProgress> nextJudgeRefresh({
    required BridgeJudgeRefreshTask task,
  }) async => throw localError(failure);
}

class OldTask implements BridgeJudgeRefreshTask {
  bool cancelled = false;
  @override
  void cancel() {
    cancelled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Api implements RustLibApi {
  @override
  Future<BridgeOfflineCache> crateApiOfflineBridgeOfflineCacheOpen({
    required String configDir,
    required String accountId,
    required String expectedIdentity,
    required List<int> key,
  }) async => Cache();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Cache implements BridgeOfflineCache {
  @override
  Future<void> activate() async {}
  @override
  Future<void> deactivate() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
