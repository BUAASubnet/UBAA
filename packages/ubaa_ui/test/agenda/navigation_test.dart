import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:clock/clock.dart';
import '../app/shell_parity_test.dart' show mount;
import '../support/home_todos.dart';
import 'flow_test.dart' show opened;
import 'support.dart';

void main() {
  testWidgets('首页查看全部进入日程待办，末尾学校事项从原详情单层返回', (tester) async {
    tester.view.physicalSize = const Size(500, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = MemoryAgenda();
    final service = await opened(backend);
    final now = AgendaTime(
      rfc3339: '2026-11-05T09:00:00+08:00',
      timezone: 'Asia/Shanghai',
    );
    for (var i = 0; i < 5; i++) {
      backend.school.add(
        SchoolAgendaItem(
          key: SchoolAgendaKey(source: 'spoc', upstreamId: 'a$i'),
          timing: AgendaTiming(kind: AgendaTimingKind.deadline, due: now),
          title: '任务$i',
          subtitle: '合成课程',
          statusLabel: '未提交',
          upstreamStatus: AgendaUpstreamStatus(
            feature: AgendaFeature.spoc,
            completed: false,
          ),
          navigation: AgendaNavigation(
            feature: AgendaFeature.spoc,
            assignmentId: 'a$i',
          ),
          homeTodo: true,
        ),
      );
    }
    await service.create(
      AgendaDraft(
        content: AgendaContent(
          kind: AgendaKind.event,
          title: '本地日程',
          allDay: false,
          start: now,
          end: AgendaTime(
            rfc3339: '2026-11-05T10:00:00+08:00',
            timezone: 'Asia/Shanghai',
          ),
        ),
        exdates: [],
      ),
      now,
    );
    final queries = <FeatureQuery>[];
    FeatureSnapshot? detail;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: StatefulBuilder(
          builder: (context, redraw) => UbaaMainShell(
            user: const UserSummary(username: 'synthetic'),
            cacheAccountId: 'synthetic',
            agenda: AgendaAccess(service: service, term: 'synthetic'),
            homeClock: Clock.fixed(DateTime(2026, 11, 5, 9)),
            onProjectHomeTodos: homeTodoFixture,
            snapshots: {
              for (final id in FeatureId.values)
                id: FeatureSnapshot(
                  feature: id,
                  status: FeatureLoadStatus.empty,
                ),
              FeatureId.spoc: FeatureSnapshot(
                feature: FeatureId.spoc,
                status: FeatureLoadStatus.success,
                details: [
                  for (var i = 0; i < 5; i++)
                    FeatureDetail(
                      title: '任务$i',
                      presentation: SpocAssignmentPresentation(
                        courseId: 'c',
                        courseName: '合成课程',
                        assignmentId: 'a$i',
                        dueTime: '2026-11-05 20:00:00',
                        status: AssignmentSubmissionStatus.unsubmitted,
                        statusText: '未提交',
                      ),
                    ),
                ],
              ),
              if (detail != null) FeatureId.spoc: detail!,
            },
            routePolicy: RoutePolicy.direct,
            telemetryEnabled: false,
            onFeatureQuery: (_, query) async {
              queries.add(query);
              redraw(
                () => detail = FeatureSnapshot(
                  feature: FeatureId.spoc,
                  status: FeatureLoadStatus.success,
                  readContext: FeatureReadContext(
                    query: query,
                    requestRevision: queries.length + 1,
                  ),
                  details: const [FeatureDetail(title: '合成作业详情')],
                ),
              );
            },
            onRefresh: () async => fail('本机导航不刷新学校'),
            onRetryFeature: (_) async {},
            onLogout: () async {},
            onLogoutAndClearAccount: () async {},
            onRoutePolicyChanged: (_) {},
            onTelemetryChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final all = find.byKey(const ValueKey('home-todos-toggle'));
    await tester.ensureVisible(all);
    await tester.tap(all);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '日程'), findsOneWidget);
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, '待办')).selected,
      isTrue,
    );
    expect(find.text('本地日程'), findsNothing);
    await tester.tap(find.widgetWithText(FilterChip, '待办'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, '待办')).selected,
      isFalse,
    );
    await tester.tap(find.widgetWithText(NavigationDestination, '首页'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(all);
    await tester.tap(all);
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, '待办')).selected,
      isTrue,
      reason: '每次首页查看全部都应重新启用待办筛选',
    );
    await tester.ensureVisible(find.text('任务4'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('任务4'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开原功能'));
    await tester.pumpAndSettle();
    expect(queries.last.assignmentId, 'a4');
    expect(find.byTooltip('返回'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '日程'), findsOneWidget);
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, '待办')).selected,
      isTrue,
    );
  });
  testWidgets('日程为中间入口，学习保留课表与成绩入口', (tester) async {
    await mount(tester);
    await tester.tap(find.widgetWithText(NavigationDestination, '日程'));
    await tester.pumpAndSettle();
    expect(find.text('新建事项'), findsOneWidget);
    await tester.tap(find.widgetWithText(NavigationDestination, '学习'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Card, FeatureId.schedule.title), findsOneWidget);
    await tester.ensureVisible(
      find.widgetWithText(Card, FeatureId.grades.title),
    );
    expect(find.widgetWithText(Card, FeatureId.grades.title), findsOneWidget);
  });
}
