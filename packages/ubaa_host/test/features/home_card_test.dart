import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_test_support/privacy.dart';
import 'package:ubaa_test_support/recovery.dart' as fixtures;
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets(
    'refreshes without opening Agenda and discards reads after logout',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final accounts = await fixtures.widgetAccounts(tester);
      final backend = _Backend();
      final snapshots = <HomeCardSnapshot>[];
      await tester.pumpWidget(
        UbaaAppHost(
          preferenceValues: acceptedPrivacyPreferences(),
          backend: backend,
          localAccountStore: accounts,
          initialDestination: UiDestination.campus,
          publishHomeCard: (snapshot) async => snapshots.add(snapshot),
        ),
      );
      await accounts.settle(tester);
      await tester.pumpAndSettle();

      UbaaMainShell shell() => tester.widget(find.byType(UbaaMainShell));
      expect(snapshots.last.todo.single.title, 'First');
      final query = backend.storage.cardQueries.last;
      expect(query.from, query.now.rfc3339.substring(0, 10));
      expect(
        query.to,
        agendaDate(DateTime.parse(query.from).add(const Duration(days: 28))),
      );
      expect(query.includeHidden, isFalse);

      backend.storage.title = 'Edited';
      shell().agenda.onChanged!();
      await tester.pump();
      expect(snapshots.last.todo.single.title, 'Edited');

      backend.storage.title = 'Timed';
      await tester.pump(const Duration(minutes: 1));
      expect(snapshots.last.todo.single.title, 'Timed');
      final unchanged = snapshots.length;
      await tester.pump(const Duration(minutes: 1));
      expect(snapshots, hasLength(unchanged));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      final reads = backend.storage.cardQueries.length;
      final writes = snapshots.length;
      backend.storage.title = 'Resumed';
      await tester.pump(const Duration(minutes: 2));
      expect(backend.storage.cardQueries, hasLength(reads));
      expect(snapshots, hasLength(writes));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await accounts.settle(tester);
      await tester.pumpAndSettle();
      expect(snapshots.last.todo.single.title, 'Resumed');

      final beforeBrowsing = snapshots.length;
      await tester.tap(find.byIcon(UiDestination.agenda.icon));
      await tester.pumpAndSettle();
      final pageQuery = backend.storage.queries.last;
      expect(pageQuery.includeHidden, isTrue);
      for (var week = 0; week < 12; week++) {
        await tester.tap(find.byTooltip('上一周'));
        await tester.pumpAndSettle();
      }
      expect(backend.storage.queries.last.to.compareTo(query.from), lessThan(0));
      expect(snapshots, hasLength(beforeBrowsing));

      final pending = Completer<void>();
      backend.storage.pending = pending;
      backend.storage.title = 'Late';
      shell().agenda.onChanged!();
      final beforeChange = backend.storage.cardQueries.length;
      await tester.pump();
      expect(backend.storage.cardQueries.length, greaterThan(beforeChange));
      final logout = shell().onLogout();
      await accounts.settle(tester);
      await tester.pumpAndSettle();
      await logout;
      expect(snapshots.last.signedIn, isFalse);
      expect(snapshots.last.todo, isEmpty);
      final afterLogout = snapshots.length;
      pending.complete();
      await tester.pump();
      expect(snapshots, hasLength(afterLogout));
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _Backend extends fixtures.FakeRecoveryBackend implements AgendaProvider {
  final storage = _Agenda();
  @override
  late final agenda = AgendaService(storage);
}

class _Agenda implements AgendaBackend {
  final queries = <AgendaQuery>[];
  List<AgendaQuery> get cardQueries =>
      queries.where((query) => !query.includeHidden).toList();
  String title = 'First';
  Completer<void>? pending;

  @override
  Future<void> openAccount(String accountId) async {}

  @override
  Future<void> deactivate() async {}

  @override
  Future<AgendaQueryResult> query(AgendaQuery query) async {
    queries.add(query);
    final value = title;
    if (!query.includeHidden) await pending?.future;
    return AgendaQueryResult(
      entries: [
        AgendaEntry(
          local: AgendaOccurrence(
            itemId: 'fixture-task',
            recurrenceId: 'undated',
            content: AgendaContent(
              kind: AgendaKind.task,
              title: value,
              allDay: false,
            ),
            overridden: false,
          ),
          timing: AgendaTiming(kind: AgendaTimingKind.undated),
          soon: false,
          completed: false,
          hidden: false,
        ),
      ],
      sources: [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
