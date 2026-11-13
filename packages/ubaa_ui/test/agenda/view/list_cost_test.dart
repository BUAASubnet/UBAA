import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/agenda/list_content.dart';
import 'view_modes_test.dart' show at;
import 'package:ubaa_ui/src/features/agenda/month_calendar.dart';
import 'package:ubaa_ui/src/features/agenda/calendar/month_grid.dart';

void main() {
  for (final wide in [false, true]) {
    testWidgets('月历按日期分组时只遍历一次来源，宽屏=$wide', (tester) async {
      final entries = _CountedEntries(_bookings());
      final date = DateTime.utc(2026, 11, 5);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: wide
                ? AgendaMonthGrid(
                    date: date,
                    today: date,
                    entries: entries,
                    allEntries: const [],
                    onSelected: (_) {},
                    onOpen: (_) {},
                  )
                : AgendaMonthCalendar(
                    date: date,
                    entries: entries,
                    onSelected: (_) {},
                  ),
          ),
        ),
      );
      expect(
        entries.reads,
        lessThanOrEqualTo(entries.length * 2),
        reason: '每个日期格不能重新扫描整个月的来源',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('长日程列表只为接近视口的条目计算课程冲突', (tester) async {
    final entries = _bookings();
    final all = _CountedEntries(entries);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => CustomScrollView(
              slivers: agendaListSlivers(
                context: context,
                entries: entries,
                allEntries: all,
                now: DateTime.utc(2026, 11, 5),
                onOpen: (_) {},
                onComplete: (_, _) {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      all.reads,
      lessThan(entries.length * 30),
      reason: '首屏不能为所有离屏预约扫描整份课表',
    );
    await tester.scrollUntilVisible(
      find.text('合成预约 199'),
      600,
      maxScrolls: 100,
    );
    expect(find.text('合成预约 199').hitTestable(), findsOneWidget);
  });
}

class _CountedEntries extends ListBase<AgendaEntry> {
  _CountedEntries(this.source);
  final List<AgendaEntry> source;
  int reads = 0;
  @override
  int get length => source.length;
  @override
  set length(int value) => throw UnsupportedError('只读');
  @override
  AgendaEntry operator [](int index) {
    reads++;
    return source[index];
  }

  @override
  void operator []=(int index, AgendaEntry value) =>
      throw UnsupportedError('只读');
}

List<AgendaEntry> _bookings() {
  return List.generate(200, (i) {
    final timing = AgendaTiming(
      kind: AgendaTimingKind.period,
      start: at(5, 10),
      end: at(5, 11),
    );
    return AgendaEntry(
      school: SchoolAgendaItem(
        key: SchoolAgendaKey(source: 'cgyy', upstreamId: '$i'),
        timing: timing,
        title: '合成预约 $i',
        subtitle: '',
        statusLabel: '已预约',
        upstreamStatus: AgendaUpstreamStatus(
          feature: AgendaFeature.cgyy,
          completed: false,
        ),
        navigation: AgendaNavigation(feature: AgendaFeature.cgyy),
        homeTodo: false,
      ),
      timing: timing,
      soon: false,
      completed: false,
      hidden: false,
    );
  });
}
