import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/agenda/calendar/month_grid.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../flow_test.dart' show app, opened;
import '../support.dart';
import 'interactions_test.dart' show addItem;
import 'view_modes_test.dart' show at;

Finder _day(String date) => find.byKey(ValueKey('agenda-month-cell-$date'));

Future<void> _grid(
  WidgetTester tester, {
  List<AgendaEntry> entries = const [],
  ValueChanged<DateTime>? onSelected,
  ValueChanged<AgendaEntry>? onOpen,
}) => tester.pumpWidget(
  MaterialApp(
    theme: UbaaTheme.light(),
    home: Scaffold(
      body: AgendaMonthGrid(
        date: DateTime.utc(2026, 11, 5),
        today: DateTime.utc(2026, 11, 8),
        entries: entries,
        allEntries: entries,
        onSelected: onSelected ?? (_) {},
        onOpen: onOpen ?? (_) {},
      ),
    ),
  ),
);

void _viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('月网格按周一到周日排列，补齐相邻月份且可选中相邻月日期', (tester) async {
    _viewport(tester, const Size(1200, 600));
    final selected = <DateTime>[];
    await _grid(tester, onSelected: selected.add);
    await tester.pumpAndSettle();
    final monday = tester.getRect(_day('2026-10-26'));
    final sunday = tester.getRect(_day('2026-11-01'));
    final nextMonday = tester.getRect(_day('2026-11-02'));
    expect(sunday.top, closeTo(monday.top, .01));
    expect(sunday.right, closeTo(1200, .01));
    expect(nextMonday.left, closeTo(monday.left, .01));
    expect(nextMonday.top, closeTo(monday.bottom, .01));
    expect(_day('2026-12-06').hitTestable(), findsOneWidget);
    await tester.tap(_day('2026-10-31'));
    expect(selected.single, DateTime.utc(2026, 10, 31));
  });

  testWidgets('月网格溢出列表可打开原事项，点击事项不触发选日', (tester) async {
    _viewport(tester, const Size(1200, 600));
    final backend = MemoryAgenda();
    final service = await opened(backend);
    for (var index = 0; index < 5; index++) {
      await addItem(service, '月历待办$index', AgendaKind.task);
    }
    final entries = (await backend.query(
      AgendaQuery(
        route: ConnectionMode.direct,
        term: 'synthetic',
        from: '2026-11-01',
        to: '2026-12-01',
        now: at(5, 9),
        includeHidden: false,
        ygdkEnabled: false,
        ygdkWeekDone: false,
        ygdkTermDone: false,
      ),
    )).entries;
    final selected = <DateTime>[];
    final openedEntries = <AgendaEntry>[];
    await _grid(
      tester,
      entries: entries,
      onSelected: selected.add,
      onOpen: openedEntries.add,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: _day('2026-11-05'),
        matching: find.textContaining('月历待办0'),
      ),
    );
    expect(openedEntries.single, same(entries.first));
    expect(selected, isEmpty);
    openedEntries.clear();
    final overflow = find.descendant(
      of: _day('2026-11-05'),
      matching: find.textContaining('还有'),
    );
    expect(overflow.hitTestable(), findsOneWidget);
    await tester.tap(overflow);
    await tester.pumpAndSettle();
    final last = find.widgetWithText(ListTile, '月历待办4');
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(openedEntries.single, same(entries.last));
    expect(selected, isEmpty);
    expect(last, findsNothing);
  });

  testWidgets('宽屏月网格跨日打开事项后显示对应详情，翻月清除旧详情', (tester) async {
    _viewport(tester, const Size(1600, 1000));
    final backend = MemoryAgenda();
    final service = await opened(backend);
    await addItem(service, '六日安排', AgendaKind.event, day: 6);
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('月视图'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: _day('2026-11-06'),
        matching: find.textContaining('六日安排'),
      ),
    );
    await tester.pumpAndSettle();
    final pane = find.byKey(const ValueKey('agenda-detail-pane'));
    expect(
      find.descendant(of: pane, matching: find.text('六日安排')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: pane, matching: find.text('编辑事项')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('下一月'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: pane, matching: find.text('选择事项查看详情')),
      findsOneWidget,
    );
  });
}
