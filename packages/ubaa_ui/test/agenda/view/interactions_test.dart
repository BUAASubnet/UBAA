import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/agenda/list_content.dart';
import 'package:ubaa_ui/src/features/agenda/view.dart';
import '../flow_test.dart' show app, opened;
import '../support.dart';
import 'view_modes_test.dart' show at, course;
import 'view_support.dart';

Future<void> addItem(
  AgendaService service,
  String title,
  AgendaKind kind, {
  int day = 5,
}) async {
  await service.create(
    AgendaDraft(
      content: AgendaContent(
        kind: kind,
        title: title,
        allDay: false,
        start: kind == AgendaKind.event ? at(day, 9) : null,
        end: kind == AgendaKind.event ? at(day, 10) : null,
        due: kind == AgendaKind.task ? at(day, 18) : null,
      ),
      exdates: [],
    ),
    at(1, 9),
  );
}

List<String> visibleTitles(WidgetTester tester) => tester
    .widgetList<AgendaEntryTile>(find.byType(AgendaEntryTile))
    .map((tile) => tile.entry.local?.content.title ?? tile.entry.school!.title)
    .toList();

void main() {
  testWidgets('402pt日期条七天等宽完整可见，逐日点选显示对应事项并可滑动换周', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = MemoryAgenda();
    final service = await opened(backend);
    for (var day = 2; day <= 8; day++) {
      await addItem(service, '$day日待办', AgendaKind.task, day: day);
    }
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    final widths = <double>[];
    var right = 8.0;
    for (var day = 2; day <= 8; day++) {
      final date = agendaDateButton(
        '周${['一', '二', '三', '四', '五', '六', '日'][day - 2]} 11月$day日，有事项',
      );
      final rect = tester.getRect(date);
      expect(rect.left, closeTo(right, .01));
      expect(rect.right, lessThanOrEqualTo(394.01));
      widths.add(rect.width);
      right = rect.right;
      expect(date.hitTestable(), findsOneWidget);
      await tester.tap(date);
      await tester.pumpAndSettle();
      expect(tester.widget<Semantics>(date).properties.selected, isTrue);
      expect(visibleTitles(tester), ['$day日待办']);
    }
    expect(widths.every((width) => (width - widths.first).abs() < .01), isTrue);
    expect(right, closeTo(394, .01));
    await tester.fling(
      agendaDateButton('周日 11月8日，有事项'),
      const Offset(-260, 0),
      900,
    );
    await tester.pumpAndSettle();
    final state = tester.state<AgendaViewState>(find.byType(AgendaView));
    expect(state.focusDate, DateTime.utc(2026, 11, 15));
    expect(agendaDateButton('周一 11月9日').hitTestable(), findsOneWidget);
  });

  testWidgets('快捷筛选切换课程、待办和全部，选中状态与事项一致', (tester) async {
    final backend = MemoryAgenda()..school.add(course());
    final service = await opened(backend);
    await addItem(service, '本地待办', AgendaKind.task);
    await addItem(service, '本地日程', AgendaKind.event);
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    Future<void> select(String name, List<String> titles) async {
      final chip = find.widgetWithText(ChoiceChip, name);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
      expect(visibleTitles(tester), unorderedEquals(titles));
    }

    await select('课程', ['合成课程时段']);
    await select('全部', ['合成课程时段', '本地待办', '本地日程']);
    await select('待办', ['本地待办']);
    await select('全部', ['合成课程时段', '本地待办', '本地日程']);
  });
}
