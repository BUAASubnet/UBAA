import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/app/home.dart';

void main() {
  testWidgets('首页重建复用后仍响应来源替换与时间推进', (tester) async {
    var now = DateTime(2026, 10, 24);
    final snapshots = {
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.empty,
        ),
    };
    FeatureSnapshot source(String title) => FeatureSnapshot(
      feature: FeatureId.spoc,
      status: FeatureLoadStatus.success,
      details: [
        FeatureDetail(
          title: title,
          presentation: const SpocAssignmentPresentation(
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
    snapshots[FeatureId.spoc] = source('初始任务');
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
    rebuild(() => snapshots[FeatureId.spoc] = source('更新任务'));
    await tester.pump();
    expect(find.text('更新任务'), findsOneWidget);
    now = DateTime(2026, 10, 26);
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('当前没有待办'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
