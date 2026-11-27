import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/course_hub/entries.dart';
import 'package:ubaa_ui/src/features/course_hub/pages.dart';
import 'package:ubaa_ui/src/features/course_hub/study_landing.dart';
import 'package:ubaa_ui/src/features/coursework/assignment_content.dart';
import 'package:ubaa_ui/src/shared/loading.dart';
import 'package:ubaa_ui/src/write_callbacks.dart';

CourseHubAssignment assignment(
  String title, {
  bool judge = false,
  String name = '来源课程',
  String? courseName,
  String? due,
  bool done = false,
  bool detail = false,
}) {
  final status = done
      ? AssignmentSubmissionStatus.submitted
      : AssignmentSubmissionStatus.unsubmitted;
  return CourseHubAssignment(
    feature: judge ? FeatureId.judge : FeatureId.spoc,
    courseName: courseName,
    detail: FeatureDetail(
      title: title,
      presentation: judge
          ? JudgeAssignmentPresentation(
              courseId: 'judge',
              courseName: name,
              assignmentId: title,
              totalProblems: 1,
              submittedCount: 0,
              dueTime: due,
              status: status,
              statusText: '状态',
            )
          : SpocAssignmentPresentation(
              courseId: 'spoc',
              courseName: name,
              assignmentId: title,
              dueTime: due,
              status: status,
              statusText: '状态',
              isDetail: detail,
            ),
    ),
  );
}

CourseHubCourse course(
  String name, {
  bool scheduled = false,
  bool upcoming = false,
  List<CourseHubAssignment> items = const [],
}) => CourseHubCourse(
  key: name,
  name: name,
  courseCode: null,
  credit: null,
  teachers: const [],
  slots: [if (scheduled) const FeatureDetail(title: '排课')],
  nextClass: upcoming
      ? (
          start: DateTime.utc(2099),
          end: null,
          place: '实验室',
          beginSection: 1,
          endSection: 2,
        )
      : null,
  spocCourses: const [SpocCourse(courseId: 'spoc', name: '来源课程')],
  judgeLinks: const [(judgeCourseId: 'judge', name: '关联课程', linked: true)],
  assignments: items,
  exams: const [],
  grades: const [],
);

CourseHubSnapshot snapshot(
  List<CourseHubCourse> courses, {
  bool partial = false,
  List<CourseHubAssignment> all = const [],
}) => CourseHubSnapshot(
  courses: courses,
  allAssignments: all,
  sources: {
    for (final source in CourseHubSource.values)
      source: CourseHubSourceStatus(
        partial && source == CourseHubSource.judgeAssignments
            ? CourseHubSourceState.failed
            : CourseHubSourceState.ready,
      ),
  },
);

