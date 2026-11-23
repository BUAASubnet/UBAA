import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

import '../../support/bridge/fixtures.dart' show currentBridgeContractVersion;

void main() {
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  setUp(() => api.cache = _Cache());
  Future<BridgeBackend> backend() async {
    final value = BridgeBackend(_Client(), configDirectory: '/synthetic');
    await value.openOfflineAccount(
      const LocalAccount(id: 'synthetic', username: 'fixture-user'),
      List.filled(32, 1),
    );
    return value;
  }

  test('学期周次考试与教室缓存保持参数、筛选和原字段', () async {
    final value = await backend();
    final terms = await value.readCachedQuery(
      FeatureId.schedule,
      const FeatureQuery(view: FeatureQueryView.scheduleTerms),
      RoutePolicy.direct,
    );
    expect(terms.projection!.details.single.title, '合成学期');
    final weeks = await value.readCachedQuery(
      FeatureId.schedule,
      const FeatureQuery(
        view: FeatureQueryView.scheduleWeeks,
        term: '2025-2026-1',
      ),
      RoutePolicy.direct,
    );
    expect(
      (weeks.projection!.details.single.presentation as WeekPresentation)
          .responseTerm,
      'response-term',
    );
    final week = await value.readCachedQuery(
      FeatureId.schedule,
      const FeatureQuery(
        view: FeatureQueryView.scheduleWeek,
        term: '2025-2026-1',
        week: 3,
      ),
      RoutePolicy.direct,
    );
    expect(week.projection!.details.single.title, '合成课程');
    final timeline = week.projection!.overview! as ScheduleWeekOverview;
    final standard = scheduleSectionTimes(
      courses: const [],
    ).map((time) => (time.section, time.start, time.end));
    expect(
      timeline.sectionTimes.map((time) => (time.section, time.start, time.end)),
      standard,
    );
    expect(
      (week.projection!.toSnapshot().overview! as ScheduleWeekOverview)
          .sectionTimes
          .map((time) => (time.section, time.start, time.end)),
      standard,
    );
    final exams = await value.readCachedQuery(
      FeatureId.exam,
      const FeatureQuery(
        term: '2025-2026-1',
        view: FeatureQueryView.examNotArranged,
      ),
      RoutePolicy.direct,
    );
    expect(exams.projection!.details.single.title, '待定考试');
    expect(
      (exams.projection!.details.single.presentation as ExamPresentation)
          .requestTerm,
      '2025-2026-1',
    );
    final rooms = await value.readCachedQuery(
      FeatureId.classroom,
      FeatureQuery(
        date: DateTime(2026, 9, 22),
        campus: 2,
        floorId: '楼一',
        section: '3',
      ),
      RoutePolicy.direct,
    );
    expect(rooms.projection!.details.single.title, 'A');
    expect(rooms.projection!.scopeDate, '2026-09-22');
    expect(
      api.cache.scopes,
      containsAll([
        'weeks:2025-2026-1',
        'week:2025-2026-1:3',
        'exams:2025-2026-1',
        'rooms:2:2026-09-22',
      ]),
    );
  });
  test('缺省学期只从同路线缓存唯一当前项解析，无当前项不猜第一学期', () async {
    final value = await backend();
    final read = await value.readCachedQuery(
      FeatureId.grades,
      const FeatureQuery(),
      RoutePolicy.direct,
    );
    expect(
      (read.projection!.overview! as GradesTermOverview).requestTerm,
      '2025-2026-1',
    );
    api.cache.selected = false;
    final absent = await value.readCachedQuery(
      FeatureId.grades,
      const FeatureQuery(),
      RoutePolicy.direct,
    );
    expect(absent.projection, isNull);
  });
  test('磁盘成绩保留完整学期概览，已出筛选不丢待出项目且没有在线观察', () async {
    final value = await backend();
    final read = await value.readCachedQuery(
      FeatureId.grades,
      const FeatureQuery(
        term: '2025-2026-1',
        view: FeatureQueryView.gradesScored,
      ),
      RoutePolicy.direct,
    );
    final snapshot = read.projection!.toSnapshot();
    expect(snapshot.details.length, 1);
    expect((snapshot.overview as GradesTermOverview).grades.length, 2);
    expect(snapshot.evidence!.origin, DataOrigin.persisted);
    expect(snapshot.updatedAt!.millisecondsSinceEpoch, 100000);
    expect(snapshot.details.expand((entry) => entry.actions), isEmpty);
  });
  test('在线成绩使用持久刷新出口并分开报告保存失败', () async {
    final value = await backend();
    final result = await value.loadFeatureQuery(
      FeatureId.grades,
      const FeatureQuery(term: '2025-2026-1'),
    );
    expect(result.error, isNull);
    expect(result.evidence!.origin, DataOrigin.online);
    expect(result.evidence!.savedForOffline, isFalse);
    expect(result.evidence!.fetchedAt.millisecondsSinceEpoch, 200000);
  });

  test('课表刷新被较新请求替代时保留内容和状态，不返回读取错误', () async {
    final value = await backend();
    const requests = [
      (FeatureQuery(view: FeatureQueryView.scheduleToday), '已保存的今日课程'),
      (
        FeatureQuery(
          view: FeatureQueryView.scheduleWeek,
          term: '2025-2026-1',
          week: 3,
        ),
        '已保存的本周课程',
      ),
    ];
    for (final (query, course) in requests) {
      final result = await value.loadFeatureQuery(FeatureId.schedule, query);
      expect(result.error, isNull);
      expect(result.details.single.title, course);
      expect(result.resolvedRoute, ConnectionMode.webvpn);
      expect(result.evidence!.fetchedAt.millisecondsSinceEpoch, 100000);
      expect(result.evidence!.cacheFailure, CacheMaintenanceFailure.superseded);
    }
  });
}

