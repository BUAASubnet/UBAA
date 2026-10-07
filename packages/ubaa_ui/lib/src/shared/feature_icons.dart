import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

IconData uiFeatureIcon(FeatureId feature) => switch (feature) {
  FeatureId.schedule => Icons.calendar_today,
  FeatureId.exam => Icons.assignment_outlined,
  FeatureId.grades => Icons.grade,
  FeatureId.bykc => Icons.school,
  FeatureId.classroom => Icons.meeting_room,
  FeatureId.spoc => Icons.assignment_turned_in,
  FeatureId.judge => Icons.code,
  FeatureId.libbook => Icons.event_seat,
  FeatureId.signin => Icons.how_to_reg,
  FeatureId.cgyy => Icons.date_range,
  FeatureId.ygdk => Icons.wb_sunny,
  FeatureId.evaluation => Icons.assignment_turned_in,
};
