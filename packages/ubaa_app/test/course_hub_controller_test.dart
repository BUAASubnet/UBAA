import 'dart:async';
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
  bool overridesFail = false;
  Future<List<SpocCourse>> Function() catalog = () async => const [
    SpocCourse(courseId: 'k', name: '合成课程', courseCode: 'A'),
  ];
  @override
  Future<SpocRead<List<SpocCourse>>> courses() async {
    calls++;
    return (data: await catalog(), route: ConnectionMode.direct);
  }

  @override
  Future<List<CourseHubWeek>> courseHubWeeks(
    String account,
    ConnectionMode route,
    String term,
  ) async {
    weekReads++;
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
            ),
          ),
        ],
      ),
    ];
  }

  @override
  Future<List<String>> courseHubOverrides(String account, String term) async {
    if (overridesFail) throw StateError('合成读取失败');
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Controller extends AppController {
  _Controller(_Backend backend) : super(backend: backend);
  @override
  String get cacheAccountId => 'synthetic';
}

void main() {
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
