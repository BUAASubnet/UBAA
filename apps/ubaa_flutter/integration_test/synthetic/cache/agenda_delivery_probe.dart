import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_ui/src/features/agenda/view.dart';
import 'package:ubaa_ui/src/features/agenda/format.dart'
    show agendaTime, campusDate;

import '../../../../../packages/ubaa_app/test/runtime/shared_recovery_probe.dart'
    show openAccounts;

/// 真实 FFI、明文日程库与文件写出。只使用独立别名和合成内容。
Future<void> probeAgendaDelivery(WidgetTester tester, String directory) async {
  final root = await Directory('$directory/delivery').create(recursive: true);
  final accounts = await openAccounts(root);
  final account = await accounts.retain(
    'synthetic-agenda-delivery',
    retainSession: true,
  );
  final alias = account.account!.id;
  final backend = await BridgeBackend.open(root.path);
  final service = backend.agenda;
  AgendaTime at(int day, [int hour = 9]) => AgendaTime(
    rfc3339:
        '2026-11-${day.toString().padLeft(2, '0')}T${hour.toString().padLeft(2, '0')}:00:00+08:00',
    timezone: 'Asia/Shanghai',
  );
  AgendaTime mutationTime() => agendaTime(campusDate(DateTime.now()));
  AgendaContent content(String title, int day) => AgendaContent(
    kind: AgendaKind.event,
    title: title,
    allDay: false,
    start: at(day),
    end: at(day, 10),
  );
  final query = AgendaQuery(
    route: ConnectionMode.direct,
    term: 'synthetic',
    from: '2026-11-01',
    to: '2026-11-12',
    now: at(5),
    includeHidden: false,
    ygdkEnabled: false,
    ygdkWeekDone: false,
    ygdkTermDone: false,
  );
  try {
    await backend.setDefaultRoutePolicy(RoutePolicy.direct);
    await backend.bindSharedAccount(
      await accounts.bindSnapshot((await accounts.capture())!),
    );
    await service.openAccount(alias);
    final item = await service.create(
      AgendaDraft(
        content: content('合成逐日日程', 5),
        rrule: 'FREQ=DAILY;COUNT=4',
        exdates: [at(6)],
      ),
      mutationTime(),
    );
    expect((await service.query(query)).entries, hasLength(3));
    final saved = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        localizationsDelegates: UbaaTheme.localizationsDelegates,
        supportedLocales: UbaaTheme.supportedLocales,
        locale: UbaaTheme.locale,
        home: Scaffold(
          body: AgendaView(
            service: service,
            scopeKey: alias,
            route: ConnectionMode.direct,
            term: 'synthetic',
            now: DateTime(2026, 11, 5, 9),
            onOpenSchool: (_) => fail('合成本机事项不应请求学校'),
            onChanged: () => saved.complete(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('合成逐日日程').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑事项'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仅此次'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('agenda-title')), '单次修改');
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
    await saved.future.timeout(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    var values = (await service.query(query)).entries;
    expect(values.map((e) => e.local!.content.title), [
      '单次修改',
      '合成逐日日程',
      '合成逐日日程',
    ]);
    final successor = await service.editDraft(
      item.id,
      AgendaEditScope.thisAndFuture,
      at(7),
      AgendaDraft(
        content: content('以后修改', 7),
        rrule: 'FREQ=DAILY;COUNT=2',
        exdates: [at(8)],
      ),
      mutationTime(),
    );
    expect(successor, isNotNull);
    values = (await service.query(query)).entries;
    expect(values.map((e) => e.local!.content.title), ['单次修改', '以后修改']);
    await service.editDraft(
      successor!,
      AgendaEditScope.all,
      null,
      AgendaDraft(
        content: content('系列修改', 7),
        rrule: 'FREQ=DAILY;COUNT=3',
        exdates: [at(8)],
      ),
      mutationTime(),
    );
    await service.close();
    await service.openAccount(alias);
    values = (await service.query(query)).entries;
    expect(values.map((e) => e.local!.content.title), ['单次修改', '系列修改', '系列修改']);
    await service.complete(successor, at(7), true, mutationTime());
    final export = await service.exportIcs(query);
    expect(export.exportedCount, 2);
    expect(export.ics, contains('SUMMARY:单次修改'));
    expect(export.ics, contains('SUMMARY:系列修改'));
    expect(export.ics.split('BEGIN:VEVENT'), hasLength(3));
    final file = File('$directory/delivery/synthetic.ics');
    final saver = SystemAgendaFileSaver(
      selectLocation: (_) async => file.path,
      operatingSystem: 'macos',
    );
    expect(
      await saver.save(export.ics, 'synthetic.ics', () => true),
      AgendaFileResult.saved,
    );
    expect(await file.readAsString(), export.ics);
    expect(export.ics.replaceAll('\r\n', ''), isNot(contains('\n')));
    await service.delete(
      successor,
      AgendaEditScope.thisOccurrence,
      at(9),
      mutationTime(),
    );
    expect((await service.query(query)).entries, hasLength(2));
    await service.delete(successor, AgendaEditScope.all, null, mutationTime());
    await service.delete(item.id, AgendaEditScope.all, null, mutationTime());
    expect((await service.query(query)).entries, isEmpty);
  } finally {
    await tester.pumpWidget(const SizedBox());
    await service.dispose();
    await backend.dispose();
  }
}
