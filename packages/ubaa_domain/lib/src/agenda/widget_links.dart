import '../feature/catalog.dart';
import '../feature/query.dart';
import '../feature/presentation.dart';
import '../feature/read_navigation.dart';
import 'presentation.dart';
import 'school.dart';

String widgetLink(
  String owner,
  String target, {
  String? date,
  FeatureReadNavigation? navigation,
}) => Uri(
  scheme: 'ubaa',
  host: 'widget',
  path: '/open',
  queryParameters: {
    'owner': owner,
    'target': target,
    if (date != null) 'date': date,
    if (navigation != null) ...{
      'feature': navigation.feature.name,
      'view': navigation.query.view.name,
      if (navigation.query.courseId case final id?) 'courseId': id,
      if (navigation.query.assignmentId case final id?) 'assignmentId': id,
      if (navigation.query.term case final term?) 'term': term,
    },
  },
).toString();

final class WidgetLaunch {
  const WidgetLaunch(this.target, {this.date, this.navigation});
  final String target;
  final DateTime? date;
  final FeatureReadNavigation? navigation;
  Future<FeatureReadNavigation?> scheduleNavigation(
    Future<WeekPresentation?> Function(DateTime) weekOn,
  ) async {
    if (target != 'schedule' || date == null) return null;
    try {
      final week = await weekOn(date!);
      return week == null
          ? null
          : FeatureReadNavigation(
              feature: FeatureId.schedule,
              query: FeatureQuery(
                view: FeatureQueryView.scheduleWeek,
                term: week.responseTerm,
                week: week.number,
              ),
            );
    } on Object {
      return null;
    }
  }
}

WidgetLaunch? parseWidgetLaunch(String raw, {required String? owner}) {
  if (owner == null || owner.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      uri.scheme != 'ubaa' ||
      uri.host != 'widget' ||
      uri.path != '/open' ||
      uri.hasPort ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment)
    return null;
  try {
    final fields = uri.queryParametersAll;
    if (fields.entries.any(
      (field) =>
          field.value.length != 1 ||
          field.key.runes.length > 128 ||
          field.value.single.trim().isEmpty ||
          field.value.single.runes.length > 128,
    ))
      return null;
    final values = uri.queryParameters;
    if (values['owner'] != owner) return null;
    final target = values['target'];
    if (target == 'home' || target == 'agendaTodo')
      return values.length == 2 ? WidgetLaunch(target!) : null;
    if (target == 'agenda' || target == 'schedule') {
      final rawDate = values['date'];
      final date = rawDate == null || rawDate.length != 10
          ? null
          : DateTime.tryParse('${rawDate}T00:00:00Z');
      return values.length == 3 && date != null && agendaDate(date) == rawDate
          ? WidgetLaunch(target!, date: date)
          : null;
    }
    if (target != 'feature') return null;
    final feature = AgendaFeature.values.asNameMap()[values['feature']];
    if (!{
      AgendaFeature.bykc,
      AgendaFeature.spoc,
      AgendaFeature.judge,
      AgendaFeature.exam,
      AgendaFeature.cgyy,
      AgendaFeature.ygdk,
    }.contains(feature))
      return null;
    final course = values['courseId'], assignment = values['assignmentId'];
    final bykcId = int.tryParse(course ?? '');
    if (feature == AgendaFeature.bykc &&
            course != null &&
            (bykcId == null || bykcId <= 0) ||
        feature == AgendaFeature.spoc && assignment == null ||
        feature == AgendaFeature.judge &&
            (course == null || assignment == null))
      return null;
    final nav = agendaNavigation(
      AgendaNavigation(
        feature: feature!,
        bykcCourseId: bykcId,
        courseId: course,
        assignmentId: assignment,
        term: values['term'],
      ),
    );
    final allowed = {
      'target',
      'owner',
      'feature',
      'view',
      if (nav.query.courseId != null) 'courseId',
      if (nav.query.assignmentId != null) 'assignmentId',
      if (nav.query.term != null) 'term',
    };
    if (values.keys.any((key) => !allowed.contains(key)) ||
        values['view'] != null && values['view'] != nav.query.view.name)
      return null;
    return WidgetLaunch('feature', navigation: nav);
  } on FormatException {
    return null;
  }
}
