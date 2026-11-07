import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/agenda/week_content.dart';
import '../flow_test.dart' show app, opened;
import 'view_modes_test.dart' show at, course, reveal;
import '../support.dart';

void main() {
  testWidgets('列表翻周保留范围内其他日期的事项，选日筛选仍可单独开启', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final backend = MemoryAgenda();
      final service = await opened(backend);
      await service.create(
        AgendaDraft(
          content: AgendaContent(
            kind: AgendaKind.task,
            title: '十三日待办',
            allDay: false,
            due: at(13, 18),
          ),
          exdates: [],
        ),
        at(1, 9),
      );
      await tester.pumpWidget(app(service));
      await tester.pumpAndSettle();
      expect(find.text('十三日待办'), findsOneWidget);
      await tester.tap(find.byTooltip('下一周'));
      await tester.pumpAndSettle();
      expect(find.text('十三日待办'), findsOneWidget);
      await tester.tap(find.byTooltip('上一周'));
      await tester.pumpAndSettle();
      expect(find.text('十三日待办'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('周四 11月5日'));
      await tester.pumpAndSettle();
      expect(find.text('十三日待办'), findsNothing);
      await tester.tap(find.text('显示全部日期'));
      await tester.pumpAndSettle();
      expect(find.text('十三日待办'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('周视图顶部的全天事项也显示课程冲突', (tester) async {
    final backend = MemoryAgenda()..school.add(course());
    final service = await opened(backend);
    await service.create(
      AgendaDraft(
        content: AgendaContent(
          kind: AgendaKind.event,
          title: '全天避课安排',
          allDay: true,
          start: at(5, 0),
          end: at(6, 0),
        ),
        exdates: [],
      ),
      at(1, 9),
    );
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('周'));
    await tester.pumpAndSettle();
    await reveal(tester, find.textContaining('全天避课安排'));
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(
              of: find.textContaining('全天避课安排'),
              matching: find.byType(Tooltip),
            ),
          )
          .message,
      contains('与课程重叠'),
    );
  });

  testWidgets('全天行每天直接显示两项，其余收成 +N 并可打开', (tester) async {
    final backend = MemoryAgenda();
    final service = await opened(backend);
    for (final (title, hour) in [('第一项', 18), ('第二项', 20), ('第三项', 22)])
      await service.create(
        AgendaDraft(
          content: AgendaContent(
            kind: AgendaKind.task,
            title: title,
            allDay: false,
            due: at(5, hour),
          ),
          exdates: [],
        ),
        at(1, 9),
      );
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('周'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第三项'), findsNothing);
    await tester.tap(find.text('+1'));
    await tester.pumpAndSettle();
    expect(find.text('第三项'), findsOneWidget);
    expect(find.text('第一项'), findsOneWidget);
  });

  testWidgets('重叠时段并排可分别打开，跨午夜沿同一发生身份分列，截止项位于顶部', (tester) async {
    final backend = MemoryAgenda();
    final service = await opened(backend);
    Future<AgendaItem> create(String title, int first, int last) =>
        service.create(
          AgendaDraft(
            content: AgendaContent(
              kind: AgendaKind.event,
              title: title,
              allDay: false,
              start: at(5, first),
              end: at(5, last),
            ),
            exdates: [],
          ),
          at(1, 9),
        );
    final first = await create('第一个时段', 9, 11);
    final second = await create('第二个时段', 10, 12);
    final overnight = await service.create(
      AgendaDraft(
        content: AgendaContent(
          kind: AgendaKind.event,
          title: '跨午夜安排',
          allDay: false,
          start: at(5, 23),
          end: at(6, 1),
        ),
        exdates: [],
      ),
      at(1, 9),
    );
    await service.create(
      AgendaDraft(
        content: AgendaContent(
          kind: AgendaKind.task,
          title: '周五截止',
          allDay: false,
          due: at(6, 18),
        ),
        exdates: [],
      ),
      at(1, 9),
    );
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('周'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const ValueKey('agenda-week-grid')));
    Finder slot(AgendaItem item, int day) => find.byKey(
      ValueKey(
        'agenda-week-local:${item.id}:${item.content.start!.rfc3339}-$day',
      ),
    );
    final a = tester.getRect(slot(first, 3)),
        b = tester.getRect(slot(second, 3));
    expect(a.right, lessThanOrEqualTo(b.left), reason: '时间重叠时不能互相遮挡');
    expect(find.textContaining('周五截止'), findsOneWidget);
    expect(
      tester.getTopLeft(find.textContaining('周五截止')).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('agenda-week-grid'))).dy,
      ),
    );
    expect(slot(overnight, 3), findsOneWidget);
    expect(slot(overnight, 4), findsOneWidget);
    await tester.tapAt(a.center);
    await tester.pumpAndSettle();
    expect(find.text('编辑事项'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭详情'));
    await tester.pumpAndSettle();
    await tester.tapAt(b.center);
    await tester.pumpAndSettle();
    expect(find.text('第二个时段'), findsWidgets);
    expect(find.text('编辑事项'), findsOneWidget);
  });

  testWidgets('默认列表保留原日期范围内跨周待办', (tester) async {
    final backend = MemoryAgenda();
    final service = await opened(backend);
    await service.create(
      AgendaDraft(
        content: AgendaContent(
          kind: AgendaKind.task,
          title: '后续周的待办',
          allDay: false,
          due: at(20, 18),
        ),
        exdates: [],
      ),
      at(1, 9),
    );
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    expect(find.text('后续周的待办'), findsOneWidget);
  });

  testWidgets('窄屏周视图七列完整可见且无需横向滚动，每天均可点选', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final selected = <DateTime>[];
    final semantics = tester.ensureSemantics();
    try {
      for (final width in [320.0, 402.0]) {
        tester.view.physicalSize = Size(width, 874);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AgendaWeekContent(
                  date: DateTime.utc(2026, 11, 5),
                  entries: const [],
                  allEntries: const [],
                  onOpen: (_) {},
                  onDate: selected.add,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final bounds = tester.getRect(find.byType(AgendaWeekContent));
        for (var index = 0; index < 7; index++) {
          final day = DateTime.utc(2026, 11, 2 + index);
          final header = find.bySemanticsLabel(
            '周${['一', '二', '三', '四', '五', '六', '日'][index]} 11月${day.day}日',
          );
          final rect = tester.getRect(header);
          expect(rect.left, greaterThanOrEqualTo(bounds.left));
          expect(rect.right, lessThanOrEqualTo(bounds.right + .001));
          expect(rect.width, closeTo((bounds.width - 40) / 7, .001));
          await tester.tap(header);
          expect(selected.last, day);
        }
        for (final scrollable in tester.stateList<ScrollableState>(
          find.descendant(
            of: find.byType(AgendaWeekContent),
            matching: find.byType(Scrollable),
          ),
        )) {
          if (scrollable.position.axis == Axis.horizontal) {
            expect(scrollable.position.maxScrollExtent, 0);
          }
        }
        expect(tester.takeException(), isNull);
      }
    } finally {
      semantics.dispose();
    }
  });
}
