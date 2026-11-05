import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/agenda/calendar_values.dart';
import 'view_modes_test.dart' show at, course;

void main() {
  final cached = course();
  final entry = AgendaEntry(
    school: cached,
    timing: cached.timing,
    soon: false,
    completed: false,
    hidden: true,
  );
  AgendaContent event(AgendaTime start, AgendaTime end) => AgendaContent(
    kind: AgendaKind.event,
    title: '合成安排',
    allDay: false,
    start: start,
    end: end,
  );
  test('端点相接不冲突，隐藏的课程仍参与真实时段重叠提示', () {
    expect(
      agendaContentConflicts(event(at(5, 9), at(5, 10)), [entry]),
      isEmpty,
    );
    expect(
      agendaContentConflicts(event(at(5, 11), at(5, 12)), [entry]),
      isEmpty,
    );
    expect(agendaContentConflicts(event(at(5, 10, 59), at(5, 12)), [entry]), [
      entry,
    ]);
  });
  test('学校日期占位不作确定冲突，已知预约时段仍与课程比较', () {
    AgendaEntry school(AgendaFeature feature, AgendaTiming timing) =>
        AgendaEntry(
          school: SchoolAgendaItem(
            key: SchoolAgendaKey(
              source: feature.name,
              upstreamId: 'synthetic-time',
            ),
            timing: timing,
            title: '合成学校事项',
            subtitle: '',
            statusLabel: '已缓存',
            upstreamStatus: AgendaUpstreamStatus(
              feature: feature,
              completed: false,
            ),
            navigation: AgendaNavigation(feature: feature),
            homeTodo: false,
          ),
          timing: timing,
          soon: false,
          completed: false,
          hidden: false,
        );
    final placeholder = AgendaTiming(
      kind: AgendaTimingKind.allDay,
      from: '2026-11-05',
      to: '2026-11-06',
    );
    final unknownCourse = school(AgendaFeature.schedule, placeholder);
    expect(
      agendaContentConflicts(event(at(5, 18), at(5, 19)), [unknownCourse]),
      isEmpty,
    );
    final booking = school(
      AgendaFeature.cgyy,
      AgendaTiming(
        kind: AgendaTimingKind.period,
        start: at(5, 10),
        end: at(5, 11),
      ),
    );
    expect(agendaEntryConflicts(booking, [unknownCourse]), isEmpty);
    expect(agendaEntryConflicts(booking, [entry]), [entry]);
    final invalidCourse = school(
      AgendaFeature.schedule,
      AgendaTiming(
        kind: AgendaTimingKind.period,
        start: at(5, 11),
        end: at(5, 10),
      ),
    );
    expect(
      agendaContentConflicts(event(at(5, 9), at(5, 12)), [invalidCourse]),
      isEmpty,
    );
    expect(agendaEntryConflicts(booking, [invalidCourse]), isEmpty);
    expect(
      agendaEntryConflicts(school(AgendaFeature.cgyy, placeholder), [entry]),
      isEmpty,
    );
  });

  test('跨午夜事项覆盖两天，结束日期不包含在全天范围内', () {
    final overnight = AgendaEntry(
      timing: AgendaTiming(
        kind: AgendaTimingKind.period,
        start: at(5, 23),
        end: at(6, 1),
      ),
      soon: false,
      completed: false,
      hidden: false,
    );
    expect(agendaOnDay(overnight, DateTime(2026, 11, 5)), isTrue);
    expect(agendaOnDay(overnight, DateTime(2026, 11, 6)), isTrue);
    final allDay = AgendaEntry(
      timing: AgendaTiming(
        kind: AgendaTimingKind.allDay,
        from: '2026-11-05',
        to: '2026-11-07',
      ),
      soon: false,
      completed: false,
      hidden: false,
    );
    expect(agendaOnDay(allDay, DateTime(2026, 11, 6)), isTrue);
    expect(agendaOnDay(allDay, DateTime(2026, 11, 7)), isFalse);
  });
  test('月底导航落在目标月有效日期，并保留原始重复发生身份', () {
    expect(
      agendaShiftMonth(DateTime(2026, 1, 31), 1),
      DateTime.utc(2026, 2, 28),
    );
    expect(
      agendaShiftMonth(DateTime(2024, 1, 31), 1),
      DateTime.utc(2024, 2, 29),
    );
    final content = event(at(6, 10), at(6, 11));
    final moved = AgendaEntry(
      local: AgendaOccurrence(
        itemId: 'series',
        recurrenceId: at(5, 10).rfc3339,
        content: content,
        overridden: true,
      ),
      timing: AgendaTiming(
        kind: AgendaTimingKind.period,
        start: content.start,
        end: content.end,
      ),
      soon: false,
      completed: false,
      hidden: false,
    );
    expect(agendaEntryKey(moved), 'local:series:${at(5, 10).rfc3339}');
    expect(agendaOnDay(moved, DateTime(2026, 11, 6)), isTrue);
  });
}
