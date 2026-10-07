part of 'projection.dart';

ScheduleWeekOverview bridgeScheduleOverview(
  BridgeWeeklySchedule value,
  List<FeatureDetail> details,
) => ScheduleWeekOverview(
  code: value.code,
  sectionTimes: scheduleSectionTimes(
    code: value.code,
    courses: details
        .map((d) => d.presentation)
        .whereType<ScheduleCoursePresentation>(),
    explicit: [
      for (final time in value.sectionTimes)
        ScheduleSectionTime(time.section, time.start, time.end),
    ],
  ),
);
