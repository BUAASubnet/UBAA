import '../../support/home_harness.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/theme.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('首页来源提示在手机${dark ? '暗色' : '亮色'}布局集中重试失败来源', (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final retries = <FeatureId>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? UbaaTheme.dark() : UbaaTheme.light(),
          home: Scaffold(
            body: HomeHarness(
              user: null,
              visible: true,
              cacheEpoch: 0,
              homeClock: Clock.fixed(DateTime.utc(2026, 11, 5, 11)),
              snapshots: {
                for (final feature in FeatureId.values)
                  feature: FeatureSnapshot(
                    feature: feature,
                    status: [FeatureId.spoc, FeatureId.judge].contains(feature)
                        ? FeatureLoadStatus.failure
                        : FeatureLoadStatus.empty,
                  ),
              },
              onFeatureTap: (_) {},
              onTodoTap: (_) {},
              onRetryFeature: (feature) async => retries.add(feature),
              onRefresh: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final warning = find.byKey(const ValueKey('home-source-warning'));
      await tester.ensureVisible(warning);
      final retry = find.descendant(
        of: warning,
        matching: find.widgetWithText(TextButton, '重试'),
      );
      final bounds = tester.getRect(warning);
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(402));
      expect(bounds.height, lessThanOrEqualTo(64));
      expect(tester.getSize(retry).height, greaterThanOrEqualTo(44));
      await tester.tap(retry);
      await tester.pump();
      expect(retries, [FeatureId.spoc, FeatureId.judge]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('重试完成后提示条消失，已加载待办仍可打开', (tester) async {
    var failed = true;
    HomeTodo? opened;
    final todo = HomeTodo(
      id: 'exam:synthetic',
      feature: FeatureId.exam,
      title: '合成课程考试',
      subtitle: '合成考场',
      statusLabel: '即将考试',
      timeLabel: '19:00–20:35',
      sortTime: DateTime.utc(2026, 11, 5, 11),
      navigation: const FeatureReadNavigation(
        feature: FeatureId.exam,
        query: FeatureQuery(view: FeatureQueryView.examArranged),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: HomeHarness(
              user: null,
              visible: true,
              cacheEpoch: 0,
              homeClock: Clock.fixed(DateTime.utc(2026, 11, 5, 11)),
              snapshots: {
                for (final feature in FeatureId.values)
                  feature: FeatureSnapshot(
                    feature: feature,
                    status: feature == FeatureId.spoc && failed
                        ? FeatureLoadStatus.failure
                        : FeatureLoadStatus.empty,
                  ),
              },
              onProjectTodos: (_) async => HomeTodoProjection([todo]),
              onFeatureTap: (_) {},
              onTodoTap: (value) => opened = value,
              onRetryFeature: (_) async => setState(() => failed = false),
              onRefresh: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final warning = find.byKey(const ValueKey('home-source-warning'));
    await tester.ensureVisible(warning);
    await tester.tap(
      find.descendant(
        of: warning,
        matching: find.widgetWithText(TextButton, '重试'),
      ),
    );
    await tester.pumpAndSettle();
    expect(warning, findsNothing);
    await tester.ensureVisible(find.text(todo.title));
    await tester.tap(find.text(todo.title));
    expect(opened?.id, todo.id);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
