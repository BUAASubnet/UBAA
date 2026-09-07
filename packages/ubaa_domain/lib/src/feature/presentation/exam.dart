part of '../presentation.dart';

final class ExamPresentation extends FeaturePresentation {
  const ExamPresentation({
    required this.arranged,
    this.courseNo,
    this.date,
    this.description,
    this.startTime,
    this.endTime,
    this.place,
    this.seat,
    this.week,
    this.status,
    this.type,
    this.taskId,
  });

  final bool arranged;
  final String? courseNo;
  final String? date;
  final String? description;
  final String? startTime;
  final String? endTime;
  final String? place;
  final String? seat;
  final int? week;
  final int? status;
  final String? type;
  final String? taskId;
}
