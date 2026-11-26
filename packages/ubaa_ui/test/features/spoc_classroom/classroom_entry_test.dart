import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/spoc_classroom/classroom_entry.dart';
import 'package:ubaa_ui/src/features/spoc_classroom/classroom_view.dart';

import 'fixture.dart';

Future<void> _openEntry(
  WidgetTester tester,
  ClassroomFixture fixture, {
  Future<SpocRead<List<SpocCourse>>> Function()? courses,
  String? fallback,
}) async {
  setViewport(tester);
  await pumpClassroom(
    tester,
    Scaffold(
      body: ClassroomEntryButton(
        access: fixture.access(courses: courses),
        courseName: fixture.course.name,
        fallbackCourseId: fallback,
      ),
    ),
  );
  await tapAndSettle(tester, find.widgetWithText(TextButton, '课堂'));
}

void main() {
  testWidgets('只有一个同名课程时直接读取对应目录', (tester) async {
    final fixture = await ClassroomFixture.load();
    await _openEntry(
      tester,
      fixture,
      fallback: 'unused-fallback',
      courses: () async => (
        data: [
          const SpocCourse(courseId: 'unrelated', name: '其他课程'),
          fixture.course,
        ],
        route: ConnectionMode.direct,
      ),
    );

    expect(find.text('选择课堂'), findsNothing);
    expect(find.byType(ClassroomView), findsOneWidget);
    expect(fixture.catalogCalls, [fixture.kcid]);
  });

  testWidgets('多个同名课程先选择，再把选中的 kcid 传给目录', (tester) async {
    final fixture = await ClassroomFixture.load();
    fixture.readCatalog = (_) async => fixture.demoCatalog;
    final second = SpocCourse(
      courseId: 'fixture-lab',
      name: fixture.course.name,
      teacher: '实验教师',
    );
    await _openEntry(
      tester,
      fixture,
      courses: () async =>
          (data: [fixture.course, second], route: ConnectionMode.direct),
    );

    expect(find.text('选择课堂'), findsOneWidget);
    expect(find.text(fixture.course.teacher!), findsOneWidget);
    expect(fixture.catalogCalls, isEmpty);
    await tapAndSettle(tester, find.text(second.teacher!));
    expect(find.text('选择课堂'), findsNothing);
    expect(find.byType(ClassroomView), findsOneWidget);
    expect(fixture.catalogCalls, [second.courseId]);
  });

  testWidgets('课程列表读取失败后用作业提供的 kcid', (tester) async {
    final fixture = await ClassroomFixture.load();
    await _openEntry(
      tester,
      fixture,
      courses: () async => throw catalogFailure,
      fallback: fixture.kcid,
    );

    expect(find.byType(ClassroomView), findsOneWidget);
    expect(find.text(catalogFailure.message), findsNothing);
    expect(fixture.catalogCalls, [fixture.kcid]);
  });

  testWidgets('课程列表读取失败且无兜底时显示错误，不读目录', (tester) async {
    final fixture = await ClassroomFixture.load();
    await _openEntry(
      tester,
      fixture,
      courses: () async => throw catalogFailure,
    );

    expect(find.text(catalogFailure.message), findsOneWidget);
    expect(find.byType(ClassroomView), findsNothing);
    expect(fixture.catalogCalls, isEmpty);
  });
}
