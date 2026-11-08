import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/agenda/editor.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../flow_test.dart' show opened;
import '../support.dart';
import 'pickers_support.dart';

Future<void> openEditor(
  WidgetTester tester,
  AgendaService service, {
  TextScaler textScaler = TextScaler.noScaling,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? UbaaTheme.light(),
      localizationsDelegates: UbaaTheme.localizationsDelegates,
      supportedLocales: UbaaTheme.supportedLocales,
      locale: UbaaTheme.locale,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => AgendaEditor(
                  service: service,
                  isCurrent: () => true,
                  now: DateTime(2026, 11, 5, 9),
                  boundary: (child) => child,
                ),
              ),
            ),
            child: const Text('打开编辑器'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开编辑器'));
  await tester.pumpAndSettle();
}

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('日期与时间选择器修改日程并保存校园时区时间', (tester) async {
    phone(tester);
    final backend = MemoryAgenda();
    await openEditor(tester, await opened(backend));
    expect(
      tester.getRect(find.byKey(const ValueKey('agenda-editor-save'))).bottom,
      lessThanOrEqualTo(874),
    );
    await tester.enterText(find.byKey(const ValueKey('agenda-title')), '选择日期');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await setEditorDate(tester, 'start', 6);
    await setEditorDate(tester, 'end', 6);
    await setEditorTime(tester, 'start', 10, 15);
    await setEditorTime(tester, 'end', 11, 45);
    await saveAgendaEditor(tester);
    final content = backend.items.values.single.content;
    expect(content.start?.rfc3339, '2026-11-06T10:15:00+08:00');
    expect(content.end?.rfc3339, '2026-11-06T11:45:00+08:00');
    expect(content.start?.timezone, 'Asia/Shanghai');
  });

  testWidgets('全天日程通过日期选择器保存结束日排除的日期范围', (tester) async {
    phone(tester);
    final backend = MemoryAgenda();
    await openEditor(tester, await opened(backend));
    await tester.enterText(find.byKey(const ValueKey('agenda-title')), '全天安排');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, '全天'));
    await tester.pumpAndSettle();
    await setEditorDate(tester, 'end', 6);
    await saveAgendaEditor(tester);
    final content = backend.items.values.single.content;
    expect(content.allDay, isTrue);
    expect(content.start?.rfc3339, '2026-11-05T00:00:00+08:00');
    expect(content.end?.rfc3339, '2026-11-06T00:00:00+08:00');
  });

  testWidgets('无日期待办保存时不附加截止时间', (tester) async {
    phone(tester);
    final backend = MemoryAgenda();
    await openEditor(tester, await opened(backend));
    await tester.tap(find.text('待办'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, '无日期待办'));
    await tester.enterText(find.byKey(const ValueKey('agenda-title')), '无日期待办');
    await saveAgendaEditor(tester);
    final content = backend.items.values.single.content;
    expect(content.kind, AgendaKind.task);
    expect(content.due, isNull);
  });

  testWidgets('日期待办通过选择器保存截止时间', (tester) async {
    phone(tester);
    final backend = MemoryAgenda();
    await openEditor(tester, await opened(backend));
    await tester.tap(find.text('待办'));
    await tester.pumpAndSettle();
    await setEditorDate(tester, 'due', 7);
    await setEditorTime(tester, 'due', 16, 30);
    await tester.enterText(find.byKey(const ValueKey('agenda-title')), '日期待办');
    await saveAgendaEditor(tester);
    expect(
      backend.items.values.single.content.due?.rfc3339,
      '2026-11-07T16:30:00+08:00',
    );
  });

  testWidgets('颜色色块保存所选颜色并保留日程时间', (tester) async {
    phone(tester);
    final backend = MemoryAgenda();
    await openEditor(tester, await opened(backend));
    await tester.enterText(find.byKey(const ValueKey('agenda-title')), '绿色安排');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final green = find.byTooltip('绿色');
    await tester.scrollUntilVisible(
      green,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('agenda-editor-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(green);
    await tester.pumpAndSettle();
    await saveAgendaEditor(tester);
    final content = backend.items.values.single.content;
    expect(content.color, '#30856A');
    expect(content.start?.rfc3339, '2026-11-05T09:00:00+08:00');
    expect(content.end?.rfc3339, '2026-11-05T10:00:00+08:00');
  });

  testWidgets('暗色大字体下保存按钮固定，说明文字可滚动且不重叠', (tester) async {
    phone(tester);
    final backend = MemoryAgenda();
    await openEditor(
      tester,
      await opened(backend),
      theme: UbaaTheme.dark(),
      textScaler: const TextScaler.linear(1.8),
    );
    final save = find.byKey(const ValueKey('agenda-editor-save'));
    final before = tester.getRect(save);
    final note = find.text('时间均为北京时间');
    await tester.scrollUntilVisible(
      note,
      250,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('agenda-editor-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    final after = tester.getRect(save);
    expect(after, before);
    expect(after.height, greaterThanOrEqualTo(44));
    expect(tester.getRect(note).bottom, lessThanOrEqualTo(after.top));
    expect(tester.takeException(), isNull);
  });
}