Future<void> show(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  testWidgets('学习页保持在读、已结课、仅 SPOC 的顺序；待交数区分来源完整性', (tester) async {
    var retries = 0;
    Future<void> landing(CourseHubSnapshot hub) => show(
      tester,
      CourseHubLanding(
        snapshot: hub,
        onOpenFeature: (_) {},
        onOpenCourse: (_) {},
        onOpenAssignments: () {},
        onOpenSources: () {},
        onRefresh: () async {
          retries++;
        },
      ),
    );
    await landing(const CourseHubSnapshot());
    expect(find.byType(LoadingPlaceholder), findsOneWidget);
    expect(find.textContaining('还没有本学期课程'), findsNothing);
    final courses = [
      course('独立'),
      course('已结课', scheduled: true),
      course('在读', scheduled: true, upcoming: true, items: [assignment('练习')]),
    ];
    for (final partial in [false, true]) {
      await landing(snapshot(courses, partial: partial));
      final positions = [
        for (final name in ['在读', '已结课', '独立'])
          tester.getCenter(find.text(name)).dy,
      ];
      expect(positions[0], lessThan(positions[1]));
      expect(positions[1], lessThan(positions[2]));
      expect(find.text(partial ? '已知 1 项待交' : '1 项待交'), findsOneWidget);
      expect(find.textContaining('0 项待交'), findsNothing);
      expect(find.text('未关联课表'), findsOneWidget);
    }
    expect(find.textContaining('希冀作业暂未加载'), findsOneWidget);
    await tester.tap(find.text('重试'));
    expect(retries, 1);
  });

  testWidgets('课程主页按来源显示待交，截止与已交分组折叠，信息页可取消关联', (tester) async {
    final items = [
      assignment('作业甲'),
      assignment('作业乙', judge: true),
      assignment('截止练习', due: '2000-01-01 08:00'),
      assignment('已交练习', done: true),
    ];
    (String, String, bool)? change;
    Future<void> page(List<CourseHubAssignment> rows, {bool partial = false}) =>
        show(
          tester,
          CourseHubCoursePage(
            snapshot: snapshot([course('合成', items: rows)], partial: partial),
            courseKey: '合成',
            onOpenAssignment: (_) {},
            onOpenFeature: (_) {},
            onSetJudgeLink: (key, id, linked) async {
              change = (key, id, linked);
            },
          ),
        );
    await page(items);
    expect(find.textContaining('没有出现在课表里'), findsOneWidget);
    for (final title in [
      'SPOC 作业 · 1',
      '希冀作业 · 1',
      '作业甲',
      '作业乙',
      '已截止未交（1）',
      '已提交（1）',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('截止练习'), findsNothing);
    expect(find.text('已交练习'), findsNothing);
    await page([], partial: true);
    expect(find.text('没有待交作业'), findsNothing);
    expect(find.text('希冀作业未加载完整'), findsOneWidget);
    await tester.tap(find.text('信息'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('course-hub-judge-judge')));
    expect(change, ('合成', 'judge', false));
  });

  testWidgets('目录与希冀来源未读全时不能把尚未关联误报成没有待交', (tester) async {
    const local = CourseHubCourse(
      key: 'local',
      name: '排课',
      courseCode: 'A',
      credit: null,
      teachers: [],
      slots: [FeatureDetail(title: '排课')],
      nextClass: null,
      spocCourses: [],
      judgeLinks: [],
      assignments: [],
      exams: [],
      grades: [],
    );
    await show(
      tester,
      CourseHubCoursePage(
        snapshot: const CourseHubSnapshot(
          courses: [local],
          sources: {
            CourseHubSource.spocCourses: CourseHubSourceStatus(
              CourseHubSourceState.failed,
            ),
            CourseHubSource.judgeAssignments: CourseHubSourceStatus(
              CourseHubSourceState.failed,
            ),
          },
        ),
        courseKey: 'local',
        onOpenAssignment: (_) {},
        onOpenFeature: (_) {},
      ),
    );
    expect(find.text('没有待交作业'), findsNothing);
    expect(find.textContaining('未加载完整'), findsOneWidget);
  });

  testWidgets('全部作业按课程筛选，未归属项使用来源课程名', (tester) async {
    final items = [
      assignment('已归属', courseName: '本课'),
      assignment('未归属', name: '独立来源'),
    ];
    await show(
      tester,
      CourseHubAssignmentsPage(
        snapshot: snapshot([], all: items),
        onOpenAssignment: (_) {},
      ),
    );
    expect(find.text('独立来源 · SPOC'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '独立来源'));
    await tester.pump();
    expect(find.text('已归属'), findsNothing);
    expect(find.text('未归属'), findsOneWidget);
  });

  testWidgets('作业列表分组标题与详情课程链接打开同一门课', (tester) async {
    final opened = <String>[];
    for (final detail in [false, true]) {
      await show(
        tester,
        CourseHubEntries(
          snapshot: snapshot([course('课程键')]),
          open: opened.add,
          term: 'term',
          child: AssignmentContent(
            details: [assignment('练习', detail: detail).detail],
          ),
        ),
      );
      await tester.tap(
        find.byKey(
          ValueKey(
            detail ? 'assignment-detail-course' : 'assignment-course-来源课程',
          ),
        ),
      );
    }
    expect(opened, ['课程键', '课程键']);
  });

  testWidgets('SPOC 原详情保留文件提交确认，取消不调用提交回调', (tester) async {
    const action = SpocSubmitAction(
      courseId: 'spoc',
      assignmentId: 'task',
      allowedExtensions: ['pdf'],
    );
    const file = SpocSubmitFile(path: 'synthetic.pdf', name: '合成作业.pdf');
    final submitted = <SpocSubmitInput>[];
    await show(
      tester,
      AssignmentContent(
        details: [
          FeatureDetail(
            title: '文件练习',
            presentation: assignment('task', detail: true).detail.presentation,
            actions: const [action],
          ),
        ],
        pickSpocSubmitFile: () async => file,
        onSpocSubmitWrite: (input) async => submitted.add(input),
      ),
    );
    for (final confirm in [false, true]) {
      final button = find.widgetWithText(FilledButton, '提交作业');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(submitted, isEmpty);
      expect(find.textContaining(file.name), findsOneWidget);
      await tester.tap(find.text(confirm ? '确认提交' : '取消'));
      await tester.pumpAndSettle();
    }
    expect(submitted.single.action, same(action));
    expect(submitted.single.file, same(file));
  });
}
