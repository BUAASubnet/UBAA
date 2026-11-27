import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  const term = '2026-2027-1';
  const name = '数学（上）';
  const catalog = [
    SpocCourse(courseId: 'k1', name: name, courseCode: 'A'),
    SpocCourse(courseId: 'k2', name: name, courseCode: 'A'),
    SpocCourse(courseId: 'k3', name: '单列'),
  ];
  FeatureDetail slot(String code, int day) => FeatureDetail(
    title: code == 'A' ? name : '物理',
    presentation: ScheduleCoursePresentation(
      courseCode: code,
      dayOfWeek: day,
      beginSection: 1,
      endSection: 2,
      beginTime: '08:00',
      endTime: '09:35',
      place: '一教',
    ),
  );
  FeatureDetail spoc(String id) => FeatureDetail(
    title: '练习',
    presentation: SpocAssignmentPresentation(
      courseId: id,
      courseName: name,
      assignmentId: 's$id',
      status: AssignmentSubmissionStatus.unknown,
      statusText: '未知',
    ),
  );
  FeatureDetail judge(String id, String start, String due) => FeatureDetail(
    title: '练习',
    presentation: JudgeAssignmentPresentation(
      courseId: id,
      courseName: ' 数 学 (上) ',
      assignmentId: 'j$id',
      startTime: start,
      dueTime: due,
      totalProblems: 1,
      submittedCount: 0,
      status: AssignmentSubmissionStatus.unknown,
      statusText: '未知',
    ),
  );
  CourseHubSnapshot build({
    bool graduate = false,
    String? semester = term,
    bool imported = true,
    bool ambiguous = false,
    Set<String> overrides = const {},
  }) => buildCourseHub(
    termCode: semester,
    graduate: graduate,
    now: DateTime.parse('2026-09-07T10:00:00+08:00'),
    spocCourses: [
      ...catalog,
      if (ambiguous) const SpocCourse(courseId: 'k4', name: name),
    ],
    weeks: imported
        ? [
            for (final day in [7, 14])
              CourseHubWeek(
                startDate: '2026-09-$day'.replaceFirst('-7', '-07'),
                endDate: '2026-09-${day + 6}',
                slots: [slot('B', 3), slot('A', 1)],
              ),
          ]
        : [],
    spocAssignments: [spoc('k2'), spoc('missing')],
    judgeAssignments: [
      judge('first', '2026-09-06T16:00:00Z', ''),
      judge('last', '', '2026-09-20 23:59:59'),
      judge('span', '2026-09-01', '2026-09-21'),
      judge('old', '', '2025-09-15'),
    ],
    exams: [
      for (final code in [term, 'old'])
        FeatureDetail(
          title: '考试',
          presentation: ExamPresentation(
            arranged: true,
            courseNo: 'A',
            requestTerm: code,
          ),
        ),
    ],
    grades: [
      for (final code in [term, 'old'])
        FeatureDetail(
          title: '成绩',
          presentation: GradePresentation(courseCode: 'A', termCode: code),
        ),
    ],
    overrides: overrides,
    sources: const {
      CourseHubSource.grades: CourseHubSourceStatus(
        CourseHubSourceState.failed,
      ),
    },
  );

  test('同代码合并、顺序稳定、排课跨周去重，摘要全部保留且按学期归属', () {
    final hub = build();
    expect(hub.courses.map((course) => course.key), [
      'code:A',
      'code:B',
      'kcid:k3',
    ]);
    final course = hub.courses.first;
    expect(course.spocCourses.length, 2);
    expect(course.slots.length, 1);
    expect(
      course.nextClass!.start,
      DateTime.parse('2026-09-14T08:00:00+08:00'),
    );
    expect(course.assignments.length, 3);
    expect(hub.allAssignments.map((item) => item.courseName), [
      name,
      null,
      name,
      name,
      null,
      null,
    ]);
    expect(course.grades.length, 1);
    expect(course.exams.length, 1);
    expect(
      hub.sources[CourseHubSource.grades]!.state,
      CourseHubSourceState.failed,
    );
  });
  test('身份未知不使用课表和希冀匹配，仍保留两源摘要', () {
    final hub = buildCourseHub(
      graduate: null,
      termCode: term,
      now: DateTime.utc(2026, 9, 7),
      spocCourses: catalog,
      weeks: [
        CourseHubWeek(
          startDate: '2026-09-07',
          endDate: '2026-09-13',
          slots: [slot('B', 1)],
        ),
      ],
      judgeAssignments: [judge('j', '', '2026-09-09')],
      spocAssignments: [spoc('k1')],
    );
    expect(hub.graduate, isNull);
    expect(hub.courses.expand((course) => course.slots), isEmpty);
    expect(hub.allAssignments.map((item) => item.courseKey), ['code:A', null]);
  });
  test('取消关联可恢复，一对多不猜测', () {
    final course = build(overrides: {'first'}).courses.first;
    expect(
      course.judgeLinks
          .singleWhere((link) => link.judgeCourseId == 'first')
          .linked,
      false,
    );
    expect(course.assignments.length, 2);
    expect(build().courses.first.assignments.length, 3);
    expect(
      build(ambiguous: true).courses.expand((course) => course.judgeLinks),
      isEmpty,
    );
  });
  test('研究生、未导入和学期未知只列 SPOC 课程，保留全部作业', () {
    for (final hub in [
      build(graduate: true),
      build(imported: false),
      build(semester: null),
    ]) {
      expect(
        hub.courses.map((course) => course.key),
        unorderedEquals(['code:A', 'kcid:k3']),
      );
      expect(hub.courses.expand((course) => course.slots), isEmpty);
      expect(hub.courses.expand((course) => course.judgeLinks), isEmpty);
      expect(hub.allAssignments.length, 6);
    }
  });
}
