import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  test('详情精确传递双标识，Auto 选择最新来源且单路线损坏不遮蔽其他记录', () async {
    final cache = _Cache()..damagedDirectDetail = true;
    api.cache = cache;
    final backend = BridgeBackend(_Client(), configDirectory: '/synthetic');
    await backend.openOfflineAccount(
      const LocalAccount(id: 'synthetic', username: 'synthetic'),
      List.filled(32, 1),
    );
    const query = FeatureQuery(
      view: FeatureQueryView.judgeDetail,
      courseId: '12',
      assignmentId: '101',
      fullRefresh: true,
    );
    final read = await backend.readCachedQuery(
      FeatureId.judge,
      query,
      RoutePolicy.auto,
    );
    expect(cache.detailReads, [
      (BridgeConnectionMode.direct, '12', '101'),
      (BridgeConnectionMode.webVpn, '12', '101'),
    ]);
    expect(read.error, isNotNull);
    expect(read.projection!.route, ConnectionMode.webvpn);
    expect(read.projection!.readContext.hasSameQuery(query), isTrue);
    expect(read.projection!.fetchedAt.millisecondsSinceEpoch, 200000);
    expect(read.projection!.details.single.actions, isEmpty);
    cache.damagedDirectDetail = false;
    final latest = await backend.readCachedQuery(
      FeatureId.judge,
      query,
      RoutePolicy.auto,
    );
    expect(latest.projection!.route, ConnectionMode.webvpn);
    final direct = await backend.readCachedQuery(
      FeatureId.judge,
      query,
      RoutePolicy.direct,
    );
    expect(direct.projection!.route, ConnectionMode.direct);
    expect(direct.projection!.fetchedAt.millisecondsSinceEpoch, 100000);
  });
  test('查询缓存不会拿今日替代周课表，详情错配拒绝投影', () async {
    final cache = _Cache()..wrongDetail = true;
    api.cache = cache;
    final backend = BridgeBackend(_Client(), configDirectory: '/synthetic');
    await backend.openOfflineAccount(
      const LocalAccount(id: 'synthetic', username: 'synthetic'),
      List.filled(32, 1),
    );
    final week = await backend.readCachedQuery(
      FeatureId.schedule,
      const FeatureQuery(term: '2026', week: 1),
      RoutePolicy.direct,
    );
    expect(week.projection, isNull);
    expect(cache.reads, isEmpty);
    final detail = await backend.readCachedQuery(
      FeatureId.judge,
      const FeatureQuery(
        view: FeatureQueryView.judgeDetail,
        courseId: '12',
        assignmentId: '101',
      ),
      RoutePolicy.direct,
    );
    expect(detail.projection, isNull);
    expect(detail.error, isNotNull);
    await backend.readCachedQuery(
      FeatureId.judge,
      const FeatureQuery(includeExpired: true),
      RoutePolicy.direct,
    );
    expect(cache.expiredReads, [true]);
  });
  test('实际缓存路线与原时间不被配置策略改写，且不会校验网络会话', () async {
    final cache = _Cache();
    api.cache = cache;
    final backend = BridgeBackend(_Client(), configDirectory: '/synthetic');
    await backend.openOfflineAccount(
      const LocalAccount(id: 'synthetic', username: 'synthetic'),
      List.filled(32, 1),
    );
    final records = await backend.readCachedHome(RoutePolicy.webvpn);
    expect(cache.reads, [BridgeConnectionMode.webVpn]);
    final schedule = records.singleWhere(
      (record) => record.feature == FeatureId.schedule,
    );
    final judge = records.singleWhere(
      (record) => record.feature == FeatureId.judge,
    );
    expect(judge.details.single.title, '已保存的合成作业');
    expect(judge.details.single.readNavigation?.query.includeExpired, isFalse);
    expect(judge.details.single.actions, isEmpty);
    expect(schedule.route, ConnectionMode.webvpn);
    expect(schedule.fetchedAt.millisecondsSinceEpoch, 1700000000000);
    expect(schedule.toSnapshot().details.single.actions, isEmpty);
    expect(schedule.scopeDate, '2026-09-21');
  });
  test('一个领域的缓存损坏不能遮蔽其他领域已保存的待办', () async {
    api.cache = _Cache()..damagedToday = true;
    final backend = BridgeBackend(_Client(), configDirectory: '/synthetic');
    await backend.openOfflineAccount(
      const LocalAccount(id: 'synthetic', username: 'synthetic'),
      List.filled(32, 1),
    );
    final batch = await backend.readCachedHome(RoutePolicy.direct);
    expect(batch.single.feature, FeatureId.judge);
    expect(batch.error, isNotNull);
  });
  test('打开缓存被挂起时随后退出，启用不能越过停用重新开放账号', () async {
    final cache = _Cache()..activateGate = Completer<void>();
    api.cache = cache;
    final backend = BridgeBackend(_Client(), configDirectory: '/synthetic');
    final opening = backend.openOfflineAccount(
      const LocalAccount(id: 'synthetic', username: 'synthetic'),
      List.filled(32, 1),
    );
    final closing = backend.deactivateOfflineAccount();
    await Future<void>.delayed(Duration.zero);
    cache.activateGate!.complete();
    await opening;
    await closing;
    expect(cache.events, ['activate', 'deactivate']);
  });
}

