import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 沿首页主滚动找到待办，必要时先展开完整列表。
Future<void> ensureHomeTodo(WidgetTester tester, Finder target) async {
  if (target.hitTestable().evaluate().isNotEmpty) return;
  final outer = find
      .descendant(
        of: find.byKey(const ValueKey('home-scroll')),
        matching: find.byType(Scrollable),
      )
      .first;
  tester.state<ScrollableState>(outer).position.jumpTo(0);
  await tester.pumpAndSettle();
  final preview = find.byKey(const ValueKey('home-todos'));
  if (preview.evaluate().isEmpty) {
    await tester.scrollUntilVisible(preview, 200, scrollable: outer);
  }
  if (target.evaluate().isEmpty) {
    final toggle = find.byKey(const ValueKey('home-todos-toggle'));
    if (toggle.evaluate().isNotEmpty && find.text('收起').evaluate().isEmpty) {
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
    }
  }
  await tester.scrollUntilVisible(
    target.hitTestable(),
    160,
    scrollable: outer,
    maxScrolls: 100,
  );
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
}
