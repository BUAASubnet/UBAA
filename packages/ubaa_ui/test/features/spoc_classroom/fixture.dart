import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/demo_classroom.dart';
import 'package:ubaa_ui/src/features/coursework/spoc_classroom_access.dart';
import 'package:ubaa_ui/src/features/spoc_classroom/classroom_view.dart';

final class ClassroomFixture implements ClassroomService {
  ClassroomFixture._(this.course, this.demoCatalog);

  static const demo = DemoClassroomService();
  final SpocCourse course;
  final ClassroomRead<ClassroomCatalog> demoCatalog;
  final catalogCalls = <String>[];
  final sessionCalls = <(String, String)>[];
  final externalUrls = <Uri>[];
  Future<ClassroomRead<ClassroomCatalog>> Function(String)? readCatalog;

  static Future<ClassroomFixture> load() async {
    final course = (await demo.courses()).data.single;
    return ClassroomFixture._(course, await demo.catalog(course.courseId));
  }

  ClassroomCatalog get data => demoCatalog.data;
  String get kcid => course.courseId;
  ClassroomSessionSummary period(ClassroomStatus status) =>
      data.sessions.singleWhere((session) => session.status == status);

  SpocClassroomAccess access({
    Future<SpocRead<List<SpocCourse>>> Function()? courses,
    VideoPlaybackCapability? playback,
  }) => SpocClassroomAccess(
    service: this,
    courses: courses ?? demo.courses,
    playback: playback,
    openExternal: (url) async => externalUrls.add(url),
  );

  ClassroomView view({VideoPlaybackCapability? playback}) => ClassroomView(
    access: access(playback: playback),
    kcid: kcid,
    courseName: course.name,
  );

  ClassroomRead<ClassroomCatalog> withPeriods(
    List<ClassroomSessionSummary> periods,
  ) => (
    route: demoCatalog.route,
    data: ClassroomCatalog(
      courseId: data.courseId,
      title: data.title,
      teachers: data.teachers,
      termName: data.termName,
      sessions: periods,
    ),
  );

  @override
  Future<ClassroomRead<ClassroomCatalog>> catalog(String kcid) {
    catalogCalls.add(kcid);
    return (readCatalog ?? demo.catalog)(kcid);
  }

  @override
  Future<ClassroomRead<ClassroomSession>> session(
    String courseId,
    String subId,
  ) {
    sessionCalls.add((courseId, subId));
    return demo.session(courseId, subId);
  }

  @override
  Future<ClassroomRead<ClassroomTranscript>> transcript(
    String subId,
    String resourceGuid,
  ) => demo.transcript(subId, resourceGuid);

  @override
  Future<ClassroomRead<ClassroomSummary>> summary(
    String subId,
    String resourceGuid,
  ) => demo.summary(subId, resourceGuid);

  @override
  Future<ClassroomRead<ClassroomSlides>> slides(
    String courseId,
    String subId,
    String resourceGuid,
  ) => demo.slides(courseId, subId, resourceGuid);
}

const catalogFailure = UiError(
  code: UbaaErrorCode.upstreamUnavailable,
  title: '读取失败',
  message: '演示课堂暂时无法读取',
);

void setViewport(
  WidgetTester tester, {
  double width = 420,
  double height = 840,
}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> pumpClassroom(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(MaterialApp(home: home));
  await tester.pumpAndSettle();
}

Future<void> tapAndSettle(WidgetTester tester, Finder target) async {
  await tester.tap(target);
  await tester.pumpAndSettle();
}
