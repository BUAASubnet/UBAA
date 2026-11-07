import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/agenda/cache_status.dart';
import 'package:ubaa_ui/src/features/agenda/view.dart';
import '../flow_test.dart' show opened;
import '../support.dart';
import '../data_sheet_support.dart';

void main() {
  testWidgets('学校刷新期间面板保持打开，完成后显示新时间，导入课表调用专用操作', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = MemoryAgenda();
    AgendaSource source(DateTime updated) {
      final epoch = updated.millisecondsSinceEpoch ~/ 1000;
      return AgendaSource(
        feature: AgendaFeature.exam,
        observations: [
          AgendaObservation(
            scope: AgendaCacheScope(
              route: ConnectionMode.direct,
              kind: AgendaCacheKind.exams,
            ),
            fetchedAt: epoch,
            lastVerifiedAt: epoch,
            lastAttemptAt: epoch,
            lastAttemptSucceeded: true,
            completeness: AgendaCompleteness.complete,
          ),
        ],
        missingScopes: [],
        unprojectableCount: 0,
      );
    }

    backend.sources.add(source(DateTime.utc(2026, 11, 5)));
    final service = await opened(backend);
    final refreshDone = Completer<void>();
    var refreshed = 0, imported = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaView(
            service: service,
            scopeKey: 1,
            route: ConnectionMode.direct,
            term: 'synthetic',
            now: DateTime.utc(2026, 11, 5, 9),
            onOpenSchool: (_) => fail('已有专用操作时不应回退到学校页面'),
            onRefreshSchool: () async {
              refreshed++;
              await refreshDone.future;
              backend.sources
                ..clear()
                ..add(source(DateTime.utc(2026, 11, 5, 1)));
              await backend.create(
                AgendaDraft(
                  content: AgendaContent(
                    kind: AgendaKind.task,
                    title: '刷新后读取的事项',
                    allDay: false,
                  ),
                  exdates: [],
                ),
                AgendaTime(
                  rfc3339: '2026-11-05T09:00:00+08:00',
                  timezone: 'Asia/Shanghai',
                ),
              );
            },
            onImportSchedule: () => imported++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openAgendaDataSheet(tester);
    expect(find.text('数据与同步').hitTestable(), findsOneWidget);
    final sheetRoute = ModalRoute.of(tester.element(find.text('数据与同步')))!;
    final exam = find.byKey(const ValueKey('agenda-cache-exam'));
    expect(
      find.descendant(of: exam, matching: find.text('1 小时前更新')),
      findsOneWidget,
    );
    final refresh = find.widgetWithText(FilledButton, '刷新学校日程');
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    await tester.pump();
    await tester.pump();
    expect(refreshed, 1);
    final refreshing = find.widgetWithText(FilledButton, '正在刷新');
    expect(tester.widget<FilledButton>(refreshing).onPressed, isNull);
    expect(
      find.descendant(
        of: refreshing,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(sheetRoute.isCurrent, isTrue);
    expect(ModalRoute.of(tester.element(find.text('数据与同步'))), same(sheetRoute));

    refreshDone.complete();
    await tester.pumpAndSettle();
    expect(sheetRoute.isCurrent, isTrue);
    expect(ModalRoute.of(tester.element(find.text('数据与同步'))), same(sheetRoute));
    expect(
      find.descendant(of: exam, matching: find.text('刚刚更新')),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(refresh).onPressed, isNotNull);
    await closeAgendaDataSheet(tester);
    expect(find.text('刷新后读取的事项').hitTestable(), findsOneWidget);
    expect(
      ModalRoute.of(tester.element(find.byType(AgendaView)))!.isCurrent,
      isTrue,
    );
    await openAgendaDataSheet(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, '导入整学期课表'));
    await tester.pumpAndSettle();
    expect(imported, 1);
    expect(refreshed, 1);
    expect(
      ModalRoute.of(tester.element(find.byType(AgendaView)))!.isCurrent,
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await service.dispose();
  });

  testWidgets('仅缺其他教学周的课表时提示导入整学期课表', (tester) async {
    final backend = MemoryAgenda();
    final epoch = DateTime.utc(2026, 11, 5, 1).millisecondsSinceEpoch ~/ 1000;
    backend.sources.add(
      AgendaSource(
        feature: AgendaFeature.schedule,
        observations: [
          AgendaObservation(
            scope: AgendaCacheScope(
              route: ConnectionMode.direct,
              kind: AgendaCacheKind.scheduleWeek,
              term: 'synthetic',
              week: 9,
            ),
            fetchedAt: epoch,
            lastVerifiedAt: epoch,
            lastAttemptAt: epoch,
            lastAttemptSucceeded: true,
            completeness: AgendaCompleteness.complete,
          ),
        ],
        missingScopes: [
          AgendaCacheScope(
            route: ConnectionMode.direct,
            kind: AgendaCacheKind.scheduleWeek,
            term: 'synthetic',
            week: 10,
          ),
        ],
        semesterImported: false,
        unprojectableCount: 0,
      ),
    );
    final service = await opened(backend);
    var imported = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaView(
            service: service,
            scopeKey: 1,
            route: ConnectionMode.direct,
            term: 'synthetic',
            now: DateTime(2026, 11, 5, 9),
            onOpenSchool: (_) => fail('已有导入操作时不应回退到学校页面'),
            onImportSchedule: () => imported++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 正常状态不显示数据提示条，入口在更多菜单。
    expect(find.byKey(const ValueKey('agenda-data-notice')), findsNothing);
    await openAgendaDataSheet(tester);
    expect(find.text('只显示看过的几周课表，导入整学期课表可查看全部周。'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('agenda-cache-schedule')),
        matching: find.text('刚刚更新'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, '导入整学期课表'));
    await tester.pumpAndSettle();
    expect(imported, 1);
    expect(
      ModalRoute.of(tester.element(find.byType(AgendaView)))!.isCurrent,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    await service.dispose();
  });

  testWidgets('学校来源分别展示最近更新时间和更新失败', (tester) async {
    final backend = MemoryAgenda();
    int epoch(int day, int hour) =>
        DateTime.utc(2026, 11, day, hour).millisecondsSinceEpoch ~/ 1000;
    backend.sources.addAll([
      AgendaSource(
        feature: AgendaFeature.schedule,
        observations: [
          AgendaObservation(
            scope: AgendaCacheScope(
              route: ConnectionMode.direct,
              kind: AgendaCacheKind.scheduleWeek,
              week: 9,
            ),
            fetchedAt: epoch(5, 1),
            lastVerifiedAt: epoch(5, 2),
            lastAttemptAt: epoch(5, 2),
            lastAttemptSucceeded: true,
            completeness: AgendaCompleteness.complete,
          ),
        ],
        missingScopes: [],
        semesterImported: true,
        unprojectableCount: 0,
      ),
      AgendaSource(
        feature: AgendaFeature.exam,
        observations: [
          AgendaObservation(
            scope: AgendaCacheScope(
              route: ConnectionMode.direct,
              kind: AgendaCacheKind.exams,
            ),
            fetchedAt: epoch(1, 1),
            lastVerifiedAt: epoch(2, 1),
            lastAttemptAt: epoch(5, 3),
            lastAttemptSucceeded: false,
            completeness: AgendaCompleteness.partial,
          ),
        ],
        missingScopes: [],
        unprojectableCount: 0,
      ),
    ]);
    final service = await opened(backend);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaView(
            service: service,
            scopeKey: 1,
            route: ConnectionMode.direct,
            term: 'synthetic',
            now: DateTime(2026, 11, 5, 11, 7),
            onOpenSchool: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openAgendaDataSheet(tester);
    expect(find.text('学校数据'), findsOneWidget);
    expect(find.text('1 小时前更新 · 考试更新失败'), findsOneWidget);
    final exam = find.byKey(const ValueKey('agenda-cache-exam'));
    final schedule = find.byKey(const ValueKey('agenda-cache-schedule'));
    expect(
      find.descendant(of: exam, matching: find.text('考试')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: exam, matching: find.text('更新失败')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: schedule, matching: find.text('课程')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: schedule, matching: find.text('1 小时前更新')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await service.dispose();
  });

  for (final route in ConnectionMode.values) {
    testWidgets('${route.name} 来源不完整时概要使用最近更新时间，不显示路线与查询范围', (tester) async {
      final now = DateTime.utc(2026, 11, 5, 2, 7);
      final latest = now.subtract(const Duration(minutes: 7));
      int epoch(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AgendaCacheStatus(
                now: AgendaTime(
                  rfc3339: now.toIso8601String(),
                  timezone: 'Asia/Shanghai',
                ),
                sources: [
                  AgendaSource(
                    feature: AgendaFeature.schedule,
                    observations: [
                      for (final week in [8, 9])
                        AgendaObservation(
                          scope: AgendaCacheScope(
                            route: route,
                            kind: AgendaCacheKind.scheduleWeek,
                            term: 'synthetic',
                            week: week,
                          ),
                          fetchedAt: epoch(
                            latest.subtract(Duration(hours: 10 - week)),
                          ),
                          lastVerifiedAt: epoch(
                            latest.subtract(Duration(hours: 9 - week)),
                          ),
                          lastAttemptAt: epoch(
                            latest.subtract(Duration(hours: 9 - week)),
                          ),
                          lastAttemptSucceeded: true,
                          completeness: week == 9
                              ? AgendaCompleteness.partial
                              : AgendaCompleteness.complete,
                        ),
                    ],
                    missingScopes: [],
                    unprojectableCount: 0,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('学校数据'), findsOneWidget);
      // 概要与课程行各显示一次。
      expect(find.text('7 分钟前更新'), findsNWidgets(2));
      final schedule = find.byKey(const ValueKey('agenda-cache-schedule'));
      expect(
        find.descendant(of: schedule, matching: find.text('7 分钟前更新')),
        findsOneWidget,
      );
    });
  }
}
