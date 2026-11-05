import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/agenda/view.dart';
import '../flow_test.dart' show app, opened;
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
    await tester.pumpWidget(app(await opened(backend)));
    await tester.pumpAndSettle();
    await openAgendaDataSheet(tester);
    expect(find.textContaining('上次更新失败'), findsOneWidget);
    expect(find.textContaining('部分结果'), findsOneWidget);
    expect(find.textContaining('核验已超过5分钟'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('agenda-cache-status')));
    await tester.pumpAndSettle();
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
  });
}
