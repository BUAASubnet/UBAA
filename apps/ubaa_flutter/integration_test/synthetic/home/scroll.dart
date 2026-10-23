import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 先展示待办窗口，再在独立列表中寻找可点击目标。
Future<void> ensureHomeTodo(WidgetTester tester, Finder target) async {
  final window = find.byKey(const ValueKey('home-todos'));
  final outer = find
      .descendant(
        of: find.byKey(const ValueKey('home-scroll')),
        matching: find.byType(Scrollable),
      )
      .first;
  if (window.evaluate().isEmpty) {
    await tester.scrollUntilVisible(window, 200, scrollable: outer);
  }
  await Scrollable.ensureVisible(tester.element(window), alignment: .4);
  await tester.pumpAndSettle();
  final inner = find.descendant(of: window, matching: find.byType(Scrollable));
  await tester.drag(inner, const Offset(0, 30000));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    target.hitTestable(),
    160,
    scrollable: inner,
    maxScrolls: 100,
  );
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
}
