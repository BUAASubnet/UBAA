import '../../support/home_harness.dart';
import '../../support/home_todos.dart';
import 'dart:async';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  testWidgets('待考试隐藏且考试中保留，类型与状态位于标题上方的元信息行', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeHarness(
            onProjectTodos: (r) =>
                homeTodoFixture(r, statuses: const {'当前考试': '考试中'}),
            user: null,
            visible: true,
            cacheEpoch: 0,
            homeClock: Clock.fixed(DateTime.parse('2026-10-25T11:00:00+08:00')),
            snapshots: {
              for (final feature in FeatureId.values)
                feature: FeatureSnapshot(
                  feature: feature,
                  status: FeatureLoadStatus.empty,
                ),
              FeatureId.exam: FeatureSnapshot(
                feature: FeatureId.exam,
                status: FeatureLoadStatus.success,
                details: [
                  for (final ongoing in [true, false])
                    FeatureDetail(
                      title: ongoing ? '当前考试' : '稍后考试',
                      presentation: ExamPresentation(
                        arranged: true,
                        date: '2026-10-25',
                        startTime: ongoing ? '10:00' : '14:00',
                        endTime: ongoing ? '12:00' : '16:00',
                        place: '合成考场',
                        seat: '8',
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
    for (final title in ['当前考试', '稍后考试']) {
      final card = find.widgetWithText(Card, title);
      final type = find.descendant(of: card, matching: find.text('考试'));
      final titleRect = tester.getRect(find.text(title));
      final typeRect = tester.getRect(type);
      expect(typeRect.bottom, lessThanOrEqualTo(titleRect.top));
    }
    expect(find.text('待考试'), findsNothing);
    final status = tester.getRect(find.text('考试中'));
    final type = tester.getRect(
      find.descendant(
        of: find.widgetWithText(Card, '当前考试'),
        matching: find.text('考试'),
      ),
    );
    expect(status.center.dy, closeTo(type.center.dy, 1));
    expect(status.left, greaterThan(type.right));
    expect(
      status.bottom,
      lessThanOrEqualTo(tester.getRect(find.text('当前考试')).top),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final feature in [FeatureId.spoc, FeatureId.exam]) {
    testWidgets('${feature.title}首页重建复用后仍响应来源替换与时间推进', (tester) async {
      var projectVisible = true;
      var now = DateTime.parse('2026-10-24T00:00:00+08:00');
      final snapshots = {
        for (final feature in FeatureId.values)
          feature: FeatureSnapshot(
            feature: feature,
            status: FeatureLoadStatus.empty,
          ),
      };
      FeatureSnapshot source(String title) => FeatureSnapshot(
        feature: feature,
        status: FeatureLoadStatus.success,
        details: [
          FeatureDetail(
            title: title,
            presentation: feature == FeatureId.exam
                ? const ExamPresentation(
                    arranged: true,
                    date: '2026-10-25',
                    startTime: '10:00',
                    endTime: '12:00',
                    place: '合成考场',
                    seat: '8',
                  )
                : const SpocAssignmentPresentation(
                    courseId: 'c',
                    courseName: '合成课程',
                    assignmentId: 'a',
                    dueTime: '2026-10-25 12:00:00',
                    status: AssignmentSubmissionStatus.unsubmitted,
                    statusText: '未提交',
                  ),
          ),
        ],
      );
      snapshots[feature] = source('初始任务');
      late StateSetter rebuild;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return MaterialApp(
              home: Scaffold(
                body: HomeHarness(
                  onProjectTodos: (r) =>
                      homeTodoFixture(r, visible: projectVisible),
                  user: null,
                  visible: true,
                  cacheEpoch: 0,
                  homeClock: Clock(() => now),
                  snapshots: snapshots,
                  onFeatureTap: (_) {},
                  onRetryFeature: (_) async {},
                  onRefresh: () async {},
                  onLoadSupplement: (_, _) async => FeatureResult.empty(),
                  onTodoTap: (_) {},
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('初始任务'), findsOneWidget);
      rebuild(() {});
      await tester.pump();
      expect(find.text('初始任务'), findsOneWidget);
      rebuild(() => snapshots[feature] = source('更新任务'));
      await tester.pumpAndSettle();
      expect(find.text('更新任务'), findsOneWidget);
      projectVisible = false;
      now = DateTime.parse('2026-10-26T00:00:00+08:00');
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('当前没有待办'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('首次投影前与被取代的投影不显示没有待办，取代后自动重算；切换路线清空', (tester) async {
    final gate = Completer<void>();
    var conflicts = 1;
    Future<HomeTodoProjection> flaky(HomeTodoRequest r) async {
      await gate.future;
      // 后端缓存代次变化（如共享账号重新绑定）会让在途投影以冲突结束。
      if (conflicts-- > 0) {
        throw const AgendaException(AgendaFailure.superseded);
      }
      return homeTodoFixture(r);
    }

    HomeTodoReader? reader = flaky;
    FeatureSnapshot exam() => const FeatureSnapshot(
      feature: FeatureId.exam,
      status: FeatureLoadStatus.success,
      details: [
        FeatureDetail(
          title: '缓存考试',
          presentation: ExamPresentation(
            arranged: true,
            date: '2026-10-25',
            startTime: '14:00',
            endTime: '16:00',
            place: '合成考场',
            seat: '8',
          ),
        ),
      ],
    );
    final snapshots = {
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.empty,
        ),
      FeatureId.exam: exam(),
    };
    late StateSetter rebuild;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return MaterialApp(
            home: Scaffold(
              body: HomeHarness(
                onProjectTodos: reader,
                user: null,
                visible: true,
                cacheEpoch: 0,
                homeClock: Clock.fixed(
                  DateTime.parse('2026-10-25T11:00:00+08:00'),
                ),
                snapshots: Map.of(snapshots),
                onFeatureTap: (_) {},
                onRetryFeature: (_) async {},
                onRefresh: () async {},
                onLoadSupplement: (_, _) async => FeatureResult.empty(),
                onTodoTap: (_) {},
              ),
            ),
          );
        },
      ),
    );
    await tester.pump();
    await tester.pump();
    // 缓存已在，只是投影还没算完：不能先告诉学生“没有待办”。
    expect(find.text('当前没有待办'), findsNothing);
    gate.complete();
    await tester.pump();
    await tester.pump();
    // 首次投影被取代：仍占位，不显示失败提示，稍后自动重算。
    expect(find.text('当前没有待办'), findsNothing);
    expect(find.text('完成状态暂时无法显示，请刷新'), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('缓存考试'), findsOneWidget);

    // 已显示待办后再次被取代：保留原有待办，不清空也不报错。
    conflicts = 1;
    rebuild(() => snapshots[FeatureId.exam] = exam());
    await tester.pump();
    await tester.pump();
    expect(find.text('缓存考试'), findsOneWidget);
    expect(find.text('完成状态暂时无法显示，请刷新'), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('缓存考试'), findsOneWidget);

    // 切换路线等身份过渡时宿主暂停投影：旧路线待办不再显示，改为占位。
    rebuild(() => reader = null);
    await tester.pump();
    expect(find.text('缓存考试'), findsNothing);
    expect(find.text('当前没有待办'), findsNothing);
    rebuild(() => reader = homeTodoFixture);
    await tester.pumpAndSettle();
    expect(find.text('缓存考试'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
