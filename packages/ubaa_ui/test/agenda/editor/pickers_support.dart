import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> setEditorTime(
  WidgetTester tester,
  String field,
  int hour,
  int minute,
) async {
  final target = find.byKey(ValueKey('agenda-$field-time'));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.keyboard_outlined));
  await tester.pumpAndSettle();
  final inputs = find.descendant(
    of: find.byType(TimePickerDialog),
    matching: find.byType(TextFormField),
  );
  await tester.enterText(inputs.first, '$hour');
  await tester.enterText(inputs.last, minute.toString().padLeft(2, '0'));
  await tester.tap(find.text('确定').last);
  await tester.pumpAndSettle();
}

Future<void> setEditorDate(WidgetTester tester, String field, int day) async {
  final target = find.byKey(ValueKey('agenda-$field-date'));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
  await tester.tap(find.text('$day').last);
  await tester.tap(find.text('确定').last);
  await tester.pumpAndSettle();
}

Future<void> saveAgendaEditor(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('agenda-editor-save')));
  await tester.pumpAndSettle();
}
