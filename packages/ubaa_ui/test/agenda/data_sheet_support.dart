import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openAgendaDataSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('agenda-data-notice')));
  await tester.pumpAndSettle();
}

Future<void> closeAgendaDataSheet(WidgetTester tester) async {
  Navigator.of(tester.element(find.text('数据与同步'))).pop();
  await tester.pumpAndSettle();
}
