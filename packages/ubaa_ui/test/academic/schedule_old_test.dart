import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../coursework_content_test.dart' show showFeature;

FeatureDetail course(String title, int day, int begin, int end) =>
    FeatureDetail(
      title: title,
      presentation: ScheduleCoursePresentation(
        courseCode: 'CODE-$title',
        dayOfWeek: day,
        beginSection: begin,
        endSection: end,
        place: '合成A203',
        beginTime: '08:00',
        endTime: '09:40',
        weeksAndTeachers: '合成教师与第1–16周',
        teachingTarget: '合成教学对象',
      ),
    );
void main() {
  testWidgets('已查询的空周课表仍保留七日网格，不冒充读取失败', (tester) async {
    await showFeature(
      tester,
      FeatureId.schedule,
      [],
      [],
      query: const FeatureQuery(
        view: FeatureQueryView.scheduleWeek,
        term: 'term',
        week: 4,
      ),
    );
    expect(find.text('周一'), findsOneWidget);
    expect(find.text('周日'), findsOneWidget);
    expect(find.text('本周暂无课程'), findsOneWidget);
    expect(
      tester.getRect(find.text('本周暂无课程')).top,
      greaterThan(tester.getRect(find.text('周一')).bottom),
    );
    expect(find.text('重试'), findsNothing);
  });
  testWidgets('大字横滚保留节次列，单节长课程可查看', (tester) async {
    final name = List.filled(5, '合成很长课程').join();
    await showFeature(
      tester,
      FeatureId.schedule,
      [course(name, 7, 1, 1), course('未知时间课程', 9, 4, 2)],
      [],
      size: const Size(390, 844),
      textScale: 1.3,
    );
    final horizontal = find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    );
    await tester.drag(horizontal, const Offset(-250, 0));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('1')).left, greaterThanOrEqualTo(8));
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
    expect(find.text('CODE-$name'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '关闭'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('未知时间课程'),
      400,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('schedule-grid-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.drag(horizontal, const Offset(-250, 0));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('未知时间课程')).left, greaterThanOrEqualTo(8));

    expect(tester.takeException(), isNull);
  });
  for (final width in [390.0, 834.0, 1280.0]) {
    testWidgets('$width宽度沿旧七日节次网格定位，低频字段只在本地详情', (tester) async {
      final reads = <FeatureQuery>[];
      await showFeature(
        tester,
        FeatureId.schedule,
        [
          course('周一早课', 1, 1, 2),
          course('周二下午课', 2, 5, 6),
          course('周日晚课', 7, 11, 12),
        ],
        reads,
        size: Size(width, 1000),
      );
      expect(find.text('周一'), findsOneWidget);
      expect(find.text('周日'), findsOneWidget);
      final first = tester.getRect(find.text('周一早课'));
      final later = tester.getRect(find.text('周二下午课'));
      expect(later.left, greaterThan(first.right));
      expect(later.top, greaterThan(first.bottom));
      expect(tester.getRect(find.text('周日')).right, lessThanOrEqualTo(width));
      expect(find.text('合成教师与第1–16周'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('周一早课'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('CODE-周一早课'), findsOneWidget);
      expect(find.text('合成教师与第1–16周'), findsOneWidget);
      expect(find.text('合成教学对象'), findsOneWidget);
      expect(reads, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('整周不被本地20条截断，重叠与未知节次课程仍可独立查看', (tester) async {
    await showFeature(
      tester,
      FeatureId.schedule,
      [
        for (var i = 0; i < 22; i++) course('合成重叠课程$i', 1, 1, 2),
        course('时间待定课程', 9, 4, 2),
      ],
      [],
      size: const Size(390, 844),
    );
    expect(find.byTooltip('下一页'), findsNothing);
    expect(find.text('22门课程'), findsOneWidget);
    await tester.tap(find.text('22门课程'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('合成重叠课程21'),
      400,
      scrollable: find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('合成重叠课程21'));
    await tester.pumpAndSettle();
    expect(find.text('CODE-合成重叠课程21'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
