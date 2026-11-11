import 'dart:typed_data';

import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

import 'promo_agenda.dart';
import 'promo_data.dart';
import 'promo_schoolwork.dart';

/// 日程需要已打开的本机账号；这里直接提供固定索引，不访问钥匙串或磁盘。
final class PromoAccountStore implements LocalAccountStore {
  const PromoAccountStore();

  @override
  Future<LocalAccountState> read() async => const LocalAccountState(
    account: LocalAccount(id: storeUsername, username: storeUsername),
    canRestore: true,
    generation: 1,
  );

  @override
  Future<LocalAccountState> retain(
    String username, {
    required bool retainSession,
  }) => _readOnly();

  @override
  Future<Uint8List> cacheKey(LocalAccount account) => _readOnly();

  @override
  Future<void> signOut() => _readOnly();

  @override
  Future<void> removeAccount(String accountId) => _readOnly();

  Future<T> _readOnly<T>() async => throw UnsupportedError('示例账号仅供读取');
}

/// 宣传图从应用宿主进入正常页面，所有账号与查询均在内存中替换为示例数据。
final class PromoBackend
    implements
        UbaaBackend,
        FeatureQueryBackend,
        HomeTodoBackend,
        AgendaProvider {
  @override
  final agenda = AgendaService(PromoAgenda());

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;

  @override
  Future<UserSummary> userInfo() async => const UserSummary(
    username: storeUsername,
    displayName: storeDisplayName,
    department: '计算机学院',
  );

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async =>
      throw const BackendException(UbaaErrorCode.unsupported);

  @override
  Future<void> logout() async {}

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) =>
      loadFeatureQuery(feature, const FeatureQuery());

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async => switch (feature) {
    FeatureId.schedule => _schedule(query),
    FeatureId.grades => _grades(query),
    FeatureId.exam => _exams(query),
    FeatureId.spoc => _spoc(query),
    _ => _result([]),
  };

  @override
  Future<HomeTodoProjection> projectHomeTodos(HomeTodoRequest request) async {
    final assignmentIds = request.snapshots[FeatureId.spoc]?.details
        .map((row) => row.presentation)
        .whereType<SpocAssignmentPresentation>()
        .map((row) => row.assignmentId)
        .toSet();
    final todos = <HomeTodo>[
      for (final assignment in storeAssignments)
        if (!assignment.submitted &&
            (assignmentIds?.contains(assignment.id) ?? false))
          formatHomeTodo(
            storeAssignmentAgenda(assignment),
            now: homeCampusTime(request.now),
            navigation: assignment.navigation,
          ),
    ];
    todos.sort((a, b) => a.sortTime.compareTo(b.sortTime));
    return HomeTodoProjection(todos);
  }
}

FeatureResult _schedule(FeatureQuery query) {
  final term = query.term ?? storeTerm;
  final week = query.week ?? storeWeek;
  return switch (query.view) {
    FeatureQueryView.scheduleTerms => _result(_terms),
    FeatureQueryView.scheduleWeeks => _result(term == storeTerm ? _weeks : []),
    FeatureQueryView.scheduleWeek => _result([
      if (term == storeTerm)
        for (final course in storeCourses)
          if (course.occursIn(week))
            FeatureDetail(
              title: course.name,
              presentation: ScheduleCoursePresentation(
                courseCode: course.code,
                credit: course.credit,
                dayOfWeek: course.day,
                beginSection: course.begin,
                endSection: course.end,
                beginTime: course.beginTime,
                endTime: course.endTime,
                place: course.place,
                weeksAndTeachers: course.weeksAndTeachers,
                color: course.color,
              ),
            ),
    ], overview: ScheduleWeekOverview(code: term, sectionTimes: storeSections)),
    FeatureQueryView.summary || FeatureQueryView.scheduleToday => _scheduleDay(
      term,
      query.date ?? storeNow,
    ),
    _ => _result([]),
  };
}

