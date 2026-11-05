import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_ui/src/features/bhpan/chrome.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

Future<void> mountBhpan(WidgetTester tester, BhpanAccess access) async {
  tester.view.physicalSize = const Size(1000, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: UbaaTheme.light(),
      home: Scaffold(body: BhpanView(access: access)),
    ),
  );
  await tester.pumpAndSettle();
}

Finder itemRow(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(BhpanItemTile));

Future<void> openItemActions(WidgetTester tester, String name) async {
  await tester.tap(
    find.descendant(of: itemRow(name), matching: find.byTooltip('更多操作')),
  );
  await tester.pumpAndSettle();
}

Future<void> openCloudMenu(WidgetTester tester, String action) async {
  await tester.tap(find.byTooltip('更多云盘操作'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

Future<void> openCreateSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('bhpan-create')));
  await tester.pumpAndSettle();
}

Finder sheetAction(String action) => find.descendant(
  of: find.byType(BottomSheet),
  matching: find.widgetWithText(ListTile, action),
);
