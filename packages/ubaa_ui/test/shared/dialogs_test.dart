import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_ui/src/shared/dialogs/form_page.dart';
import 'package:ubaa_ui/src/shared/dialogs/sheet.dart';
import 'package:ubaa_ui/ubaa_ui.dart' show UbaaTheme;

Future<BuildContext> _mount(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      theme: UbaaTheme.light(),
      locale: UbaaTheme.locale,
      supportedLocales: UbaaTheme.supportedLocales,
      localizationsDelegates: UbaaTheme.localizationsDelegates,
      home: Scaffold(
        body: Builder(
          builder: (value) {
            context = value;
            return const SizedBox.expand();
          },
        ),
      ),
    ),
  );
  return context;
}

void main() {
  for (final size in [
    const Size(390, 800),
    const Size(1100, 800),
    const Size(1100, 400),
  ]) {
    testWidgets('面板在 $size 内滚动长内容，固定操作返回选中值', (tester) async {
      final context = await _mount(tester, size);
      final result = showUiSheet<String>(
        context,
        builder: (context) => UiSheetBody(
          title: '选择合成条目',
          children: [
            for (var i = 0; i < 24; i++) ListTile(title: Text('合成条目 $i')),
          ],
          primaryAction: FilledButton(
            onPressed: () => Navigator.pop(context, '合成选择结果'),
            child: const Text('确认选择'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final surface = size.height >= 480 && size.width >= 720
          ? find.byType(UiSheetBody)
          : find.byType(BottomSheet);
      final bounds = tester.getRect(surface);
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(size.width));
      expect(bounds.bottom, lessThanOrEqualTo(size.height));
      if (size.height >= 480 && size.width >= 720) {
        expect(bounds.width, lessThanOrEqualTo(480));
        expect(bounds.center.dx, closeTo(size.width / 2, 1));
      }
      final confirm = find.widgetWithText(FilledButton, '确认选择');
      final before = tester.getRect(confirm);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -1600),
      );
      await tester.pumpAndSettle();
      expect(find.text('合成条目 23').hitTestable(), findsOneWidget);
      expect(tester.getRect(confirm), before);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(await result, '合成选择结果');
      expect(tester.takeException(), isNull);
    });

    testWidgets('表单在 $size 内滚动并提交字段内容，宽屏点外面保留草稿', (tester) async {
      final context = await _mount(tester, size);
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final result = showUiPage<String>(
        context,
        builder: (context) => UiFormScaffold(
          title: '编辑合成条目',
          children: [
            TextField(controller: controller),
            const SizedBox(height: 1200),
            const Text('字段末尾'),
          ],
          secondary: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          primary: FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '保留的合成草稿');
      if (size.height >= 480 && size.width >= 720) {
        final bounds = tester.getRect(find.byType(UiFormScaffold));
        expect(bounds.width, lessThanOrEqualTo(560));
        expect(bounds.center.dx, closeTo(size.width / 2, 1));
        await tester.tapAt(const Offset(8, 8));
        await tester.pumpAndSettle();
        expect(controller.text, '保留的合成草稿');
        expect(find.byType(TextField).hitTestable(), findsOneWidget);
      }
      await tester.scrollUntilVisible(
        find.text('字段末尾'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('字段末尾').hitTestable(), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(await result, '保留的合成草稿');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('宽屏面板和表单可显式关闭，浏览子页面允许点外面退出', (tester) async {
    final context = await _mount(tester, const Size(1100, 800));
    final sheet = showUiSheet<void>(
      context,
      builder: (_) => const UiSheetBody(title: '合成面板'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await sheet;

    final form = showUiPage<String>(
      context,
      builder: (context) => UiFormScaffold(
        title: '合成表单',
        children: const [TextField()],
        primary: FilledButton(onPressed: () {}, child: const Text('保存')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(await form, isNull);

    final browser = showUiPage<String>(
      context,
      fixedHeight: true,
      builder: (_) => const Scaffold(body: Text('合成浏览页面')),
    );
    await tester.pumpAndSettle();
    final bounds = tester.getRect(
      find.descendant(of: find.byType(Dialog), matching: find.byType(Scaffold)),
    );
    expect(bounds.height, closeTo(800 * .88, 1));
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(await browser, isNull);
    expect(find.text('合成浏览页面'), findsNothing);
  });
}
