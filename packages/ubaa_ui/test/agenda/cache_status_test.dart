import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'flow_test.dart' show app, opened;
import 'support.dart';

void main() {
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
