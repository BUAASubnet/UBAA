import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

const account = LocalAccount(id: 'synthetic', username: 'fixture-user');
void main() {
  final api = SpocCacheApi();
  setUpAll(() => RustLib.initMock(api: api));
  setUp(() => api.cache = SpocCache());
  test('SPOC 首页无缓存也创建逐页任务，不落回旧长聚合', () async {
    final client = SpocClient();
    final backend = BridgeBackend(client);
    final task = await backend.beginAccountFeatureRead(
      FeatureId.spoc,
      null,
      account,
    );
    expect(task, isNotNull);
    expect(client.expectedIdentity, account.username);
    expect((await task!.next()).publish, isFalse);
    expect((await task.next()).publish, isFalse);
    final first = await task.next();
    expect(first.finished, isFalse);
    expect(first.result.details.single.title, '合成 a1');
    expect(first.result.evidence!.savedForOffline, isFalse);
    expect(first.result.evidence!.complete, isFalse);
    final last = await task.next();
    expect(last.finished, isTrue);
    expect(last.result.details.length, 2);
    expect(last.result.evidence!.complete, isTrue);
    expect(last.result.evidence!.savedForOffline, isFalse);
    expect(last.result.details.expand((item) => item.actions), isEmpty);
    task.cancel();
    expect(client.task.cancelled, isTrue);
  });
  test('分页途中同学期保留完整旧集合和原时间，完整后替换', () async {
    api.cache.value = saved('term-a');
    final client = SpocClient();
    final backend = BridgeBackend(client, configDirectory: '/synthetic');
    await backend.openOfflineAccount(account, List.filled(32, 7));
    final task = (await backend.beginFeatureRead(FeatureId.spoc, null))!;
    expect(client.persistent, isTrue);
    await task.next();
    await task.next();
    final first = await task.next();
    expect(first.result.details.map((item) => item.title), ['合成 old', '合成 a1']);
    expect(first.result.evidence!.fetchedAt.millisecondsSinceEpoch, 50000);
    expect(first.result.evidence!.origin, DataOrigin.mixed);
    final last = await task.next();
    expect(last.result.details.map((item) => item.title), ['合成 a1', '合成 a2']);
    expect(last.result.evidence!.fetchedAt.millisecondsSinceEpoch, 100000);
    expect(last.result.evidence!.savedForOffline, isTrue);
  });
  test('新学期部分页不冒用旧学期名称，失败终态继续保留旧集合', () async {
    api.cache.value = saved('term-old');
    final client = SpocClient()..partial = true;
    final backend = BridgeBackend(client, configDirectory: '/synthetic');
    await backend.openOfflineAccount(account, List.filled(32, 7));
    final task = (await backend.beginFeatureRead(FeatureId.spoc, null))!;
    await task.next();
    await task.next();
    for (final batch in [await task.next(), await task.next()]) {
      expect((batch.result.overview as SpocTermOverview).termCode, 'term-old');
      expect(batch.result.details.single.title, '合成 old');
      expect(batch.result.evidence!.complete, isFalse);
      expect(batch.result.evidence!.fetchedAt.millisecondsSinceEpoch, 50000);
    }
  });
  test('无数据的中间页不是完整空结果，退出代次丢弃在途页', () async {
    final client = SpocClient()..empty = true;
    final backend = BridgeBackend(client);
    final task = (await backend.beginFeatureRead(FeatureId.spoc, null))!;
    await task.next();
    await task.next();
    final partial = await task.next();
    expect(partial.result.isEmpty, isFalse);
    client.gate = Completer<BridgeSpocScanBatch>();
    final pending = task.next();
    await backend.deactivateOfflineAccount();
    client.gate!.complete(client.batch(3));
    await expectLater(
      pending,
      throwsA(
        isA<BackendException>().having(
          (e) => e.code,
          '旧代次',
          UbaaErrorCode.operationConflict,
        ),
      ),
    );
  });
  test('开始任务时账号变化也取消迟到句柄', () async {
    final client = SpocClient()..beginGate = Completer<BridgeSpocScan>();
    final backend = BridgeBackend(client);
    final pending = backend.beginFeatureRead(FeatureId.spoc, null);
    await Future<void>.delayed(Duration.zero);
    await backend.deactivateOfflineAccount();
    client.beginGate!.complete(client.task);
    await expectLater(pending, throwsA(isA<BackendException>()));
    expect(client.task.cancelled, isTrue);
  });
}

BridgeSpocAssignments data(String term, List<String> ids) =>
    BridgeSpocAssignments(
      termCode: term,
      assignments: [
        for (final id in ids)
          BridgeSpocAssignmentSummary(
            assignmentId: id,
            courseId: 'c1',
            courseName: '合成课程',
            title: '合成 $id',
            submissionStatus: BridgeSpocSubmissionStatus.unsubmitted,
            submissionStatusText: '未提交',
          ),
      ],
    );
