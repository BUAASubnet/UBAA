import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_ui/src/features/grades/cards.dart';

void main() {
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
