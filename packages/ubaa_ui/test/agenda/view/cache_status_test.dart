import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/agenda/cache_status.dart';
import 'package:ubaa_ui/src/features/agenda/view.dart';
import '../flow_test.dart' show opened;
import '../support.dart';
import '../data_sheet_support.dart';

void main() {
  testWidgets('状态提示打开数据面板，刷新学校与导入课表分别调用对应操作', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = MemoryAgenda();
    final service = await opened(backend);
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
    await tester.tap(find.widgetWithText(FilledButton, '刷新学校日程'));
    await tester.pumpAndSettle();
    expect(refreshed, 1);
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

  testWidgets('学校来源分别展示保存与核验时间、更新失败和部分结果', (tester) async {
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
    expect(find.text('学校数据（直连）'), findsOneWidget);
    expect(find.text('1 小时前更新 · 考试待补全'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('agenda-cache-status')));
    await tester.pumpAndSettle();
    expect(find.text('考试 · 核验已超过5分钟 · 上次更新失败 · 部分结果'), findsOneWidget);
    expect(find.textContaining('保存 2026-11-01 09:00'), findsOneWidget);
    expect(find.textContaining('核验 2026-11-02 09:00'), findsOneWidget);
    expect(find.textContaining('保存 2026-11-05 09:00'), findsOneWidget);
    expect(find.textContaining('核验 2026-11-05 10:00'), findsOneWidget);
    final exam = find.byKey(const ValueKey('agenda-cache-exam'));
    await tester.ensureVisible(exam);
    await tester.tap(
      find.descendant(of: exam, matching: find.textContaining('考试')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('尝试 2026-11-05 11:00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await service.dispose();
  });

  for (final route in ConnectionMode.values) {
    testWidgets('${route.name} 来源不完整时概要使用最近核验时间，展开保留查询范围', (tester) async {
      final now = DateTime.utc(2026, 11, 5, 2, 7);
      final latest = now.subtract(const Duration(minutes: 7));
      int epoch(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AgendaCacheStatus(
                route: route,
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
      expect(
        find.text('学校数据（${route == ConnectionMode.direct ? '直连' : 'WebVPN'}）'),
        findsOneWidget,
      );
      expect(find.text('7 分钟前更新 · 课程待补全'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('agenda-cache-status')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('保存 2026-11-05 08:00 — 2026-11-05 09:00'),
        findsOneWidget,
      );
      expect(
        find.textContaining('核验 2026-11-05 09:00 — 2026-11-05 10:00'),
        findsOneWidget,
      );
      final schedule = find.byKey(const ValueKey('agenda-cache-schedule'));
      await tester.tap(
        find.descendant(of: schedule, matching: find.textContaining('课程')),
      );
      await tester.pumpAndSettle();
      expect(find.text('synthetic · 第8教学周'), findsOneWidget);
      expect(find.text('synthetic · 第9教学周'), findsOneWidget);
      expect(
        find.textContaining('尝试 2026-11-05 09:00 · 核验已超过5分钟'),
        findsOneWidget,
      );
      expect(
        find.textContaining('尝试 2026-11-05 10:00 · 核验已超过5分钟 · 部分结果'),
        findsOneWidget,
      );
    });
  }
}
