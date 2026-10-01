import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  final cache = _Cache();
  setUpAll(() => RustLib.initMock(api: _Api(cache)));
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
    final exams = await value.readCachedQuery(
      FeatureId.exam,
      const FeatureQuery(
        term: '2025-2026-1',
        view: FeatureQueryView.examNotArranged,
      ),
      RoutePolicy.direct,
    );
    expect(exams.projection!.details.single.title, '待定考试');
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
      cache.scopes,
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
    cache.selected = false;
    final absent = await value.readCachedQuery(
      FeatureId.grades,
      const FeatureQuery(),
      RoutePolicy.direct,
    );
    expect(absent.projection, isNull);
    cache.selected = true;
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
}

const grades = BridgeGradeData(
  termCode: '2025-2026-1',
  grades: [
    BridgeGrade(courseName: '已出', score: '90', credit: 2),
    BridgeGrade(courseName: '待出', credit: 1),
  ],
);

class _Api implements RustLibApi {
  _Api(this.cache);
  final _Cache cache;
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
  bool selected = true;
  final scopes = <String>[];
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
  @override
  int contractVersion() => 38;
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
