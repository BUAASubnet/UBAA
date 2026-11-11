import '../../support/home_harness.dart';
import '../../support/home_todos.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/app/home.dart';
import '../../app/shell_parity_test.dart' as shell;

void main() {
  testWidgets('远期同课程待办合并预览，近期和不同来源分别保留且可查看全部', (tester) async {
    final now = DateTime(2026, 11, 11, 8);
    final tasks = [
      for (final (id, feature, days, course) in [
        ('近期', FeatureId.spoc, 1, '课程甲'),
        ('远期首项', FeatureId.spoc, 9, '课程甲'),
        ('远期后项', FeatureId.spoc, 10, '课程甲'),
        ('其他课程', FeatureId.spoc, 11, '课程乙'),
        ('其他来源', FeatureId.judge, 12, '课程甲'),
      ])
        HomeTodo(
          id: id,
          navigation: FeatureReadNavigation(
            feature: feature,
            query: FeatureQuery(assignmentId: id),
          ),
          feature: feature,
          title: id,
          subtitle: course,
          statusLabel: '待完成',
          timeLabel: '截止时间',
          sortTime: now.add(Duration(days: days)),
          deadline: now.add(Duration(days: days)),
        ),
    ];
    var all = false;
    HomeTodo? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeView(
            state: HomeState(
              now: now,
              sources: const {},
              todos: tasks,
              projected: true,
              schedule: HomeScheduleState(
                date: '2026-11-11',
                snapshot: FeatureSnapshot(
                  feature: FeatureId.schedule,
                  status: FeatureLoadStatus.empty,
                ),
              ),
            ),
            homeClock: Clock.fixed(now),
            visible: true,
            onFeatureTap: (_) {},
            onRetryFeature: (_) async {},
            onRefresh: () async {},
            onTodoTap: (item) => opened = item,
            onViewAllTodos: () => all = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('远期后项'), findsNothing);
    expect(find.text('另有 1 项'), findsOneWidget);
    for (final title in ['近期', '远期首项', '其他课程', '其他来源']) {
      expect(find.text(title), findsOneWidget);
    }
    await tester.ensureVisible(find.text('远期首项'));
    await tester.tap(find.text('远期首项'));
    expect(opened, same(tasks[1]));
    final button = find.byKey(const ValueKey('home-todos-toggle'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    expect(all, isTrue);
    expect(tasks.map((item) => item.id), [
      '近期',
      '远期首项',
      '远期后项',
      '其他课程',
      '其他来源',
    ]);
  });

  for (final width in [1100.0, 390.0]) {
    testWidgets('首页待办预览随页面滚动，查看全部进入日程且保留预览，宽度 $width', (tester) async {
      tester.view.physicalSize = Size(width, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      HomeTodo? opened;
      var refreshes = 0;
      var viewedAll = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeHarness(
              onProjectTodos: homeTodoFixture,
              user: null,
              visible: true,
              cacheEpoch: 0,
              homeClock: Clock.fixed(DateTime(2026, 10, 24)),
              snapshots: {
                for (final f in FeatureId.values)
                  f: FeatureSnapshot(
                    feature: f,
                    status: FeatureLoadStatus.empty,
                  ),
                FeatureId.spoc: FeatureSnapshot(
                  feature: FeatureId.spoc,
                  status: FeatureLoadStatus.success,
                  details: [
                    for (var i = 0; i < 12; i++)
                      FeatureDetail(
                        title: '任务$i',
                        presentation: SpocAssignmentPresentation(
                          courseId: 'c',
                          courseName: '合成课程',
                          assignmentId: 'a$i',
                          dueTime:
                              '2026-10-25 12:${i.toString().padLeft(2, '0')}:00',
                          status: AssignmentSubmissionStatus.unsubmitted,
                          statusText: '未提交',
                        ),
                      ),
                  ],
                ),
              },
              onFeatureTap: (_) {},
              onRetryFeature: (_) async {},
              onRefresh: () async {
                refreshes++;
              },
              onTodoTap: (item) => opened = item,
              onViewAllTodos: () => viewedAll = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final outer = find
          .descendant(
            of: find.byKey(const ValueKey('home-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(outer).position;
      if (find.text('任务0').hitTestable().evaluate().isEmpty) {
        await tester.ensureVisible(find.text('任务0'));
      }
      final before = position.pixels;
      await tester.drag(find.text('任务0'), const Offset(0, -220));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(before), reason: '待办手势应滚动整个首页');
      final toggle = find.byKey(const ValueKey('home-todos-toggle'));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      // 宽屏课表与待办并排，待办单列预览六项；窄屏上下排列预览四项。
      final preview = width >= 840 ? 6 : 4;
      expect(find.text('任务$preview'), findsNothing, reason: '首页先展示时间最临近的几项');
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(viewedAll, isTrue);
      expect(find.text('任务$preview'), findsNothing);
      await tester.ensureVisible(find.text('任务3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('任务3'));
      expect(opened?.title, '任务3');
      position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.drag(find.text('任务0'), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(refreshes, 1, reason: '待办区域下拉同样触发首页刷新');
      expect(tester.takeException(), isNull);
    });
  }

  for (final config in [(1100.0, 1.0), (390.0, 2.0)]) {
    testWidgets('待办单列排列，长描述保留全文 $config', (tester) async {
      tester.view.physicalSize = Size(config.$1, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final descriptions = ['短课程', '合成的较长课程名称与地点说明' * 5, '课程三', '课程四'];
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(config.$2)),
            child: child!,
          ),
          home: Scaffold(
            body: HomeHarness(
              onProjectTodos: homeTodoFixture,
              user: null,
              visible: true,
              cacheEpoch: 0,
              homeClock: Clock.fixed(DateTime(2026, 10, 24)),
              snapshots: {
                for (final f in FeatureId.values)
                  f: FeatureSnapshot(
                    feature: f,
                    status: FeatureLoadStatus.empty,
                  ),
                FeatureId.spoc: FeatureSnapshot(
                  feature: FeatureId.spoc,
                  status: FeatureLoadStatus.success,
                  details: [
                    for (var i = 0; i < 4; i++)
                      FeatureDetail(
                        title: '对齐任务$i',
                        presentation: SpocAssignmentPresentation(
                          courseId: 'c$i',
                          courseName: descriptions[i],
                          assignmentId: 'a$i',
                          dueTime: '2026-10-25 12:0$i:00',
                          status: AssignmentSubmissionStatus.unsubmitted,
                          statusText: '未提交',
                        ),
                      ),
                  ],
                ),
              },
              onFeatureTap: (_) {},
              onRetryFeature: (_) async {},
              onRefresh: () async {},
              onTodoTap: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final cards = [
        for (var i = 0; i < 4; i++) find.widgetWithText(Card, '对齐任务$i'),
      ];
      final rects = cards.map(tester.getRect).toList();
      for (var i = 1; i < rects.length; i++) {
        expect(rects[i].top, greaterThanOrEqualTo(rects[i - 1].bottom));
      }
      final description = find.text(descriptions[1]);
      expect(tester.getRect(description).bottom, lessThan(rects[1].bottom));
      expect(tester.widget<Text>(description).maxLines, isNull);
      await tester.ensureVisible(find.text('对齐任务3'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('常用功能按最近访问排序，再次访问置顶且不重复', (tester) async {
    await shell.mount(tester);
    Future<void> visit(FeatureId id) async {
      await tester.tap(find.text('学习'));
      await tester.pumpAndSettle();
      final card = find.widgetWithText(Card, id.title);
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();
      await tester.tap(find.text('首页').last);
      await tester.pumpAndSettle();
    }

    await visit(FeatureId.exam);
    await visit(FeatureId.grades);
    await visit(FeatureId.exam);
    final entries = tester
        .widgetList<InkWell>(
          find.descendant(
            of: find.byType(HomeView),
            matching: find.byType(InkWell),
          ),
        )
        .where((entry) => entry.key.toString().contains('recent-'))
        .toList();
    expect(entries.map((entry) => entry.key), [
      const ValueKey('recent-exam'),
      const ValueKey('recent-grades'),
      const ValueKey('recent-schedule'),
      const ValueKey('recent-bykc'),
    ]);
    await tester.tap(find.byKey(const ValueKey('recent-grades')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, FeatureId.grades.title), findsOneWidget);
  });
}
