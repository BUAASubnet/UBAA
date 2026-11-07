import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openAgendaDataSheet(WidgetTester tester) async {
  await tester.tap(find.byTooltip('更多日程操作'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('agenda-data-menu')));
  await tester.pumpAndSettle();
}

Future<void> closeAgendaDataSheet(WidgetTester tester) async {
  // 模态面板只留拖动条，点面板外的遮罩关闭。
  await tester.tapAt(const Offset(8, 8));
  await tester.pumpAndSettle();
}
