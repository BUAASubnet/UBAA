import 'dart:async';
import 'support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_ui/src/features/agenda/view.dart';

Future<AgendaService> opened(MemoryAgenda backend) async {
  final service = AgendaService(backend);
  await service.openAccount('synthetic');
  return service;
}

Widget app(
  AgendaService service, {
  Object scope = 1,
  String term = 'synthetic',
  Future<String?> Function(AgendaExportResult, String, bool Function())?
  saveFile,
}) => MaterialApp(
  theme: UbaaTheme.light(),
  localizationsDelegates: UbaaTheme.localizationsDelegates,
  supportedLocales: UbaaTheme.supportedLocales,
  locale: UbaaTheme.locale,
  home: Scaffold(
    body: AgendaView(
      service: service,
      scopeKey: scope,
      route: ConnectionMode.direct,
      term: term,
      now: DateTime(2026, 11, 5, 9),
      onSaveFile: saveFile,
      onOpenSchool: (_) {},
    ),
  ),
);
void main() {
  testWidgets('账号退出后清除旧事项并禁用本机编辑入口', (tester) async {
    final backend = MemoryAgenda();
    final service = await opened(backend);
    final now = AgendaTime(
      rfc3339: '2026-11-05T09:00:00+08:00',
      timezone: 'Asia/Shanghai',
    );
    await service.create(
      AgendaDraft(
        content: AgendaContent(
          kind: AgendaKind.task,
          title: '退出前事项',
          allDay: false,
        ),
        exdates: [],
      ),
      now,
    );
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    expect(find.text('退出前事项'), findsOneWidget);
    await service.close();
    await tester.pumpWidget(app(service, scope: 2));
    await tester.pumpAndSettle();
    expect(find.text('退出前事项'), findsNothing);
    expect(find.text('登录本机账号后可使用日程'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '新建事项'))
          .onPressed,
      isNull,
    );
  });
  testWidgets('新建待办保存后显示，完成与重新挂起保持，删除后消失', (tester) async {
    final backend = MemoryAgenda();
    final actual = await opened(backend);
    await tester.pumpWidget(app(actual));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建事项'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('待办'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('agenda-title')), '合成待办');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('保存事项'),
      250,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('agenda-editor-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存事项'));
    await tester.pumpAndSettle();
    expect(backend.items.values.single.content.title, '合成待办');
    expect(find.text('合成待办'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(
      backend.items.values.single.completions.single.completedAt,
      isNotNull,
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(backend.items.values.single.completions.single.completedAt, isNull);
    await tester.tap(find.text('合成待办'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除事项'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(backend.items, isEmpty);
    expect(find.text('合成待办'), findsNothing);
  });
  testWidgets('路线变化丢弃迟到查询并禁止旧编辑保存', (tester) async {
    final backend = MemoryAgenda();
    final service = await opened(backend);
    backend.gate = Completer();
    await tester.pumpWidget(app(service));
    await tester.pump();
    await tester.pumpWidget(app(service, scope: 2));
    await tester.pump();
    backend.gate!.complete(AgendaQueryResult(entries: [], sources: []));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建事项'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('agenda-title')), '旧编辑');
    await tester.pumpWidget(app(service, scope: 3));
    await tester.pumpAndSettle();
    if (find.text('保存事项').evaluate().isNotEmpty) {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('保存事项'),
        250,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('agenda-editor-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存事项'));
      await tester.pumpAndSettle();
    }
    expect(backend.writes, 0);
  });
}
