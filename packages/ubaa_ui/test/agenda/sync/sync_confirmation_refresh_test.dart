import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/agenda/sync_status.dart';

import 'sync_lifecycle_test.dart' show Backend, app, size;
import '../data_sheet_support.dart';

class RefreshBackend extends Backend {
  RefreshBackend() {
    enabled = false;
    creationFailure = AgendaFailure.superseded;
  }

  int confirmations = 0;
  final refresh = Completer<AgendaSyncReport>();

  @override
  AgendaSyncJob prepareSync(AgendaSyncAction action, AgendaTime now) {
    if (action == AgendaSyncAction.createConfirmed) confirmations++;
    return super.prepareSync(action, now);
  }

  @override
  Future<AgendaSyncReport> sync(AgendaSyncAction action, AgendaTime now) async {
    if (action == AgendaSyncAction.pull) {
      calls.add((account, action));
      final report = await refresh.future;
      creationFailure = null;
      return report;
    }
    return super.sync(action, now);
  }
}

class RouteRefreshBackend extends RefreshBackend {
  bool direct = false;

  @override
  Future<AgendaSyncReport> sync(AgendaSyncAction action, AgendaTime now) async {
    if (action == AgendaSyncAction.pull && !direct) {
      calls.add((account, action));
      return const AgendaSyncReport(
        status: AgendaSyncStatus.unverified,
        pendingCount: 0,
        changedCount: 0,
      );
    }
    return super.sync(action, now);
  }
}

void main() {
  testWidgets('首次启用刷新遇到未验证路线后，恢复路线仍可只读刷新再确认', (tester) async {
    size(tester);
    final backend = RouteRefreshBackend();
    final service = AgendaService(backend);
    await service.openAccount('fixture-a');
    await tester.pumpWidget(app(service, route: ConnectionMode.webvpn));
    await tester.pumpAndSettle();
    await openAgendaDataSheet(tester);
    await tester.tap(find.widgetWithText(FilledButton, '启用云端同步'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '重新拉取'));
    await tester.pumpAndSettle();
    expect(service.syncState.report?.status, AgendaSyncStatus.unverified);
    expect(service.syncEnabled, isFalse);
    expect(backend.confirmations, 1);
    expect(find.byType(AlertDialog), findsNothing);

    backend.direct = true;
    await tester.pumpWidget(app(service, route: ConnectionMode.direct));
    await tester.pumpAndSettle();
    expect(backend.calls.map((call) => call.$2), [AgendaSyncAction.pull]);
    await openAgendaDataSheet(tester);
    final refresh = find.widgetWithText(FilledButton, '重新拉取');
    expect(refresh, findsOneWidget);
    expect(tester.widget<ButtonStyleButton>(refresh).onPressed, isNotNull);
    await tester.tap(refresh);
    await tester.pump();
    await tester.pump();
    expect(backend.confirmations, 1);
    expect(backend.calls.map((call) => call.$2), [
      AgendaSyncAction.pull,
      AgendaSyncAction.pull,
    ]);
    expectRefreshRunning(tester, actionLabel: '重新拉取');
    expect(find.byType(AlertDialog), findsNothing);
    backend.refresh.complete(
      const AgendaSyncReport(
        status: AgendaSyncStatus.locationUnknown,
        pendingCount: 0,
        changedCount: 0,
      ),
    );
    await tester.pumpAndSettle();
    expect(service.syncEnabled, isFalse);
    await tester.tap(find.widgetWithText(FilledButton, '启用云端同步'));
    await tester.pumpAndSettle();
    expect(backend.confirmations, 2);
    await tester.tap(find.widgetWithText(FilledButton, '确认启用'));
    await tester.pumpAndSettle();
    expect(service.syncEnabled, isTrue);
    expect(backend.calls.map((call) => call.$2), [
      AgendaSyncAction.pull,
      AgendaSyncAction.pull,
      AgendaSyncAction.createConfirmed,
    ]);
    await tester.pumpWidget(const SizedBox());
    await service.dispose();
  });

  testWidgets('首次启用确认过期后先只读刷新，再重新捕获确认并启用', (tester) async {
    size(tester);
    final backend = RefreshBackend();
    final service = AgendaService(backend);
    await service.openAccount('fixture-a');
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    expect(backend.calls, isEmpty);

    await openAgendaDataSheet(tester);
    await tester.tap(find.widgetWithText(FilledButton, '启用云端同步'));
    await tester.pumpAndSettle();
    expect(backend.confirmations, 1);
    expect(backend.calls, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);

    final refresh = find.widgetWithText(FilledButton, '重新拉取');
    expect(refresh, findsOneWidget);
    await tester.tap(refresh);
    await tester.pump();
    await tester.pump();
    expect(backend.calls.map((call) => call.$2), [AgendaSyncAction.pull]);
    expect(service.syncEnabled, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
    expect(backend.confirmations, 1);
    expectRefreshRunning(tester, actionLabel: '启用云端同步');

    backend.refresh.complete(
      const AgendaSyncReport(
        status: AgendaSyncStatus.locationUnknown,
        pendingCount: 0,
        changedCount: 0,
      ),
    );
    await tester.pumpAndSettle();
    expect(service.syncEnabled, isFalse);
    await tester.tap(find.widgetWithText(FilledButton, '启用云端同步'));
    await tester.pumpAndSettle();
    expect(backend.confirmations, 2);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(backend.calls.map((call) => call.$2), [AgendaSyncAction.pull]);

    await tester.tap(find.widgetWithText(FilledButton, '确认启用'));
    await tester.pumpAndSettle();
    expect(service.syncEnabled, isTrue);
    expect(backend.calls.map((call) => call.$2), [
      AgendaSyncAction.pull,
      AgendaSyncAction.createConfirmed,
    ]);
    await tester.pumpWidget(const SizedBox());
    await service.dispose();
  });
}

void expectRefreshRunning(WidgetTester tester, {required String actionLabel}) {
  final card = find.byType(AgendaSyncStatusCard);
  Finder within(Finder matching) =>
      find.descendant(of: card, matching: matching);
  expect(within(find.text('正在同步日程')).hitTestable(), findsOneWidget);
  expect(within(find.text('正在与个人云盘交换自建事项')), findsOneWidget);
  final progress = within(find.byType(CircularProgressIndicator));
  expect(progress.hitTestable(), findsOneWidget);
  expect(tester.widget<CircularProgressIndicator>(progress).value, isNull);
  expect(
    tester
        .widget<FilledButton>(
          within(find.widgetWithText(FilledButton, actionLabel)),
        )
        .onPressed,
    isNull,
  );
}
