import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/common/state_panel.dart';
import 'package:ubaa_ui/src/features/course_hub/course_classroom_tab.dart';
import 'package:ubaa_ui/src/features/course_hub/course_files_tab.dart';
import 'package:ubaa_ui/src/features/coursework/spoc_files_access.dart';
import 'package:ubaa_ui/src/features/spoc_classroom/classroom_view.dart';
import 'fixture.dart';

const _unavailable = UiError(
  code: UbaaErrorCode.businessUnavailable,
  title: '未开通',
  message: '未开通课堂',
);
const _filesFailure = UiError(
  code: UbaaErrorCode.upstreamUnavailable,
  title: '读取失败',
  message: '演示课件暂时无法读取',
);
const _lecture = SpocCourse(courseId: 'lecture', name: '理论', teacher: '教师甲');
const _lab = SpocCourse(courseId: 'lab', name: '实验', teacher: '教师乙');

class _Files implements SpocFilesService {
  final calls = <String>[];
  final errors = <String, UiError>{};
  final emptyRoots = <String>{};

  @override
  Future<SpocRead<List<SpocCourseFile>>> courseFiles(
    String courseId, {
    String? folderId,
  }) async {
    calls.add(courseId);
    if (errors[courseId] case final error?) throw error;
    return (
      route: ConnectionMode.direct,
      data: [
        if (!emptyRoots.contains(courseId))
          SpocCourseFile(
            id: courseId,
            name: '讲义 $courseId',
            isFolder: false,
            downloadAllowed: false,
          ),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _classroomTab(
  WidgetTester tester,
  ClassroomFixture fixture, {
  List<SpocCourse> courses = const [_lecture, _lab],
}) => pumpClassroom(
  tester,
  Scaffold(
    body: CourseClassroomTab(
      access: fixture.access(),
      courses: courses,
      courseName: '合成课程',
    ),
  ),
);

Future<void> _filesTab(
  WidgetTester tester,
  _Files files, {
  List<SpocCourse> courses = const [_lecture, _lab],
}) => pumpClassroom(
  tester,
  Scaffold(
    body: CourseFilesTab(
      access: SpocFilesAccess(service: files),
      courses: courses,
      courseName: '合成课程',
    ),
  ),
);

List<SpocCourse> _coursesWithTeachers(bool sameTeacher) => [
  _lecture,
  SpocCourse(
    courseId: _lab.courseId,
    name: _lab.name,
    teacher: sameTeacher ? _lecture.teacher : _lab.teacher,
  ),
];

void main() {
  final segments = find.byType(SegmentedButton<int>);
  final inlineRetry = find.byType(UiInlineRetry);
  final statePanel = find.byType(UiStatePanel);
  final sessionList = find.byType(ClassroomSessionList);

  testWidgets('课堂略过未开通项，唯一可用项不分段且不提示失败', (tester) async {
    final fixture = await ClassroomFixture.load();
    fixture.readCatalog = (id) async =>
        id == _lab.courseId ? throw _unavailable : fixture.demoCatalog;
    await _classroomTab(tester, fixture);
    expect(fixture.catalogCalls, ['lecture', 'lab']);
    expect(
      tester.widget<ClassroomSessionList>(sessionList).catalog,
      same(fixture.data),
    );
    expect(segments, findsNothing);
    expect(inlineRetry, findsNothing);
    expect(find.text(_unavailable.message), findsNothing);
  });

  testWidgets('课堂部分失败只在顶部提示一行，重试重新读取两个课程', (tester) async {
    final fixture = await ClassroomFixture.load();
    var labError = catalogFailure;
    fixture.readCatalog = (id) async =>
        id == _lab.courseId ? throw labError : fixture.demoCatalog;
    await _classroomTab(tester, fixture);
    final banner = find.widgetWithText(UiInlineRetry, '另有 1 个课堂未能读取');
    expect(banner, findsOneWidget);
    expect(
      tester.getBottomLeft(banner).dy,
      lessThanOrEqualTo(tester.getTopLeft(sessionList).dy),
    );
    expect(segments, findsNothing);
    expect(statePanel, findsNothing);
    labError = _unavailable;
    await tapAndSettle(
      tester,
      find.descendant(of: banner, matching: find.text('重试')),
    );
    expect(fixture.catalogCalls, ['lecture', 'lab', 'lecture', 'lab']);
    expect(inlineRetry, findsNothing);
    expect(sessionList, findsOneWidget);
  });

  testWidgets('两个 kcid 命中同一个智学北航课堂时只显示一次', (tester) async {
    final fixture = await ClassroomFixture.load();
    fixture.readCatalog = (id) async =>
        id == _lab.courseId ? fixture.withPeriods([]) : fixture.demoCatalog;
    await _classroomTab(tester, fixture);
    expect(fixture.catalogCalls, ['lecture', 'lab']);
    expect(
      tester.widget<ClassroomSessionList>(sessionList).catalog,
      same(fixture.data),
    );
    expect(segments, findsNothing);
  });

  for (final sameTeacher in [true, false]) {
    final label = sameTeacher ? '教师相同用编号' : '教师不同用教师名';
    testWidgets('两个不同课堂：$label', (tester) async {
      final fixture = await ClassroomFixture.load();
      const labCatalog = ClassroomCatalog(
        courseId: 'classroom-lab',
        title: '合成实验课堂',
        teachers: [],
        termName: '合成学期',
        sessions: [],
      );
      fixture.readCatalog = (id) async => id == _lab.courseId
          ? (route: fixture.demoCatalog.route, data: labCatalog)
          : fixture.demoCatalog;
      await _classroomTab(
        tester,
        fixture,
        courses: _coursesWithTeachers(sameTeacher),
      );
      final first = sameTeacher ? '课堂 1' : '教师甲';
      final second = sameTeacher ? '课堂 2' : '教师乙';
      expect(
        find.descendant(of: segments, matching: find.text(first)),
        findsOneWidget,
      );
      await tapAndSettle(
        tester,
        find.descendant(of: segments, matching: find.text(second)),
      );
      expect(
        tester.widget<ClassroomSessionList>(sessionList).catalog,
        same(labCatalog),
      );
      expect(fixture.catalogCalls, ['lecture', 'lab']);
    });

    testWidgets('两个有文件的课件来源：$label', (tester) async {
      final files = _Files();
      await _filesTab(
        tester,
        files,
        courses: _coursesWithTeachers(sameTeacher),
      );
      final first = sameTeacher ? '课件 1' : '教师甲';
      final second = sameTeacher ? '课件 2' : '教师乙';
      expect(
        find.descendant(of: segments, matching: find.text(first)),
        findsOneWidget,
      );
      expect(find.text('讲义 lecture'), findsOneWidget);
      await tapAndSettle(
        tester,
        find.descendant(of: segments, matching: find.text(second)),
      );
      expect(find.text('讲义 lab'), findsOneWidget);
      expect(find.text('讲义 lecture'), findsNothing);
      expect(files.calls, ['lecture', 'lab']);
    });
  }

  for (final allUnavailable in [false, true]) {
    final label = allUnavailable ? '全部业务不可用' : '全部失败';
    testWidgets('课堂${label}时显示整页提示且可重试', (tester) async {
      final fixture = await ClassroomFixture.load();
      final error = allUnavailable ? _unavailable : catalogFailure;
      fixture.readCatalog = (_) async => throw error;
      await _classroomTab(tester, fixture);
      expect(
        find.widgetWithText(UiStatePanel, allUnavailable ? '暂无课堂' : '课堂读取失败'),
        findsOneWidget,
      );
      expect(find.text(error.message), findsOneWidget);
      expect(inlineRetry, findsNothing);
      expect(sessionList, findsNothing);
      fixture.readCatalog = (_) async => fixture.demoCatalog;
      await tapAndSettle(
        tester,
        find.descendant(of: statePanel, matching: find.text('重试')),
      );
      expect(sessionList, findsOneWidget);
      expect(fixture.catalogCalls, ['lecture', 'lab', 'lecture', 'lab']);
    });

    testWidgets('课件${label}时显示整页提示', (tester) async {
      final files = _Files();
      final error = allUnavailable ? _unavailable : _filesFailure;
      files.errors.addAll({'lecture': error, 'lab': error});
      await _filesTab(tester, files);
      expect(
        find.widgetWithText(
          UiStatePanel,
          allUnavailable ? '这里还没有文件' : '课件读取失败',
        ),
        findsOneWidget,
      );
      expect(
        find.text(error.message),
        allUnavailable ? findsNothing : findsOneWidget,
      );
      expect(find.text('重试'), allUnavailable ? findsNothing : findsOneWidget);
      expect(inlineRetry, findsNothing);
    });
  }

  testWidgets('课堂没有成功项时优先显示实际读取失败', (tester) async {
    final fixture = await ClassroomFixture.load();
    fixture.readCatalog = (id) async =>
        throw (id == _lecture.courseId ? _unavailable : catalogFailure);
    await _classroomTab(tester, fixture);
    expect(find.widgetWithText(UiStatePanel, '课堂读取失败'), findsOneWidget);
    expect(find.text(catalogFailure.message), findsOneWidget);
    expect(inlineRetry, findsNothing);
  });

  testWidgets('课件略过空根目录，嵌入页复用 initialItems', (tester) async {
    final files = _Files()..emptyRoots.add('lecture');
    await _filesTab(tester, files);
    expect(find.text('讲义 lab'), findsOneWidget);
    expect(segments, findsNothing);
    expect(files.calls, ['lecture', 'lab']);
  });

  testWidgets('课件略过业务不可用的来源，不分段且不提示失败', (tester) async {
    final files = _Files()..errors['lab'] = _unavailable;
    await _filesTab(tester, files);
    expect(find.text('讲义 lecture'), findsOneWidget);
    expect(segments, findsNothing);
    expect(inlineRetry, findsNothing);
    expect(find.text(_unavailable.message), findsNothing);
    expect(files.calls, ['lecture', 'lab']);
  });

  testWidgets('课件部分失败只在顶部提示一行，重试重新读取两个课程', (tester) async {
    final files = _Files()..errors['lab'] = _filesFailure;
    await _filesTab(tester, files);
    final banner = find.widgetWithText(UiInlineRetry, '另有 1 个课程的课件未能读取');
    final file = find.text('讲义 lecture');
    expect(banner, findsOneWidget);
    expect(
      tester.getBottomLeft(banner).dy,
      lessThanOrEqualTo(tester.getTopLeft(file).dy),
    );
    expect(segments, findsNothing);
    expect(statePanel, findsNothing);
    files.errors['lab'] = _unavailable;
    await tapAndSettle(
      tester,
      find.descendant(of: banner, matching: find.text('重试')),
    );
    expect(files.calls, ['lecture', 'lab', 'lecture', 'lab']);
    expect(file, findsOneWidget);
    expect(inlineRetry, findsNothing);
  });
}
