import 'dart:async';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/src/contracts/course_hub.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'support/controller/grades.dart';

class _Backend extends FixtureGradesBackend
    implements CourseHubBackend, SpocFilesBackend, SpocFilesService {
  @override
  SpocFilesService get spocFiles => this;
  @override
  void Function(bool?)? onAcademicIdentity;
  int calls = 0, weekReads = 0;
  bool overridesFail = false, weeksFail = false;
  bool emptyWeeks = false;
  ConnectionMode readRoute = ConnectionMode.direct;
  Completer<List<String>>? overrideRead;
  final writes = <bool>[];
  Completer<void>? saving;
  @override
  Future<void> saveCourseHubLink(
    String account,
    String term,
    String id,
    bool linked,
  ) async {
    writes.add(linked);
    await saving?.future;
  }

  Future<List<SpocCourse>> Function() catalog = () async => const [
    SpocCourse(courseId: 'k', name: '合成课程', courseCode: 'A'),
  ];
  @override
  Future<SpocRead<List<SpocCourse>>> courses() async {
    calls++;
    return (data: await catalog(), route: readRoute);
  }

  @override
  Future<List<CourseHubWeek>> courseHubWeeks(
    String account,
    ConnectionMode route,
    String term,
  ) async {
    weekReads++;
    if (weeksFail) throw StateError('合成排课读取失败');
    if (emptyWeeks) return [];
    return const [
      CourseHubWeek(
        startDate: '2026-09-07',
        endDate: '2026-09-13',
        slots: [
          FeatureDetail(
            title: '合成课程',
            presentation: ScheduleCoursePresentation(
              courseCode: 'A',
              dayOfWeek: 1,
              beginTime: '08:00',
            ),
          ),
        ],
      ),
    ];
  }

  @override
  Future<List<String>> courseHubOverrides(String account, String term) async {
    if (overridesFail) throw StateError('合成读取失败');
    return overrideRead?.future ?? Future.value([]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Controller extends AppController {
  _Controller(_Backend backend) : super(backend: backend);
  @override
  String get cacheAccountId => user?.username ?? 'synthetic';
  @override
  Future<void> refreshHome({Iterable<FeatureId>? only}) async {
    expect(only, [FeatureId.spoc, FeatureId.judge]);
  }
}

void main() {
  late _Backend backend;
  late _Controller app;
  late CourseHubController hub;
  void term(String code) => app.internalAgendaSchoolScope = (
    accountId: app.cacheAccountId,
    routeGeneration: app.internalRoutePolicyGeneration,
    term: code,
    route: ConnectionMode.direct,
  );
  Future<void> settle() => Future<void>.delayed(Duration.zero);
  setUp(() {
    backend = _Backend();
    app = _Controller(backend)
      ..internalPhase = AppPhase.home
      ..internalUser = const UserSummary(username: 'synthetic');
    term('term');
    hub = CourseHubController(app);
    addTearDown(() {
      hub.dispose();
      app.dispose();
    });
  });
  test('已知身份忽略空值，同账号路线与缓存代次变化保留，换号清空', () async {
    hub.ensureLoaded();
    backend.onAcademicIdentity!(false);
    backend.onAcademicIdentity!(null);
    expect(hub.value.graduate, false);
    app.internalRoutePolicyGeneration++;
    app.internalNotify();
    expect(hub.value.graduate, false);
    app.internalBusinessCacheEpoch++;
    app.internalNotify();
    expect(hub.value.graduate, false);
    app.internalUser = const UserSummary(username: 'second');
    app.internalNotify();
    expect(hub.value.graduate, isNull);
    await settle();
  });
  test('学期和自动路线就绪不重读目录，自动回落可用', () async {
    app.internalHomeDefaults[FeatureId.spoc] = const FeatureSnapshot(
      feature: FeatureId.spoc,
      resolvedRoute: ConnectionMode.direct,
    );
    backend.readRoute = ConnectionMode.webvpn;
    hub.ensureLoaded();
    await settle();
    expect(hub.value.courses.single.spocCourses.single.courseId, 'k');
    term('next');
    app.internalHomeDefaults[FeatureId.spoc] = const FeatureSnapshot(
      feature: FeatureId.spoc,
      resolvedRoute: ConnectionMode.webvpn,
    );
    app.internalNotify();
    await settle();
    expect(backend.calls, 1);
  });
  test('换号后旧课程目录不能覆盖新账号', () async {
    final first = Completer<List<SpocCourse>>();
    backend.catalog = () => first.future;
    hub.ensureLoaded();
    backend.catalog = () async => const [
      SpocCourse(courseId: 'new', name: '新课程'),
    ];
    app.internalUser = const UserSummary(username: 'second');
    app.internalNotify();
    await settle();
    first.complete(const [SpocCourse(courseId: 'old', name: '旧课程')]);
    await settle();
    expect(hub.value.courses.single.name, '新课程');
  });
  test('刷新期间和排课读取失败后保留旧数据', () async {
    backend.onAcademicIdentity!(false);
    hub.ensureLoaded();
    await settle();
    backend.weeksFail = true;
    final refresh = hub.refresh();
    expect(hub.value.courses.single.slots, hasLength(1));
    await refresh;
    expect(hub.value.courses.single.slots, hasLength(1));
    expect(
      hub.value.sources[CourseHubSource.schedule]?.state,
      CourseHubSourceState.partial,
    );
  });
  test('关联写入串行，迟到的覆盖读取不撤销已经保存的开关', () async {
    app.internalHomeDefaults[FeatureId.judge] = FeatureSnapshot(
      feature: FeatureId.judge,
      details: [
        FeatureDetail(
          title: '作业',
          presentation: JudgeAssignmentPresentation(
            courseId: 'judge',
            courseName: '合成课程',
            assignmentId: 'item',
            dueTime: '2026-09-08',
            totalProblems: 1,
            submittedCount: 0,
            status: AssignmentSubmissionStatus.unsubmitted,
            statusText: '未交',
          ),
        ),
      ],
    );
    backend.onAcademicIdentity!(false);
    hub.ensureLoaded();
    await settle();
    final pending = backend.overrideRead = Completer<List<String>>();
    final saving = backend.saving = Completer<void>();
    final refresh = hub.refresh();
    await settle();
    final off = hub.setJudgeLink('code:A', 'judge', false);
    final on = hub.setJudgeLink('code:A', 'judge', true);
    await settle();
    expect(backend.writes, [false]);
    saving.complete();
    await Future.wait([off, on]);
    expect(backend.writes, [false, true]);
    pending.complete(['judge']);
    await refresh;
    expect(hub.value.courses.single.judgeLinks.single.linked, isTrue);
  });
  test('覆盖读取失败时保留上次完整读取的排课', () async {
    backend.onAcademicIdentity!(false);
    hub.ensureLoaded();
    await settle();
    backend
      ..emptyWeeks = true
      ..overridesFail = true;
    await hub.refresh();
    expect(hub.value.courses.single.scheduleLinked, true);
    expect(
      hub.value.sources[CourseHubSource.schedule]?.state,
      CourseHubSourceState.partial,
    );
  });
  test('成绩往年查询和学期列表不能标记本学期已加载', () async {
    hub.ensureLoaded();
    for (final query in [
      const FeatureQuery(term: 'old'),
      const FeatureQuery(view: FeatureQueryView.gradesTerms),
    ]) {
      app.internalSnapshots[FeatureId.grades] = FeatureSnapshot(
        feature: FeatureId.grades,
        status: FeatureLoadStatus.success,
        readContext: FeatureReadContext(query: query, requestRevision: 1),
      );
      app.internalNotify();
      expect(
        hub.value.sources[CourseHubSource.grades]?.state,
        CourseHubSourceState.notLoaded,
      );
    }
    await settle();
  });
  testWidgets('分钟重算无变化时不通知，离页不留下周期定时器', (tester) async {
    hub.ensureLoaded();
    await tester.pump();
    var notifications = 0;
    hub.addListener(() => notifications++);
    await tester.pump(const Duration(minutes: 1));
    expect(notifications, 0);
    hub.leave();
  });
  test('前台恢复立即移除已开始的课次', () async {
    var now = DateTime.utc(2026, 9, 6);
    await withClock(Clock(() => now), () async {
      backend.onAcademicIdentity!(false);
      hub.ensureLoaded();
      await settle();
      expect(hub.value.courses.single.nextClass, isNotNull);
      app.setAppForeground(false);
      now = DateTime.utc(2026, 9, 8);
      app.setAppForeground(true);
      expect(hub.value.courses.single.nextClass, isNull);
      hub.leave();
      hub.ensureLoaded();
      expect(backend.calls, 1);
      hub.leave();
    });
  });
  test('首次需要才读课程，身份确认后加载课表，覆盖失败保留排课与已读成绩', () async {
    final backend = _Backend()..overridesFail = true;
    final app = _Controller(backend)
      ..internalPhase = AppPhase.home
      ..internalUser = const UserSummary(username: 'synthetic')
      ..internalAgendaSchoolScope = (
        accountId: 'synthetic',
        routeGeneration: 0,
        term: 'term',
        route: ConnectionMode.direct,
      );
    app.internalSnapshots[FeatureId.grades] = const FeatureSnapshot(
      feature: FeatureId.grades,
      status: FeatureLoadStatus.success,
      overview: GradesTermOverview(
        requestTerm: 'term',
        termCode: 'term',
        grades: [],
      ),
      details: [
        FeatureDetail(
          title: '成绩',
          presentation: GradePresentation(courseCode: 'A', termCode: 'term'),
        ),
      ],
    );
    final hub = CourseHubController(app);
    addTearDown(() {
      hub.dispose();
      app.dispose();
    });
    expect(backend.calls, 0);
    hub.ensureLoaded();
    await Future<void>.delayed(Duration.zero);
    expect(hub.value.graduate, isNull);
    expect(backend.calls, 1);
    expect(backend.weekReads, 0);
    backend.onAcademicIdentity!(false);
    await Future<void>.delayed(Duration.zero);
    expect(hub.value.courses.single.scheduleLinked, isTrue);
    expect(hub.value.courses.single.grades, hasLength(1));
    backend.catalog = () async => throw StateError('合成课程读取失败');
    await hub.refresh();
    expect(hub.value.courses.single.spocCourses, hasLength(1));
    expect(
      hub.value.sources[CourseHubSource.spocCourses]!.state,
      CourseHubSourceState.failed,
    );
    final pending = Completer<List<SpocCourse>>();
    backend.catalog = () => pending.future;
    final refresh = hub.refresh();
    app.internalPhase = AppPhase.login;
    app.internalNotify();
    pending.complete(const [SpocCourse(courseId: 'old', name: '旧账号课程')]);
    await refresh;
    expect(hub.value.courses, isEmpty);
  });
}