const grades = BridgeGradeData(
  termCode: '2025-2026-1',
  grades: [
    BridgeGrade(courseName: '已出', score: '90', credit: 2),
    BridgeGrade(courseName: '待出', credit: 1),
  ],
);

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

class _Cache implements BridgeOfflineCache {
  @override
  Future<void> close() async {}

  @override
  void dispose() {}

  bool selected = true;
  final scopes = <String>[];
  @override
  Future<BridgeCachedAcademicTerms?> readExamTerms({
    required BridgeConnectionMode route,
  }) => readAcademicTerms(route: route);
  @override
  Future<BridgeCachedAcademicTerms?> readAcademicTerms({
    required BridgeConnectionMode route,
  }) async => BridgeCachedAcademicTerms(
    data: [
      BridgeTerm(
        itemCode: '2025-2026-1',
        itemName: '合成学期',
        selected: selected,
        itemIndex: 1,
      ),
    ],
    sourceRoute: route,
    fetchedAt: 100,
    complete: true,
  );
  @override
  Future<BridgeCachedAcademicWeeks?> readAcademicWeeks({
    required BridgeConnectionMode route,
    required String term,
  }) async {
    scopes.add('weeks:$term');
    return BridgeCachedAcademicWeeks(
      data: const [
        BridgeWeek(
          startDate: '2026-09-01',
          endDate: '2026-09-07',
          term: 'response-term',
          curWeek: true,
          serialNumber: 3,
          name: '第三周',
        ),
      ],
      sourceRoute: route,
      fetchedAt: 100,
      complete: true,
    );
  }

  @override
  Future<BridgeCachedAcademicWeek?> readAcademicWeek({
    required BridgeConnectionMode route,
    required String term,
    required int week,
  }) async {
    scopes.add('week:$term:$week');
    return BridgeCachedAcademicWeek(
      data: const BridgeWeeklySchedule(
        sectionTimes: [
          BridgeSectionTime(section: 1, start: "09:00", end: "09:45"),
          BridgeSectionTime(section: 14, start: "22:00", end: "22:45"),
        ],
        arrangedList: [BridgeCourseClass(courseCode: 'C', courseName: '合成课程')],
        code: 'response-code',
        name: '周表',
      ),
      sourceRoute: route,
      fetchedAt: 100,
      complete: true,
    );
  }

  @override
  Future<BridgeCachedAcademicExams?> readAcademicExams({
    required BridgeConnectionMode route,
    required String term,
  }) async {
    scopes.add('exams:$term');
    return BridgeCachedAcademicExams(
      data: const BridgeExamArrangement(
        arranged: [BridgeExam(courseName: '已安排')],
        notArranged: [BridgeExam(courseName: '待定考试')],
      ),
      sourceRoute: route,
      fetchedAt: 100,
      complete: true,
    );
  }

