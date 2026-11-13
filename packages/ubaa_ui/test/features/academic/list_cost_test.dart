import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/academic/content.dart';

void main() {
  testWidgets('考试长列表按视口读取展示标题，末项仍能滚动打开', (tester) async {
    var titles = 0;
    final details = List.generate(200, (i) => _Exam(i, () => titles++));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AcademicResultContent(
            feature: FeatureId.exam,
            details: details,
          ),
        ),
      ),
    );
    expect(titles, lessThan(30), reason: '首屏不布局和读取全部离屏考试的标题');
    await tester.scrollUntilVisible(
      find.text('合成考试 199'),
      600,
      maxScrolls: 100,
    );
    await tester.tap(find.text('合成考试 199'));
    await tester.pumpAndSettle();
    expect(find.text('合成考试 199'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

class _Exam extends FeatureDetail {
  _Exam(this.index, this.onTitle)
    : super(
        title: '',
        presentation: const ExamPresentation(
          arranged: true,
          date: '2099-12-01',
          startTime: '10:00',
          endTime: '12:00',
        ),
      );
  final int index;
  final void Function() onTitle;
  @override
  String get title {
    onTitle();
    return '合成考试 $index';
  }
}
