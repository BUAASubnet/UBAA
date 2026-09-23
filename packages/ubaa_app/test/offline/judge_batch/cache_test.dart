import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../judge_fallback/bridge_test.dart' as fallback;
import '../judge_online/bridge_test.dart' as online;
import '../progressive_controller_test.dart' show until;

const query = FeatureQuery(
  view: FeatureQueryView.judgeBatchDetails,
  judgeKeys: [
    JudgeAssignmentQueryKey(courseId: '12', assignmentId: '101'),
    JudgeAssignmentQueryKey(courseId: '12', assignmentId: '101'),
  ],
);

void main() {
  final cache = Cache();
  setUpAll(() => RustLib.initMock(api: Api(cache)));
  setUp(() {
    cache.missing = false;
    cache.failure = null;
    cache.wrong = false;
    cache.reads.clear();
  });
  test('批量存储故障回退仍保留明确目标与未保存分类', () async {
    final client = Client()..failBegin = true;
    final backend = await fallback.open(client);
    final task = (await backend.beginFeatureRead(FeatureId.judge, query))!;
    FeatureReadBatch batch;
    do {
      batch = await task.next();
    } while (!batch.finished);
    expect(client.options!.keys!.single.assignmentId, '101');
    expect(batch.result.evidence!.savedForOffline, isFalse);
    expect(
      batch.result.evidence!.cacheFailure,
      CacheMaintenanceFailure.corrupt,
    );
    task.cancel();
  });
  test('批量创建期间退出，迟到持久句柄被取消', () async {
    final client = Client()..beginGate = Completer<BridgeJudgeDetailsTask>();
    final backend = await fallback.open(client);
    final pending = backend.beginFeatureRead(FeatureId.judge, query);
    await until(() => client.keys != null);
    await backend.deactivateOfflineAccount();
    final rejected = expectLater(
      pending,
      throwsA(
        isA<BackendException>().having(
          (e) => e.code,
          '代次',
          UbaaErrorCode.operationConflict,
        ),
      ),
    );
    client.beginGate!.complete(client.persistent);
    await rejected;
    expect(client.persistent.cancelled, isTrue);
    expect(client.options, isNull);
  });
  test('损坏条目不冒充目标且其他已保存详情继续可见', () async {
    final backend = await fallback.open(Client());
    cache.failure = BridgeCacheFailure.corrupt;
    final partial = await backend.readCachedQuery(
      FeatureId.judge,
      const FeatureQuery(
        view: FeatureQueryView.judgeBatchDetails,
        judgeKeys: [
          JudgeAssignmentQueryKey(courseId: '12', assignmentId: '102'),
          JudgeAssignmentQueryKey(courseId: '12', assignmentId: '101'),
        ],
      ),
      RoutePolicy.direct,
    );
    expect(partial.projection!.details.single.title, '合成101');
    expect(partial.projection!.complete, isFalse);
    expect(partial.error!.cacheFailure, CacheMaintenanceFailure.corrupt);
    cache.failure = null;
    cache.wrong = true;
    final invalid = await backend.readCachedQuery(
      FeatureId.judge,
      query,
      RoutePolicy.direct,
    );
    expect(invalid.projection, isNull);
    expect(invalid.error!.cacheFailure, CacheMaintenanceFailure.corrupt);
  });
  for (final storageFailure in [null, BridgeCacheFailure.capacity]) {
    test('批量详情走持久分段且保存结果独立 $storageFailure', () async {
      final client = Client()..saveFailure = storageFailure;
      final backend = await fallback.open(client);
      final task = (await backend.beginFeatureRead(FeatureId.judge, query))!;
      FeatureReadBatch batch;
      do {
        batch = await task.next();
      } while (!batch.finished);
      expect(client.keys, isNotNull);
      expect(client.keys!.length, 1);
      expect(client.options, isNull);
      expect(batch.result.details.single.title, '合成作业');
      expect(batch.result.evidence!.complete, isTrue);
      expect(batch.result.evidence!.savedForOffline, storageFailure == null);
      expect(batch.result.evidence!.cacheFailure?.name, storageFailure?.name);
      expect(batch.result.error, isNull);
      task.cancel();
      expect(client.persistent.cancelled, isTrue);
    });
  }
  for (final missing in [false, true]) {
    test('离线批量精确去重保序，缺项=$missing不冒充完整', () async {
      cache.missing = missing;
      final client = Client();
      final backend = await fallback.open(client);
      final value = await backend.readCachedQuery(
        FeatureId.judge,
        const FeatureQuery(
          view: FeatureQueryView.judgeBatchDetails,
          judgeKeys: [
            JudgeAssignmentQueryKey(courseId: '12', assignmentId: '102'),
            JudgeAssignmentQueryKey(courseId: '12', assignmentId: '101'),
            JudgeAssignmentQueryKey(courseId: '12', assignmentId: '102'),
          ],
        ),
        RoutePolicy.direct,
      );
      expect(value.projection, isNotNull);
      final snapshot = value.projection!.toSnapshot();
      expect(
        snapshot.details.map((d) => d.title),
        missing ? ['合成101'] : ['合成102', '合成101'],
      );
      expect(snapshot.evidence!.fetchedAt.millisecondsSinceEpoch, 100000);
      expect(snapshot.evidence!.complete, !missing);
      expect(snapshot.details.expand((d) => d.actions), isEmpty);
      expect(client.keys, isNull);
      expect(client.options, isNull);
      expect(cache.reads, ['102', '101']);
    });
  }
}

