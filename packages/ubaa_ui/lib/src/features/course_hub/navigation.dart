import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../../write_callbacks.dart'
    show SigninCourseQrFetcher, SigninStatusChecker;
import '../coursework/signin_qr_sheet.dart' show SigninQrImageSaver;
import '../coursework/spoc_classroom_access.dart';
import '../coursework/spoc_files_access.dart';
import 'pages.dart';

enum CourseHubPage {
  course('课程主页'),
  assignments('全部作业'),
  sources('按来源浏览');

  const CourseHubPage(this.title);
  final String title;

  String pageTitle(CourseHubSnapshot? snapshot, String? courseKey) {
    if (this == course) {
      for (final item in snapshot?.courses ?? const <CourseHubCourse>[]) {
        if (item.key == courseKey) return item.name;
      }
    }
    return title;
  }

  Widget build(
    CourseHubSnapshot snapshot, {
    required String? courseKey,
    required String? term,
    required ValueChanged<FeatureReadNavigation> onOpenAssignment,
    required ValueChanged<FeatureId> onOpenFeature,
    Future<void> Function()? onRefresh,
    SetJudgeLink? onSetJudgeLink,
    SpocClassroomAccess? classroomAccess,
    SpocFilesAccess? filesAccess,
    SigninCourseQrFetcher? onFetchSigninQr,
    SigninQrImageSaver? onSaveSigninQr,
    SigninStatusChecker? onCheckSigninStatus,
  }) => switch (this) {
    course when term != snapshot.termCode => const Center(
      child: Text('课程所属学期已变化'),
    ),
    course => CourseHubCoursePage(
      courseKey: courseKey!,
      snapshot: snapshot,
      onOpenAssignment: onOpenAssignment,
      onOpenFeature: onOpenFeature,
      onRefresh: onRefresh,
      onSetJudgeLink: onSetJudgeLink,
      classroomAccess: classroomAccess,
      filesAccess: filesAccess,
      onFetchSigninQr: onFetchSigninQr,
      onSaveSigninQr: onSaveSigninQr,
      onCheckSigninStatus: onCheckSigninStatus,
    ),
    assignments => CourseHubAssignmentsPage(
      snapshot: snapshot,
      onOpenAssignment: onOpenAssignment,
      onRefresh: onRefresh,
    ),
    sources => CourseHubSourcesPage(
      snapshot: snapshot,
      onOpenFeature: onOpenFeature,
    ),
  };
}
