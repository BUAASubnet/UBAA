part of 'flow_test.dart';

Future<void> _ensure(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final scroll = find
        .byElementPredicate((element) {
          final widget = element.widget;
          // 排除错误编号等可选择文本内部的20像素滚动区。
          return widget is Scrollable &&
              widget.axisDirection == AxisDirection.down &&
              widget.physics is! NeverScrollableScrollPhysics &&
              element is StatefulElement &&
              (element.state as ScrollableState).position.viewportDimension >
                  100;
        })
        .hitTestable()
        .last;
    await tester.drag(scroll, const Offset(0, 1200));
    await tester.pumpAndSettle();
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        240,
        scrollable: scroll,
        maxScrolls: 80,
      );
    }
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _ensure(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _edit(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(TextField, label);
  // 项目选择对话框关闭后，等待表单恢复，再定位输入框。
  await uiWaitFor(tester, () => field.evaluate().isNotEmpty, '阳光表单未显示$label');
  await _tap(tester, field);
  await tester.enterText(field, value);
  await tester.pump();
  expect(tester.widget<TextField>(field).controller!.text, value);
}

final _searchField = find.byKey(const ValueKey<String>('feature-search-field'));

/// 搜索框常驻列表顶部，输入即过滤，不经筛选面板。
Future<void> _search(WidgetTester tester, String value) async {
  await _tap(tester, _searchField);
  await tester.enterText(_searchField, value);
  await tester.pump();
  expect(tester.widget<TextField>(_searchField).controller!.text, value);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> _shot(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
  String steps,
) async {
  await tester.pump(const Duration(milliseconds: 300));
  expect(tester.takeException(), isNull);
  final size = tester.view.physicalSize, ratio = tester.view.devicePixelRatio;
  final records =
      (binding.reportData ??= <String, dynamic>{}).putIfAbsent(
            'uiEvidence',
            () => <Object?>[],
          )
          as List;
  records.add({
    'name': name,
    'steps': steps,
    'backend': 'synthetic-sports',
    'platform': Platform.operatingSystem,
    'system': Platform.operatingSystemVersion,
    'logicalWidth': size.width / ratio,
    'logicalHeight': size.height / ratio,
    'devicePixelRatio': ratio,
    'viewportSource': 'native-view-unmodified',
    'dateUtc': DateTime.now().toUtc().toIso8601String(),
    'sourceSha': const String.fromEnvironment('UBAA_UI_SOURCE_SHA'),
  });
  if (Platform.isIOS) {
    await binding.takeScreenshot(name);
  } else {
    debugPrint('原生阳光检查点：$name');
  }
}
