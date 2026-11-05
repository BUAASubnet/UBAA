import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Finder> openAgendaSearch(WidgetTester tester) async {
  await tester.tap(find.byTooltip('搜索日程'));
  await tester.pumpAndSettle();
  return find.descendant(
    of: find.byKey(const ValueKey('agenda-search')),
    matching: find.byType(TextField),
  );
}

Future<void> selectAgendaMenu(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('更多日程操作'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Finder agendaDateButton(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);
