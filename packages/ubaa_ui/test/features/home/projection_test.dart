import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/app/home.dart';

void main() {
  testWidgets('待考试隐藏且考试中保留，类型标题状态同行排列', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeView(
            user: null,
            visible: true,
            cacheEpoch: 0,
            homeClock: Clock.fixed(DateTime(2026, 10, 25, 11)),
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
      expect(typeRect.center.dy, closeTo(titleRect.center.dy, 1));
      expect(typeRect.right, lessThan(titleRect.left));
    }
    expect(find.text('待考试'), findsNothing);
    final status = tester.getRect(find.text('考试中'));
    final title = tester.getRect(find.text('当前考试'));
    expect(status.center.dy, closeTo(title.center.dy, 1));
    expect(status.left, greaterThan(title.right));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final feature in [FeatureId.spoc, FeatureId.exam]) {
    testWidgets('${feature.title}首页重建复用后仍响应来源替换与时间推进', (tester) async {
      var now = DateTime(2026, 10, 24);
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
                body: HomeView(
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
      await tester.pump();
      expect(find.text('更新任务'), findsOneWidget);
      now = DateTime(2026, 10, 26);
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('当前没有待办'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