class _Api implements RustLibApi {
  late _Cache cache;
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

class _Client implements BridgeClient {
  @override
  int contractVersion() => 29;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cache implements BridgeOfflineCache {
  @override
  Future<BridgeCachedCgyyOrdersRecord?> readCgyyOrders({
    required BridgeConnectionMode route,
    required int page,
    required int size,
  }) async => null;

  @override
  Future<BridgeCachedBykcChosenRecord?> readBykcChosen({
    required BridgeConnectionMode route,
  }) async => null;

  @override
  Future<BridgeCachedHomeSignin?> readHomeSignin({
    required BridgeConnectionMode route,
  }) async => null;
  @override
  Future<BridgeCachedHomeSpoc?> readHomeSpoc({
    required BridgeConnectionMode route,
  }) async => null;
  @override
  Future<BridgeCachedHomeYgdk?> readHomeYgdk({
    required BridgeConnectionMode route,
  }) async => null;

  @override
  Future<BridgeCachedAcademicWeek?> readAcademicWeek({
    required BridgeConnectionMode route,
    required String term,
    required int week,
  }) async => null;

  final reads = <BridgeConnectionMode>[];
  final detailReads = <(BridgeConnectionMode, String, String)>[];
  final expiredReads = <bool>[];
  bool damagedDirectDetail = false;
  bool wrongDetail = false;
  @override
  Future<BridgeCachedJudgeDetail?> readJudgeDetail({
    required BridgeConnectionMode route,
    required String courseId,
    required String assignmentId,
  }) async {
    detailReads.add((route, courseId, assignmentId));
    if (damagedDirectDetail && route == BridgeConnectionMode.direct)
      throw const BridgeError(
        code: BridgeErrorCode.internalError,
        kind: BridgeErrorKind.internal,
        retryable: false,
        message: '合成损坏',
      );
    return BridgeCachedJudgeDetail(
      data: BridgeJudgeAssignmentDetail(
        courseId: courseId,
        courseName: '合成课程',
        assignmentId: wrongDetail ? 'other' : assignmentId,
        title: '已保存详情',
        totalProblems: 1,
        submittedCount: 0,
        submissionStatus: BridgeJudgeSubmissionStatus.unsubmitted,
        submissionStatusText: '未提交',
        problems: const [],
      ),
      sourceRoute: route,
      fetchedAt: route == BridgeConnectionMode.direct ? 100 : 200,
      complete: true,
    );
  }

  bool damagedToday = false;
  final events = <String>[];
  Completer<void>? activateGate;
  @override
  Future<void> activate() async {
    await activateGate?.future;
    events.add('activate');
  }

  @override
  Future<void> deactivate() async {
    events.add('deactivate');
  }

  @override
  Future<BridgeCachedToday?> readToday({
    required BridgeConnectionMode route,
  }) async {
    reads.add(route);
    if (damagedToday)
      throw const BridgeError(
        code: BridgeErrorCode.internalError,
        kind: BridgeErrorKind.internal,
        retryable: false,
        message: '合成缓存损坏',
      );
    return BridgeCachedToday(
      data: const [BridgeTodayClass(bizName: '合成课表', time: '08:00')],
      sourceRoute: route,
      date: '2026-09-21',
      fetchedAt: 1700000000,
      complete: true,
    );
  }

  @override
  Future<BridgeCachedJudge?> readJudge({
    required BridgeConnectionMode route,
    required bool includeExpired,
  }) async {
    expiredReads.add(includeExpired);
    return BridgeCachedJudge(
      data: const [
        BridgeJudgeAssignmentSummary(
          courseId: '12',
          courseName: '合成课程',
          assignmentId: '101',
          title: '已保存的合成作业',
          totalProblems: 3,
          submittedCount: 2,
          submissionStatus: BridgeJudgeSubmissionStatus.partial,
          submissionStatusText: '进行中',
        ),
      ],
      sourceRoute: route,
      includeExpired: includeExpired,
      fetchedAt: 1700000000,
      complete: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
