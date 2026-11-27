import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/course_hub/course_classroom_tab.dart';
import 'package:ubaa_ui/src/features/course_hub/course_files_tab.dart';
import 'package:ubaa_ui/src/features/coursework/spoc_files_access.dart';
import 'package:ubaa_ui/src/features/spoc_classroom/classroom_view.dart';
import 'fixture.dart';

const unavailable = UiError(
  code: UbaaErrorCode.businessUnavailable,
  title: '未开通',
  message: '未开通课堂',
);
const unused = SpocCourse(courseId: 'empty', name: '合成课程', teacher: '教师甲');

class _Files implements SpocFilesService {
  final calls = <String>[];
  @override
  Future<SpocRead<List<SpocCourseFile>>> courseFiles(
    String courseId, {
    String? folderId,
  }) async {
    calls.add(courseId);
    return (
      route: ConnectionMode.direct,
      data: [
        if (courseId != unused.courseId)
          const SpocCourseFile(
            id: 'file',
            name: '讲义',
            isFolder: false,
            downloadAllowed: false,
          ),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('承接 classroom_entry_test：多个课堂略过未开通项，唯一可用项直接显示', (tester) async {
    final fixture = await ClassroomFixture.load();
    fixture.readCatalog = (id) async =>
        id == unused.courseId ? throw unavailable : fixture.demoCatalog;
    await pumpClassroom(
      tester,
      Scaffold(
        body: CourseClassroomTab(
          access: fixture.access(),
          courses: [unused, fixture.course],
          courseName: '合成课程',
        ),
      ),
    );
    expect(fixture.catalogCalls, [unused.courseId, fixture.kcid]);
    expect(find.byType(ClassroomSessionList), findsOneWidget);
    expect(find.byType(SegmentedButton<int>), findsNothing);
    expect(find.text(unavailable.message), findsNothing);
  });
  testWidgets('承接 classroom_entry_test：全部失败时显示可重试的错误，重试后恢复', (tester) async {
    final fixture = await ClassroomFixture.load();
    fixture.readCatalog = (id) async =>
        throw (id == unused.courseId ? unavailable : catalogFailure);
    await pumpClassroom(
      tester,
      Scaffold(
        body: CourseClassroomTab(
          access: fixture.access(),
          courses: [unused, fixture.course],
          courseName: '合成课程',
        ),
      ),
    );
    expect(find.text(catalogFailure.message), findsOneWidget);
    fixture.readCatalog = (id) async => fixture.demoCatalog;
    await tapAndSettle(tester, find.text('重试'));
    expect(find.byType(SegmentedButton<int>), findsOneWidget);
    await tapAndSettle(tester, find.text(fixture.course.teacher!));
    expect(fixture.catalogCalls, [
      unused.courseId,
      fixture.kcid,
      unused.courseId,
      fixture.kcid,
    ]);
    expect(find.byType(ClassroomSessionList), findsOneWidget);
  });
  testWidgets('课件略过空根目录，嵌入页复用 initialItems', (tester) async {
    final files = _Files();
    await pumpClassroom(
      tester,
      Scaffold(
        body: CourseFilesTab(
          access: SpocFilesAccess(service: files),
          courses: const [
            unused,
            SpocCourse(courseId: 'lab', name: '实验'),
          ],
          courseName: '合成课程',
        ),
      ),
    );
    expect(find.text('讲义'), findsOneWidget);
    expect(find.byType(SegmentedButton<int>), findsNothing);
    expect(files.calls, ['empty', 'lab']);
  });
}
