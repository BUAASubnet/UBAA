part of '../presentation.dart';

final class SigninPresentation extends FeaturePresentation {
  const SigninPresentation({
    required this.courseId,
    required this.classBeginTime,
    required this.classEndTime,
    this.signStatus,
  });
  final String courseId;
  final String classBeginTime;
  final String classEndTime;
  final int? signStatus;
}
