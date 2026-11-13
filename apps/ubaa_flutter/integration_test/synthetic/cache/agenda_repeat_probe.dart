import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/agenda/view.dart';
import 'package:ubaa_ui/src/features/agenda/list_content.dart'
    show AgendaEntryTile;
import 'package:ubaa_ui/src/features/agenda/format.dart'
    show agendaTime, campusDate;

import '../../../../../packages/ubaa_app/test/runtime/shared_recovery_probe.dart'
    show openAccounts;

/// 通过真实编辑器和 FFI 验证系列平移保留单次删除。
Future<void> probeAgendaRepeat(WidgetTester tester, String directory) async {
  for (final scope in [AgendaEditScope.all, AgendaEditScope.thisAndFuture]) {
    final root = await Directory('$directory/repeat_${scope.name}')
        .create(recursive: true);
    final accounts = await openAccounts(root);
    final account = await accounts.retain(
      'synthetic-agenda-repeat',
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
    final label = scope == AgendaEditScope.all ? '全部' : '此次及以后';
    try {
      await backend.setDefaultRoutePolicy(RoutePolicy.direct);
      await backend.bindSharedAccount(
        await accounts.bindSnapshot((await accounts.capture())!),
      );
      await service.openAccount(alias);
      final item = await service.create(
        AgendaDraft(
          content: AgendaContent(
            kind: AgendaKind.event,
            title: '系列平移',
            allDay: false,
            start: at(5),
            end: at(5, 10),
          ),
          rrule: 'FREQ=DAILY;COUNT=5',
          exdates: [],
        ),
        agendaTime(campusDate(DateTime.now())),
      );
      await service.delete(
        item.id,
        AgendaEditScope.thisOccurrence,
        at(8),
        agendaTime(campusDate(DateTime.now())),
      );
      expect(
        (await service.query(query)).entries
            .map((e) => e.local!.content.start!.rfc3339.substring(8, 10)),
        ['05', '06', '07', '09'],
      );
      final saved = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgendaView(
              service: service,
              scopeKey: alias,
              route: ConnectionMode.direct,
              term: 'synthetic',
              now: DateTime(2026, 11, 5, 9),
              onOpenSchool: (_) => fail('本机编辑不读取学校'),
              onChanged: () => saved.complete(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final occurrence = at(scope == AgendaEditScope.all ? 5 : 6).rfc3339;
      final target = find.descendant(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is AgendaEntryTile &&
              widget.entry.local?.itemId == item.id &&
              widget.entry.local?.recurrenceId == occurrence,
        ),
        matching: find.text('系列平移'),
      );
      await tester.scrollUntilVisible(
        target,
        180,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('agenda-main-scroll')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(target.hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑事项'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, label));
      await tester.pumpAndSettle();
      final day = scope == AgendaEditScope.all ? 6 : 7;
      for (final field in ['start', 'end']) {
        final target = find.byKey(ValueKey('agenda-$field-date'));
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
        final dialog = find.byType(DatePickerDialog);
        await tester.tap(
          find.descendant(of: dialog, matching: find.text('$day')),
        );
        final confirm = MaterialLocalizations.of(tester.element(dialog))
            .okButtonLabel;
        await tester.tap(
          find.descendant(of: dialog, matching: find.text(confirm)),
        );
        await tester.pumpAndSettle();
      }
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
      final entries = (await service.query(query)).entries;
      expect(
        entries.map((e) => e.local!.content.start!.rfc3339.substring(8, 10)),
        scope == AgendaEditScope.all
            ? ['06', '07', '08', '10']
            : ['05', '07', '08', '10'],
        reason: '$label平移后仍跳过原已删除的发生',
      );
      final moved = await service.get(entries.last.local!.itemId);
      expect(moved!.exdates.single.rfc3339, at(9).rfc3339);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await backend.dispose();
    }
  }
}
