import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_ui/src/features/agenda/view.dart';
import 'package:ubaa_test_support/recovery.dart' as startup;
import 'package:ubaa_test_support/navigation.dart';

void main() {
  for (final (currentWeek, destination) in [
    (true, UiDestination.home),
    (false, UiDestination.home),
    (true, UiDestination.agenda),
  ]) {
    testWidgets('自动导入整学期且进入日程不重复，入口=$destination，当前教学周=$currentWeek', (
      tester,
    ) async {
      final accounts = await startup.widgetAccounts(tester);
      final backend = _Backend()..currentWeek = currentWeek;
      await tester.pumpWidget(
        UbaaAppHost(
          backend: backend,
          localAccountStore: accounts,
          initialDestination: destination,
        ),
      );
      await accounts.settle(tester);
      await tester.pumpAndSettle();
      expect(backend.importTerms, ['selected']);
      backend.task.pending.complete(
        const ScheduleImportProgress(
          term: 'selected',
          completedWeeks: 4,
          totalWeeks: 4,
          finished: true,
          route: ConnectionMode.direct,
        ),
      );
      await accounts.settle(tester);
      await tester.pumpAndSettle();
      if (destination != UiDestination.agenda) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationRail),
            matching: find.byIcon(UiDestination.agenda.icon),
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(backend.importTerms, ['selected']);
      final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
      expect(
        shell.scheduleImports['selected']!.status,
        ScheduleImportStatus.saved,
      );
      var refreshed = false;
      final refreshing = tester
          .widget<AgendaView>(find.byType(AgendaView))
          .onRefreshSchool!()
          .then((_) => refreshed = true);
      await accounts.settle(tester);
      expect(backend.importTerms, ['selected', 'selected']);
      expect(refreshed, isFalse);
      backend.task.pending.complete(
        const ScheduleImportProgress(
          term: 'selected',
          completedWeeks: 4,
          totalWeeks: 4,
          finished: true,
          route: ConnectionMode.direct,
        ),
      );
      await accounts.settle(tester);
      await refreshing;
      expect(refreshed, isTrue);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('没有明确当前学期时不猜测整学期导入目标', (tester) async {
    final accounts = await startup.widgetAccounts(tester);
    final backend = _Backend()..selectedTerm = false;
    await tester.pumpWidget(
      UbaaAppHost(backend: backend, localAccountStore: accounts),
    );
    await accounts.settle(tester);
    await tester.pumpAndSettle();
    expect(backend.importTerms, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('生产宿主静默同步课表，失败后右上角重新刷新整学期', (tester) async {
    final accounts = await startup.widgetAccounts(tester);
    final backend = _Backend();
    await tester.pumpWidget(
      UbaaAppHost(backend: backend, localAccountStore: accounts),
    );
    await accounts.settle(tester);
    await tester.pumpAndSettle();
    UbaaMainShell shell() => tester.widget(find.byType(UbaaMainShell));
    expect(shell().onSaveScheduleSemester, isNotNull);
    await backend.task.started.future;
    expect(backend.term, 'selected');
    expect(
      shell().scheduleImports['selected']!.status,
      ScheduleImportStatus.running,
    );
    backend.task.pending.completeError(
      const BackendException(UbaaErrorCode.networkError),
    );
    await accounts.settle(tester);
    await tester.pumpAndSettle();
    expect(
      shell().scheduleImports['selected']!.status,
      ScheduleImportStatus.failed,
    );
    await openFeature(tester, FeatureId.schedule);
    expect(backend.importTerms, ['selected']);
    final reads = backend.weekReads;
    await tester.tap(find.byTooltip('刷新'));
    await tester.pump();
    await backend.task.started.future;
    backend.task.pending.complete(
      const ScheduleImportProgress(
        term: 'selected',
        completedWeeks: 1,
        totalWeeks: 1,
        finished: true,
        route: ConnectionMode.direct,
      ),
    );
    await accounts.settle(tester);
    await tester.pumpAndSettle();
    expect(backend.importTerms, ['selected', 'selected']);
    expect(backend.weekReads, reads);
    expect(
      shell().scheduleImports['selected']!.status,
      ScheduleImportStatus.saved,
    );
    expect(find.text('合成第3周'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

class _Backend extends startup.FakeRecoveryBackend
    implements
        ScheduleImportBackend,
        ProgressiveReadBackend,
        FeatureQueryBackend {
  final importTerms = <String>[];
  int weekReads = 0;
  bool currentWeek = true, selectedTerm = true;
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (query.view == FeatureQueryView.scheduleTerms) {
      return FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: [
          FeatureDetail(
            title: '合成本学期',
            presentation: TermPresentation(
              code: 'selected',
              selected: selectedTerm,
              index: 0,
            ),
          ),
        ],
      );
    }
    if (query.view == FeatureQueryView.scheduleWeeks) {
      return FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: [
          FeatureDetail(
            title: '合成第3周',
            presentation: WeekPresentation(
              requestTerm: 'selected',
              responseTerm: 'selected',
              number: 3,
              current: currentWeek,
              startDate: '2026-10-19',
              endDate: '2026-10-25',
            ),
          ),
        ],
      );
    }
    weekReads++;
    return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
  }

  var task = _Task();
  String? term;
  @override
  Future<ScheduleImportTask> beginScheduleImport(String term) async {
    this.term = term;
    importTerms.add(term);
    return task = _Task();
  }

  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async => null;
}

class _Task implements ScheduleImportTask {
  int calls = 0;
  bool cancelled = false;
  final pending = Completer<ScheduleImportProgress>();
  final started = Completer<void>();
  @override
  Future<ScheduleImportProgress> next() {
    calls++;
    if (!started.isCompleted) started.complete();
    return pending.future;
  }

  @override
  void cancel() => cancelled = true;
}