BridgeCachedHomeSpoc saved(String term) => BridgeCachedHomeSpoc(
  data: data(term, ['old']),
  sourceRoute: BridgeConnectionMode.direct,
  fetchedAt: 50,
  complete: true,
);

class SpocCacheApi implements RustLibApi {
  SpocCache cache = SpocCache();
  @override
  Future<BridgeOfflineCache> crateApiOfflineBridgeOfflineCacheOpen({
    required String configDir,
    required String accountId,
    required String expectedIdentity,
    required List<int> key,
  }) async => cache;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SpocCache implements BridgeOfflineCache {
  BridgeCachedHomeSpoc? value;
  BridgeCachedHomeSpocDetail? detailValue;
  @override
  Future<BridgeCachedHomeSpocDetail?> readHomeSpocDetail({
    required BridgeConnectionMode route,
    required String assignmentId,
  }) async => detailValue;
  @override
  Future<void> activate() async {}
  @override
  Future<BridgeCachedHomeSpoc?> readHomeSpoc({
    required BridgeConnectionMode route,
  }) async => value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Task implements BridgeSpocScan {
  bool cancelled = false;
  @override
  void cancel() {
    cancelled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SpocClient implements BridgeClient {
  final detailTask = SpocDetailTask();
  int detailCalls = 0;
  bool wrongDetail = false;
  String? requestedAssignment;
  Completer<BridgeSpocDetailScanBatch>? detailGate;
  @override
  Future<BridgeSpocDetailScan> beginSpocDetailOnline({
    String? expectedIdentity,
    required String assignmentId,
  }) async {
    this.expectedIdentity = expectedIdentity;
    requestedAssignment = assignmentId;
    return detailTask;
  }

  @override
  Future<BridgeSpocDetailScan> beginSpocDetailScan({
    required BridgeOfflineCache cache,
    required String assignmentId,
  }) async {
    persistent = true;
    requestedAssignment = assignmentId;
    return detailTask;
  }

  @override
  Future<BridgeSpocDetailScanBatch> nextSpocDetailScan({
    required BridgeSpocDetailScan task,
  }) async => detailGate?.future ?? detailBatch(detailCalls++ > 0);
  BridgeSpocDetailScanBatch detailBatch(bool finished) =>
      BridgeSpocDetailScanBatch(
        result: finished
            ? BridgeRoutedSpocAssignmentDetail(
                data: detailData(wrongDetail ? 'wrong' : 'a1', '新详情'),
                route: batch(3).result.route,
              )
            : null,
        state: BridgeHomeRefreshState(
          fetchedAt: 100,
          complete: finished && !partial,
          savedForOffline: finished && !partial && persistent,
          preservedPrevious: partial,
        ),
        completedPages: finished ? 2 : 1,
        finished: finished,
      );
  final task = _Task();
  int calls = 0;
  bool persistent = false, partial = false, empty = false;
  String? expectedIdentity;
  Completer<BridgeSpocScan>? beginGate;
  Completer<BridgeSpocScanBatch>? gate;
  @override
  int contractVersion() => 40;
  @override
  Future<BridgeSpocScan> beginSpocOnline({String? expectedIdentity}) async {
    this.expectedIdentity = expectedIdentity;
    return beginGate?.future ?? task;
  }

  @override
  Future<BridgeSpocScan> beginSpocScan({
    required BridgeOfflineCache cache,
  }) async {
    persistent = true;
    return task;
  }

  @override
  Future<BridgeSpocScanBatch> nextSpocScan({
    required BridgeSpocScan task,
  }) async => gate?.future ?? batch(calls++);
  BridgeSpocScanBatch batch(int step) => BridgeSpocScanBatch(
    result: BridgeRoutedSpocAssignments(
      data: data(
        'term-a',
        empty || step < 2
            ? []
            : step == 2
            ? ['a1']
            : ['a1', 'a2'],
      ),
      route: const BridgeRouteDecision(
        policy: BridgeRoutePolicy.direct,
        resolvedRoute: BridgeConnectionMode.direct,
        network: BridgeNetworkState.unknown,
        initialRoute: BridgeConnectionMode.direct,
        usedFallback: false,
      ),
    ),
    state: BridgeHomeRefreshState(
      fetchedAt: 100,
      complete: step >= 3 && !partial,
      savedForOffline: step >= 3 && !partial && persistent,
      preservedPrevious: step < 3 || partial,
    ),
    completedPages: step < 2 ? 0 : step - 1,
    finished: step >= 3,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SpocDetailTask implements BridgeSpocDetailScan {
  bool cancelled = false;
  @override
  void cancel() {
    cancelled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BridgeSpocAssignmentDetail detailData(String id, String title) =>
    BridgeSpocAssignmentDetail(
      assignmentId: id,
      courseId: 'c1',
      courseName: '合成课程',
      title: title,
      submissionStatus: BridgeSpocSubmissionStatus.unsubmitted,
      submissionStatusText: '未提交',
      contentPlainText: '合成正文',
    );