FeatureResult _scheduleDay(String term, DateTime instant) {
  final day = homeCampusTime(instant);
  final week = homeWeekOn(
    _weeks.map((d) => d.presentation).whereType<WeekPresentation>(),
    day,
    term: term,
  );
  return _result([
    if (week != null)
      for (final course in storeCourses)
        if (course.day == day.weekday && course.occursIn(week.number))
          FeatureDetail(
            title: course.name,
            presentation: TodayCoursePresentation(
              time: course.time,
              place: course.place,
            ),
          ),
  ], scopeDate: storeDateKey(day));
}

final _weeks = <FeatureDetail>[
  for (var week = 1; week <= storeWeekCount; week++)
    FeatureDetail(
      title: '第 $week 周',
      presentation: WeekPresentation(
        requestTerm: storeTerm,
        responseTerm: storeTerm,
        number: week,
        current: week == storeWeek,
        startDate: storeDateKey(storeDate(week, 1)),
        endDate: storeDateKey(storeDate(week, 7)),
      ),
    ),
];

final _terms = [
  _term(storeTerm, 1),
  _term(storePreviousTerm, 2),
  _term(storeEarlierTerm, 3),
];

FeatureDetail _term(String code, int index) {
  final [first, second, part] = code.split('-');
  return FeatureDetail(
    title: '$first–$second 学年${part == '1' ? '秋季' : '春季'}学期',
    presentation: TermPresentation(
      code: code,
      selected: index == 1,
      index: index,
    ),
  );
}

FeatureResult _grades(FeatureQuery query) {
  if (query.view == FeatureQueryView.gradesTerms) {
    return _result(_terms);
  }
  final term = query.term ?? storeTerm;
  final grades = storeGrades(term);
  final overview = GradesTermOverview(
    requestTerm: term,
    termCode: term,
    grades: grades,
  );
  if (query.view == FeatureQueryView.gradesOverview) return _result([]);
  return _result([
    for (final grade in grades)
      if (switch (query.view) {
        FeatureQueryView.gradesScored => grade.score != null,
        FeatureQueryView.gradesMissing => grade.score == null,
        _ => true,
      })
        FeatureDetail(title: grade.courseName!, presentation: grade),
  ], overview: overview);
}

FeatureResult _exams(FeatureQuery query) {
  if (query.view == FeatureQueryView.examTerms) {
    return _result([_term(storeTerm, 1)]);
  }
  if (query.term != null && query.term != storeTerm) return _result([]);
  return _result([
    if (query.view != FeatureQueryView.examNotArranged)
      for (final exam in storeExams) exam.detail,
    if (query.view != FeatureQueryView.examArranged)
      for (final code in ['CS2105', 'EN2003'])
        FeatureDetail(
          title: storeCourse(code).name,
          presentation: ExamPresentation(
            arranged: false,
            requestTerm: storeTerm,
            courseNo: code,
          ),
        ),
  ]);
}

FeatureResult _spoc(FeatureQuery query) => _result([
  for (final assignment in storeAssignments)
    if (query.view != FeatureQueryView.spocDetail ||
        query.assignmentId == assignment.id)
      assignment.detail(expanded: query.view == FeatureQueryView.spocDetail),
], overview: const SpocTermOverview(termCode: storeTerm, termName: '秋季学期'));

FeatureResult _result(
  List<FeatureDetail> details, {
  FeatureOverview? overview,
  String? scopeDate,
}) {
  final evidence = DataEvidence(
    accountId: storeUsername,
    origin: DataOrigin.online,
    fetchedAt: storeNow,
    complete: true,
    savedForOffline: false,
    scopeDate: scopeDate,
  );
  return details.isEmpty
      ? FeatureResult.empty(
          overview: overview,
          evidence: evidence,
          resolvedRoute: ConnectionMode.direct,
        )
      : FeatureResult.success(
          details: details,
          overview: overview,
          evidence: evidence,
          resolvedRoute: ConnectionMode.direct,
        );
}