  @override
  Future<BridgeCachedAcademicClassrooms?> readAcademicClassrooms({
    required BridgeConnectionMode route,
    required int campus,
    required String date,
  }) async {
    scopes.add('rooms:$campus:$date');
    return BridgeCachedAcademicClassrooms(
      data: const BridgeClassroomQuery(
        code: 0,
        message: '',
        floors: [
          BridgeClassroomFloor(
            name: '楼一',
            rooms: [
              BridgeClassroomInfo(
                id: 'a',
                floorId: '1',
                name: 'A',
                availableSections: '3,4',
              ),
              BridgeClassroomInfo(
                id: 'b',
                floorId: '1',
                name: 'B',
                availableSections: '13',
              ),
            ],
          ),
        ],
      ),
      sourceRoute: route,
      fetchedAt: 100,
      complete: true,
    );
  }

  @override
  Future<void> activate() async {}
  @override
  Future<BridgeCachedAcademicGradesOverview?> readAcademicGradesOverview({
    required BridgeConnectionMode route,
  }) async => null;
  @override
  Future<BridgeCachedAcademicGrades?> readAcademicGrades({
    required BridgeConnectionMode route,
    required String term,
  }) async => BridgeCachedAcademicGrades(
    data: grades,
    sourceRoute: route,
    fetchedAt: 100,
    complete: true,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements BridgeClient {
  static const _cacheRoute = BridgeRouteDecision(
    policy: BridgeRoutePolicy.webVpn,
    resolvedRoute: BridgeConnectionMode.webVpn,
    network: BridgeNetworkState.unknown,
    initialRoute: BridgeConnectionMode.webVpn,
    usedFallback: false,
  );

  @override
  int contractVersion() => currentBridgeContractVersion;

  @override
  Future<BridgeTodayRefresh> scheduleTodayCached({
    required BridgeOfflineCache cache,
  }) async => const BridgeTodayRefresh(
    result: BridgeRoutedTodayClasses(
      data: [BridgeTodayClass(bizName: '已保存的今日课程')],
      route: _cacheRoute,
    ),
    date: '2026-09-22',
    fetchedAt: 100,
    saveError: BridgeCacheFailure.superseded,
  );

  @override
  Future<BridgeAcademicWeekRefresh> academicWeekCached({
    required BridgeOfflineCache cache,
    required String term,
    required int week,
  }) async => const BridgeAcademicWeekRefresh(
    result: BridgeRoutedWeeklySchedule(
      data: BridgeWeeklySchedule(
        arrangedList: [
          BridgeCourseClass(courseCode: 'C', courseName: '已保存的本周课程'),
        ],
        sectionTimes: [],
        code: '3',
        name: '第三周',
      ),
      route: _cacheRoute,
    ),
    fetchedAt: 100,
    complete: true,
    saveError: BridgeCacheFailure.superseded,
  );
  @override
  Future<BridgeRoutedGradeOverview> gradesOverview() async =>
      const BridgeRoutedGradeOverview(
        data: BridgeGradeOverview(
          graduate: false,
          grades: [],
          statistics: null,
          terms: [],
        ),
        route: BridgeRouteDecision(
          policy: BridgeRoutePolicy.direct,
          resolvedRoute: BridgeConnectionMode.direct,
          network: BridgeNetworkState.unknown,
          initialRoute: BridgeConnectionMode.direct,
          usedFallback: false,
        ),
      );
  @override
  Future<BridgeAcademicGradesOverviewRefresh> academicGradesOverviewCached({
    required BridgeOfflineCache cache,
  }) async => BridgeAcademicGradesOverviewRefresh(
    result: await gradesOverview(),
    fetchedAt: 200,
    complete: true,
    saveError: null,
  );
  @override
  Future<BridgeAcademicGradesRefresh> academicGradesCached({
    required BridgeOfflineCache cache,
    required String term,
  }) async => const BridgeAcademicGradesRefresh(
    result: BridgeRoutedGrades(
      data: grades,
      route: BridgeRouteDecision(
        policy: BridgeRoutePolicy.direct,
        resolvedRoute: BridgeConnectionMode.direct,
        network: BridgeNetworkState.unknown,
        initialRoute: BridgeConnectionMode.direct,
        usedFallback: false,
      ),
    ),
    fetchedAt: 200,
    complete: true,
    saveError: BridgeCacheFailure.capacity,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
