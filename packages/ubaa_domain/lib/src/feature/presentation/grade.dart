part of '../presentation.dart';

final class GradePresentation extends FeaturePresentation {
  const GradePresentation({
    this.courseName,
    this.courseCode,
    this.score,
    this.gradePoint,
    this.credit,
    this.courseType,
    this.scoreType,
    this.termCode,
  });

  final String? courseName;
  final String? courseCode;
  final String? score;
  final String? gradePoint;
  final double? credit;
  final String? courseType;
  final String? scoreType;
  final String? termCode;
}