class Api extends fallback.Api {
  Api(this.cache);
  final Cache cache;
  @override
  Future<BridgeOfflineCache> crateApiOfflineBridgeOfflineCacheOpen({
    required String configDir,
    required String accountId,
    required String expectedIdentity,
    required List<int> key,
  }) async => cache;
}

class Cache extends fallback.Cache {
  bool missing = false;
  bool wrong = false;
  BridgeCacheFailure? failure;
  final reads = <String>[];
  @override
  Future<BridgeCachedJudgeDetail?> readJudgeDetail({
    required BridgeConnectionMode route,
    required String courseId,
    required String assignmentId,
  }) async {
    reads.add(assignmentId);
    if (failure != null && assignmentId == '102')
      throw fallback.localError(failure);
    if (missing && assignmentId == '102') return null;
    return BridgeCachedJudgeDetail(
      data: BridgeJudgeAssignmentDetail(
        courseId: wrong ? '99' : courseId,
        courseName: '合成课程',
        assignmentId: assignmentId,
        title: '合成$assignmentId',
        totalProblems: 1,
        submittedCount: 0,
        submissionStatus: BridgeJudgeSubmissionStatus.unsubmitted,
        submissionStatusText: '未提交',
        problems: const [],
      ),
      sourceRoute: route,
      fetchedAt: assignmentId == '101' ? 100 : 200,
      complete: true,
    );
  }
}

class Client extends fallback.Client {
  List<BridgeJudgeAssignmentKey>? keys;
  BridgeCacheFailure? saveFailure;
  bool failBegin = false;
  Completer<BridgeJudgeDetailsTask>? beginGate;
  final persistent = PersistentTask();
  @override
  Future<BridgeJudgeDetailsTask> beginJudgeDetails({
    required BridgeOfflineCache cache,
    required List<BridgeJudgeAssignmentKey> keys,
  }) async {
    this.keys = keys;
    if (failBegin) throw fallback.localError(BridgeCacheFailure.corrupt);
    if (beginGate case final gate?) return gate.future;
    return persistent;
  }

  @override
  Future<BridgeJudgeProgress> nextJudgeDetails({
    required BridgeJudgeDetailsTask task,
  }) async {
    final value = online.progress(calls++ == 0);
    return BridgeJudgeProgress(
      batch: value.batch,
      summaries: value.summaries,
      summaryFetchedAt: value.fetchedAt,
      sourceFetchedAt: value.fetchedAt,
      summaryHasCached: false,
      reused: false,
      saveError: saveFailure,
    );
  }
}

class PersistentTask implements BridgeJudgeDetailsTask {
  bool cancelled = false;
  @override
  void cancel() {
    cancelled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
