import 'package:clock/clock.dart';
import 'package:ubaa_ui/src/features/schedule/content.dart';
import 'package:ubaa_ui/src/features/schedule/flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../assignments/content_test.dart' show showFeature;

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
  testWidgets('周末课程决定五列或七列且当天表头和时间线对应周三', (tester) async {
    await withClock(Clock.fixed(DateTime.utc(2026, 9, 9, 0, 20)), () async {
      for (final weekend in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ScheduleWeekScope(
                week: const WeekPresentation(
                  requestTerm: 'term',
                  responseTerm: 'term',
                  number: 1,
                  current: true,
                  startDate: '2026-09-07',
                  endDate: '2026-09-13',
                ),
                child: ScheduleContent(
                  details: [
                    course('当天课程', 3, 1, 2),
                    if (weekend) course('周末课程', 7, 1, 2),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final day in ['周一', '周二', '周三', '周四', '周五']) {
          expect(find.text(day), findsOneWidget);
        }
        expect(find.text('周六'), weekend ? findsOneWidget : findsNothing);
        expect(find.text('周日'), weekend ? findsOneWidget : findsNothing);
        final today = tester.widget<Text>(find.text('周三'));
        final theme = Theme.of(tester.element(find.text('周三')));
        expect(today.style?.color, theme.colorScheme.primary);
        expect(today.style?.fontWeight, FontWeight.bold);
        expect(tester.widget<Text>(find.text('周二')).style?.color, isNull);
        final monday = tester.getCenter(find.text('周一')).dx;
        final tuesday = tester.getCenter(find.text('周二')).dx;
        final last = tester.getCenter(find.text(weekend ? '周日' : '周五')).dx;
        expect(
          (last - monday) / (tuesday - monday),
          closeTo(weekend ? 6 : 4, .01),
        );
        final line = tester.getRect(
          find.byKey(const ValueKey('schedule-now-line')),
        );
        expect(
          line.center.dx,
          closeTo(tester.getCenter(find.text('周三')).dx, 5),
        );
        await tester.tap(find.text('当天课程'));
        await tester.pumpAndSettle();
        expect(find.text('星期三 · 第1–2节 · 08:00–09:40'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, '关闭'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });

  testWidgets('已查询的空周课表保留五日网格，不冒充读取失败', (tester) async {
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
    expect(find.text('周五'), findsOneWidget);
    expect(find.text('周日'), findsNothing);
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
    expect(find.text('CODE-$name'), findsNothing);
    expect(find.text('星期日 · 第1节 · 08:00–09:40'), findsOneWidget);
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
    await tester.tap(find.text('未知时间课程'));
    await tester.pumpAndSettle();
    expect(find.text('第4–2节 · 08:00–09:40'), findsOneWidget);

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
      expect(find.text('CODE-周一早课'), findsNothing);
      expect(find.text('星期一 · 第1–2节 · 08:00–09:40'), findsOneWidget);
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
    expect(find.text('CODE-合成重叠课程21'), findsNothing);
    expect(find.text('星期一 · 第1–2节 · 08:00–09:40'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
