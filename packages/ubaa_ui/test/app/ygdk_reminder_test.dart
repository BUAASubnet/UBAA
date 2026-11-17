import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_ui/src/features/home/ygdk_schedule.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/home/shell_helpers.dart';

void main() {
  test('本学期体育课来自整学期本地课表，隐藏课程也参与判断', () async {
    final backend = _Agenda();
    final service = AgendaService(backend);
    await service.openAccount('synthetic');
    final check = YgdkScheduleCheck();
    var epoch = 0;
    Future<void> update() => check.update(
      owner: 'synthetic',
      epoch: epoch++,
      service: service,
      policy: RoutePolicy.auto,
      active: const [],
      schoolRoute: ConnectionMode.webvpn,
      term: 'current',
      now: DateTime.utc(2026, 11),
      changed: () {},
    );
    for (final (courses, expected)
        in <(List<(String, String, AgendaFeature)>, bool)>[
          ([('体育（3）', 'current', AgendaFeature.schedule)], true),
          ([('高等数学', 'current', AgendaFeature.schedule)], false),
          ([('体育', 'past', AgendaFeature.schedule)], false),
          ([('体育讲座', 'current', AgendaFeature.bykc)], false),
          ([], false),
        ]) {
      backend.read = (query) async {
        expect(query.term, 'current');
        expect(query.route, ConnectionMode.webvpn);
        expect(query.includeHidden, true);
        expect(DateTime.parse(query.from).isBefore(DateTime.utc(2026)), true);
        return _courses(courses);
      };
      await update();
      expect(check.hasPe, expected);
    }
    backend.read = (_) async =>
        throw const AgendaException(AgendaFailure.unavailable);
    await update();
    expect(check.hasPe, false);
  });
  test('切换账号撤销迟到课表结果', () async {
    final backend = _Agenda();
    final service = AgendaService(backend);
    await service.openAccount('a');
    final pending = Completer<AgendaQueryResult>();
    backend.read = (_) => pending.future;
    final check = YgdkScheduleCheck();
    Future<void> update(String owner, AgendaService? source) => check.update(
      owner: owner,
      epoch: 0,
      service: source,
      policy: RoutePolicy.direct,
      active: const [],
      schoolRoute: null,
      term: 'current',
      now: DateTime.utc(2026, 11),
      changed: () {},
    );
    final first = update('a', service);
    await Future<void>.delayed(Duration.zero);
    await update('b', null);
    pending.complete(_courses([('体育', 'current', AgendaFeature.schedule)]));
    await first;
    expect(check.hasPe, false);
  });

  test('体育课决定默认提醒，手动选择始终优先', () {
    for (final hasPe in [true, false]) {
      for (final manual in [null, true, false]) {
        final settings = YgdkReminderSettings(manualEnabled: manual);
        final result = effectiveYgdkReminder(settings, hasPe);
        expect(result.enabled, manual ?? hasPe);
      }
    }
  });
}

final class _Agenda implements AgendaBackend {
  Future<AgendaQueryResult> Function(AgendaQuery)? read;
  @override
  Future<void> deactivate() async {}
  @override
  Future<void> openAccount(String accountId) async {}
  @override
  Future<AgendaQueryResult> query(AgendaQuery query) => read!(query);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AgendaQueryResult _courses(List<(String, String, AgendaFeature)> courses) =>
    AgendaQueryResult(
      entries: [
        for (final (title, term, feature) in courses)
          AgendaEntry(
            timing: AgendaTiming(kind: AgendaTimingKind.undated),
            soon: false,
            completed: false,
            hidden: true,
            school: SchoolAgendaItem(
              key: SchoolAgendaKey(source: 'schedule', upstreamId: title),
              timing: AgendaTiming(kind: AgendaTimingKind.undated),
              title: title,
              subtitle: '',
              statusLabel: '',
              homeTodo: false,
              upstreamStatus: AgendaUpstreamStatus(
                feature: feature,
                completed: false,
              ),
              navigation: AgendaNavigation(feature: feature, term: term),
            ),
          ),
      ],
      sources: [],
    );
