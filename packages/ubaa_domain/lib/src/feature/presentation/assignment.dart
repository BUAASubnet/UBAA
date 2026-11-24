part of '../presentation.dart';

enum AssignmentSubmissionStatus { submitted, partial, unsubmitted, unknown }

final class SpocAssignmentPresentation extends FeaturePresentation {
  const SpocAssignmentPresentation({
    required this.courseId,
    required this.courseName,
    required this.assignmentId,
    this.teacherName,
    this.startTime,
    this.dueTime,
    this.score,
    required this.status,
    required this.statusText,
    this.contentPlainText,
    this.submittedAt,
    this.attachment,
    this.submittedFile,
    this.submitModes = const [],
    this.allowedExtensions = const [],
    this.maxSubmissions,
    this.submissionCount,
    this.isGroupAssignment = false,
    this.lateSubmissionDeadline,
    this.submitUnavailableReason,
    this.isDetail = false,
  });
  final String courseId;
  final String courseName;
  final String assignmentId;
  final String? teacherName;
  final String? startTime;
  final String? dueTime;
  final String? score;
  final AssignmentSubmissionStatus status;
  final String statusText;
  final String? contentPlainText;
  final String? submittedAt;
  final SpocAttachment? attachment;
  final SpocSubmittedFile? submittedFile;
  final List<String> submitModes, allowedExtensions;
  final int? maxSubmissions, submissionCount;
  final bool isGroupAssignment;
  final String? lateSubmissionDeadline;
  final String? submitUnavailableReason;
  final bool isDetail;
}

final class JudgeProblemPresentation extends FeaturePresentation {
  const JudgeProblemPresentation({
    required this.name,
    required this.status,
    required this.statusText,
    this.score,
    this.maxScore,
  });
  final String name;
  final AssignmentSubmissionStatus status;
  final String statusText;
  final String? score;
  final String? maxScore;
}

final class JudgeAssignmentPresentation extends FeaturePresentation {
  JudgeAssignmentPresentation({
    required this.courseId,
    required this.courseName,
    required this.assignmentId,
    this.startTime,
    this.dueTime,
    this.maxScore,
    this.myScore,
    required this.totalProblems,
    required this.submittedCount,
    required this.status,
    required this.statusText,
    this.contentPlainText,
    this.isDetail = false,
    List<JudgeProblemPresentation> problems = const [],
  }) : problems = List<JudgeProblemPresentation>.unmodifiable(problems);
  final String courseId;
  final String courseName;
  final String assignmentId;
  final String? startTime;
  final String? dueTime;
  final String? maxScore;
  final String? myScore;
  final int totalProblems;
  final int submittedCount;
  final AssignmentSubmissionStatus status;
  final String statusText;
  final String? contentPlainText;
  final bool isDetail;
  final List<JudgeProblemPresentation> problems;
}
