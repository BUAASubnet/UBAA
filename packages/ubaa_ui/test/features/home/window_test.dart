import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/app/home.dart';
import '../../app/shell_parity_test.dart' as shell;

void main() {
  for (final width in [1100.0, 390.0]) {
    testWidgets('首页待办预览随页面滚动，展开后可打开末尾任务并收起，宽度 $width', (tester) async {
      tester.view.physicalSize = Size(width, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      HomeTodo? opened;
      var refreshes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeView(
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
      expect(find.text('任务4'), findsNothing, reason: '首页先展示时间最临近的四项');
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('任务11').hitTestable(),
        200,
        scrollable: outer,
      );
      await tester.tap(find.text('任务11'));
      expect(opened?.title, '任务11');
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('任务4'), findsNothing);
      expect(find.text('任务3'), findsOneWidget);
      position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.drag(find.text('任务0'), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(refreshes, 1, reason: '待办区域下拉同样触发首页刷新');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('常用功能按最近访问排序，再次访问置顶且不重复', (tester) async {
    await shell.mount(tester);
    Future<void> visit(FeatureId id) async {
      await tester.tap(find.text('学业'));
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
    // 通过实际首页卡片顺序检查导航结果，后台数据刷新不算访问。
    final cards = find.descendant(
      of: find.byType(HomeView),
      matching: find.byType(Card),
    );
    final texts = <String>[];
    for (final element in cards.evaluate()) {
      final descendants = find.descendant(
        of: find.byWidget(element.widget),
        matching: find.byType(Text),
      );
      texts.addAll(
        tester.widgetList<Text>(descendants).map((t) => t.data ?? ''),
      );
    }
    expect(texts.indexOf(FeatureId.exam.title), greaterThanOrEqualTo(0));
    expect(
      texts.indexOf(FeatureId.exam.title),
      lessThan(texts.indexOf(FeatureId.grades.title)),
    );
    expect(texts.where((t) => t == FeatureId.exam.title), hasLength(1));
  });
}
