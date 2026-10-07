import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'card.dart' show AcademicCard;
import '../classroom/content.dart' show ClassroomContent;
import '../exam/timeline.dart' show ExamTimeline;
import '../grades/cards.dart' show GradeCard;
import '../schedule/content.dart' show ScheduleContent;

bool uiSupportsAcademicContent(
  FeatureId feature,
  List<FeatureDetail> details,
) => details.every(
  (detail) => switch (feature) {
    FeatureId.schedule =>
      detail.presentation is TodayCoursePresentation ||
          detail.presentation is TermPresentation ||
          detail.presentation is WeekPresentation ||
          detail.presentation is ScheduleCoursePresentation,
    FeatureId.exam => detail.presentation is ExamPresentation,
    FeatureId.grades => detail.presentation is GradePresentation,
    FeatureId.classroom => detail.presentation is ClassroomPresentation,
    _ => false,
  },
);

/// 学业内容直接消费 typed 展示模型；本地展开不会发起业务读取。
class AcademicResultContent extends StatelessWidget {
  const AcademicResultContent({
    required this.feature,
    required this.details,
    this.timeline,
    this.query,
    this.onQuery,
    this.onNavigate,
  });
  final FeatureId feature;
  final List<FeatureDetail> details;
  final ScheduleWeekOverview? timeline;
  final FeatureQuery? query;
  final Future<void> Function(FeatureQuery)? onQuery;
  final Future<void> Function(FeatureReadNavigation)? onNavigate;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (feature == FeatureId.classroom) {
        return ClassroomContent(
          details: details,
          query: query,
          onQuery: onQuery,
        );
      }
      final weekly =
          feature == FeatureId.schedule &&
          details.every(
            (detail) => detail.presentation is ScheduleCoursePresentation,
          );
      if (weekly) return ScheduleContent(details: details, timeline: timeline);
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (feature == FeatureId.exam)
            ExamTimeline(details: details)
          else if (feature == FeatureId.grades)
            for (final detail in details)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GradeCard(detail: detail),
              )
          else
            for (final detail in details)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AcademicCard(detail: detail, onNavigate: onNavigate),
              ),
        ],
      );
    },
  );
}
