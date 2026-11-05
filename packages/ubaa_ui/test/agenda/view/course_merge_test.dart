import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/agenda/calendar_values.dart';
import 'view_modes_test.dart' show at;

AgendaEntry _school(
  AgendaFeature feature,
  String id,
  String title,
  AgendaTime start,
  AgendaTime end, {
  String? location,
}) {
  final timing = AgendaTiming(
    kind: AgendaTimingKind.period,
    start: start,
    end: end,
  );
  return AgendaEntry(
    school: SchoolAgendaItem(
      key: SchoolAgendaKey(source: feature.name, upstreamId: id),
      timing: timing,
      title: title,
      subtitle: '',
      location: location,
      statusLabel: '已缓存',
      upstreamStatus: AgendaUpstreamStatus(feature: feature, completed: false),
      navigation: AgendaNavigation(feature: feature),
      homeTodo: false,
    ),
    timing: timing,
    soon: false,
    completed: false,
    hidden: false,
  );
}

void main() {
  test('同名同地点的连续小节合并为一段，跨过中间的签到条目', () {
    final first = _school(
      AgendaFeature.schedule,
      'a',
      '合成课程',
      at(5, 19),
      at(5, 19, 45),
      location: 'F1',
    );
    final signin = _school(
      AgendaFeature.signin,
      's',
      '合成课程',
      at(5, 19),
      at(5, 20, 35),
    );
    final second = _school(
      AgendaFeature.schedule,
      'b',
      '合成课程',
      at(5, 19, 50),
      at(5, 20, 35),
      location: 'F1',
    );
    final merged = agendaMergeCourses([signin, first, second]);
    expect(merged.map((e) => e.$1).toList(), [signin, first]);
    expect(merged.last.$2, agendaEnd(second));
  });

  test('间隔过长、地点不同或不同课程时保持分开', () {
    final first = _school(
      AgendaFeature.schedule,
      'a',
      '合成课程',
      at(5, 8),
      at(5, 8, 45),
      location: 'F1',
    );
    final late = _school(
      AgendaFeature.schedule,
      'b',
      '合成课程',
      at(5, 10),
      at(5, 10, 45),
      location: 'F1',
    );
    final moved = _school(
      AgendaFeature.schedule,
      'c',
      '合成课程',
      at(5, 8, 50),
      at(5, 9, 35),
      location: 'F2',
    );
    final other = _school(
      AgendaFeature.schedule,
      'd',
      '另一课程',
      at(5, 8, 50),
      at(5, 9, 35),
      location: 'F1',
    );
    expect(agendaMergeCourses([first, moved, other, late]).length, 4);
  });

  test('同名且时段重叠的签到归入课程，其余签到保留', () {
    final first = _school(
      AgendaFeature.schedule,
      'a',
      '合成课程',
      at(5, 19),
      at(5, 19, 45),
      location: 'F1',
    );
    final second = _school(
      AgendaFeature.schedule,
      'b',
      '合成课程',
      at(5, 19, 50),
      at(5, 20, 35),
      location: 'F1',
    );
    final signin = _school(
      AgendaFeature.signin,
      's',
      '合成课程',
      at(5, 19),
      at(5, 20, 35),
    );
    final stray = _school(
      AgendaFeature.signin,
      't',
      '其他课程',
      at(5, 19),
      at(5, 20, 35),
    );
    final result = agendaAttachSignins(
      agendaMergeCourses([signin, stray, first, second]),
    );
    expect(result.map((e) => e.$1).toList(), [stray, first]);
    expect(result.last.$3, signin);
    expect(result.last.$2, agendaEnd(second));
  });
}
