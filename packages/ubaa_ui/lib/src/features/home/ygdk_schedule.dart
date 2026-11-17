import 'package:ubaa_domain/ubaa_domain.dart';
import '../agenda/format.dart';
import 'shell_helpers.dart' show agendaRoute;

/// 只查询当前账号、路线和学期的本地课表，不触发学校读取。
final class YgdkScheduleCheck {
  Object? _scope;
  int _revision = 0;
  bool hasPe = false;

  Future<void> update({
    required Object? owner,
    required Object epoch,
    required RoutePolicy policy,
    required List<ConnectionMode> active,
    required ConnectionMode? schoolRoute,
    required AgendaService? service,
    required String term,
    required DateTime now,
    required void Function() changed,
  }) async {
    final route = agendaRoute(policy, active, schoolRoute: schoolRoute);
    final scope = (owner, epoch, service, route, term);
    if (_scope == scope) return;
    _scope = scope;
    final revision = ++_revision;
    hasPe = false;
    if (service == null || term.isEmpty) return;
    try {
      final campus = campusDate(now);
      final result = await service.query(
        AgendaQuery(
          route: route,
          term: term,
          from: '${campus.year - 1}-01-01',
          to: '${campus.year + 2}-01-01',
          now: agendaTime(campus),
          includeHidden: true,
          ygdkEnabled: false,
          ygdkWeekDone: false,
          ygdkTermDone: false,
        ),
      );
      if (_revision != revision) return;
      hasPe = result.entries.any((entry) {
        final school = entry.school;
        return school?.navigation.feature == AgendaFeature.schedule &&
            school?.navigation.term == term &&
            school!.title.contains('体育');
      });
    } on Object {
      if (_revision != revision) return;
    }
    changed();
  }

  void dispose() => _revision++;
}
