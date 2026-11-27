import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../write_callbacks.dart';
import '../coursework/spoc_classroom_access.dart';
import '../coursework/spoc_files_access.dart';

typedef SetJudgeLink =
    Future<void> Function(String courseKey, String judgeCourseId, bool linked);

class CourseHubCoursePage extends StatelessWidget {
  const CourseHubCoursePage({
    super.key,
    required this.courseKey,
    required this.snapshot,
    required this.onOpenAssignment,
    this.onRefresh,
    this.onSetJudgeLink,
    this.classroomAccess,
    this.filesAccess,
    this.onFetchSigninQr,
    this.onSaveSigninQr,
    this.onCheckSigninStatus,
    required this.onOpenFeature,
  });
  final String courseKey;
  final CourseHubSnapshot snapshot;
  final ValueChanged<FeatureReadNavigation> onOpenAssignment;
  final Future<void> Function()? onRefresh;
  final SetJudgeLink? onSetJudgeLink;
  final SpocClassroomAccess? classroomAccess;
  final SpocFilesAccess? filesAccess;
  final SigninCourseQrFetcher? onFetchSigninQr;
  final SigninQrImageSaver? onSaveSigninQr;
  final SigninStatusChecker? onCheckSigninStatus;
  final ValueChanged<FeatureId> onOpenFeature;
  @override
  Widget build(BuildContext context) {
    final course = snapshot.courses
        .where((item) => item.key == courseKey)
        .singleOrNull;
    return ListView(
      children: [
        ListTile(title: Text(course?.name ?? '课程暂不可用')),
        for (final task in course?.assignments ?? const <CourseHubAssignment>[])
          _assignment(task, onOpenAssignment),
      ],
    );
  }
}

Widget _assignment(
  CourseHubAssignment task,
  ValueChanged<FeatureReadNavigation> open,
) => ListTile(
  title: Text(task.detail.title),
  onTap: task.navigation == null ? null : () => open(task.navigation!),
);

class CourseHubAssignmentsPage extends StatelessWidget {
  const CourseHubAssignmentsPage({
    super.key,
    required this.snapshot,
    required this.onOpenAssignment,
    this.onRefresh,
  });
  final CourseHubSnapshot snapshot;
  final ValueChanged<FeatureReadNavigation> onOpenAssignment;
  final Future<void> Function()? onRefresh;
  @override
  Widget build(BuildContext context) => ListView.builder(
    itemCount: snapshot.allAssignments.length,
    itemBuilder: (_, index) =>
        _assignment(snapshot.allAssignments[index], onOpenAssignment),
  );
}

class CourseHubSourcesPage extends StatelessWidget {
  const CourseHubSourcesPage({
    super.key,
    required this.snapshot,
    required this.onOpenFeature,
  });
  final CourseHubSnapshot snapshot;
  final ValueChanged<FeatureId> onOpenFeature;
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      for (final feature in const [
        FeatureId.spoc,
        FeatureId.judge,
        FeatureId.signin,
      ])
        ListTile(
          title: Text(feature.title),
          onTap: () => onOpenFeature(feature),
        ),
    ],
  );
}
