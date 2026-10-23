import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/grades/cards.dart';

void main() {
  for (final (credits, expected) in [
    ([23.5, .1, .1], '23.7'),
    ([.1, .2], '0.3'),
    ([2.0, 1.0], '3'),
    ([.25, .5], '0.75'),
  ]) {
    testWidgets('学分累加后的统计显示 $expected，避免浮点尾数并保留有效小数', (tester) async {
      final statistics = GradeStatistics.calculate([
        for (final credit in credits)
          GradePresentation(courseName: '合成课程', credit: credit),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GradeSummaryCard(
              title: '本学期',
              statistics: statistics,
              showCourseAndCredits: true,
            ),
          ),
        ),
      );
      final total = find
          .ancestor(of: find.text('总学分'), matching: find.byType(Column))
          .first;
      expect(
        find.descendant(of: total, matching: find.text(expected)),
        findsOneWidget,
      );
    });
  }
  testWidgets('成绩统计卡可独立挂载，缺失统计显示占位并保留重试', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GradeSummaryCard(title: '本学期', onRetry: () => retries++),
        ),
      ),
    );
    expect(find.text('本学期'), findsOneWidget);
    expect(find.text('--'), findsNWidgets(3));
    await tester.tap(find.text('重试统计'));
    expect(retries, 1);
  });
}
