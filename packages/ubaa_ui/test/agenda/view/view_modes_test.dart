import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../flow_test.dart' show app, opened;
import '../editor/actions_test.dart' show saveEditor;
import '../support.dart';
import '../editor/pickers_support.dart';

AgendaTime at(int day, int hour, [int minute = 0]) => AgendaTime(
  rfc3339:
      '2026-11-${day.toString().padLeft(2, '0')}T${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:00+08:00',
  timezone: 'Asia/Shanghai',
);

SchoolAgendaItem course() => SchoolAgendaItem(
  key: SchoolAgendaKey(source: 'schedule', upstreamId: 'synthetic-course'),
  timing: AgendaTiming(
    kind: AgendaTimingKind.period,
    start: at(5, 10),
    end: at(5, 11),
  ),
  title: '合成课程时段',
  subtitle: '合成课堂',
  statusLabel: '已缓存',
  upstreamStatus: AgendaUpstreamStatus(
    feature: AgendaFeature.schedule,
    completed: false,
  ),
  navigation: AgendaNavigation(
    feature: AgendaFeature.schedule,
    courseCode: 'synthetic-course',
  ),
  homeTodo: false,
);

Future<void> reveal(
  WidgetTester tester,
  Finder target, {
  bool fromTop = false,
}) async {
  final scroll = find
      .descendant(
        of: find.byKey(const ValueKey('agenda-main-scroll')),
        matching: find.byType(Scrollable),
      )
      .first;
  if (fromTop) {
    tester.state<ScrollableState>(scroll).position.jumpTo(0);
    await tester.pumpAndSettle();
  }
  if (target.hitTestable().evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 180, scrollable: scroll);
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('隐藏课程后仍显示自建事项的课程冲突，课程条目保持隐藏', (tester) async {
    final backend = MemoryAgenda()..school.add(course());
    final service = await opened(backend);
    await service.create(
      AgendaDraft(
        content: AgendaContent(
          kind: AgendaKind.event,
          title: '保留冲突提示的安排',
          allDay: false,
          start: at(5, 10),
          end: at(5, 11),
        ),
        exdates: [],
      ),
      at(1, 9),
    );
    await service.setOverlay(
      AgendaOverlayDraft(
        key: course().key,
        completionOverride: false,
        hidden: true,
      ),
      at(1, 9),
    );
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    expect(find.text('保留冲突提示的安排'), findsOneWidget);
    expect(find.text('合成课程时段'), findsNothing);
    expect(find.textContaining('与课程重叠：合成课程时段'), findsOneWidget);
  });

  testWidgets('月历选日与周视图沿用焦点日期、发生记录和来源筛选', (tester) async {
    final backend = MemoryAgenda()..school.add(course());
    final service = await opened(backend);
    await service.create(
      AgendaDraft(
        content: AgendaContent(
          kind: AgendaKind.event,
          title: '六日安排',
          allDay: false,
          start: at(6, 9),
          end: at(6, 10),
        ),
        exdates: [],
      ),
      at(1, 9),
    );
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();
    final day = find.byKey(const ValueKey('agenda-day-2026-11-06'));
    await reveal(tester, day);
    await tester.tap(day);
    await tester.pumpAndSettle();
    expect(find.text('六日安排'), findsOneWidget);
    expect(find.text('合成课程时段'), findsNothing);
    await reveal(tester, find.text('周'), fromTop: true);
    await tester.tap(find.text('周'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const ValueKey('agenda-week-grid')));
    expect(find.byKey(const ValueKey('agenda-week-grid')), findsOneWidget);
    expect(find.text('合成课程时段'), findsOneWidget);
    expect(find.text('六日安排'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.widgetWithText(ChoiceChip, '我的'),
      180,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('agenda-quick-filters')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.widgetWithText(ChoiceChip, '我的'));
    await tester.pumpAndSettle();
    expect(find.text('合成课程时段'), findsNothing);
    expect(find.text('六日安排'), findsOneWidget);
    await reveal(tester, find.text('列表'), fromTop: true);
    await tester.tap(find.text('列表'));
    await tester.pumpAndSettle();
    expect(find.text('六日安排'), findsOneWidget);
    expect(backend.lastQuery!.route, ConnectionMode.direct);
  });

  testWidgets('自建事项保存前提示已缓存课程冲突，返回修改不写入，确认后保存', (tester) async {
    final backend = MemoryAgenda()..school.add(course());
    final service = await opened(backend);
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('agenda-title')),
      '合成重叠安排',
    );
    await setEditorTime(tester, 'start', 10, 15);
    await setEditorTime(tester, 'end', 10, 45);
    await saveEditor(tester);
    expect(backend.writes, 0, reason: '用户确认冲突前不得保存事项');
    expect(find.widgetWithText(AlertDialog, '与课程时间冲突'), findsOneWidget);
    await tester.tap(find.text('返回修改'));
    await tester.pumpAndSettle();
    expect(backend.items, isEmpty);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('agenda-title')),
      -200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('agenda-editor-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('agenda-title')))
          .controller!
          .text,
      '合成重叠安排',
    );
    await saveEditor(tester);
    await tester.tap(find.text('仍然保存'));
    await tester.pumpAndSettle();
    expect(backend.items.values.single.content.title, '合成重叠安排');
    expect(backend.school.single.title, '合成课程时段');
  });
}
