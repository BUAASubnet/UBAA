part of '../presentation.dart';

final class EvaluationCoursePresentation extends FeaturePresentation {
  const EvaluationCoursePresentation({
    required this.courseId,
    required this.isEvaluated,
  });
  final String courseId;
  final bool isEvaluated;
}
