import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../features/assignments/content_test.dart' as coursework;
import '../features/assignments/spoc_filters_test.dart' as spoc_fixture;

void main() {
  for (final feature in [FeatureId.judge, FeatureId.spoc]) {
    testWidgets('${feature.title}按课程连续展示，超过二十项仍可滚动到最后一项', (tester) async {
      await coursework.showFeature(tester, feature, [
        for (var i = 0; i < 42; i++)
          feature == FeatureId.judge
              ? coursework.judge(i.toString().padLeft(2, '0'))
              : spoc_fixture.spoc(
                  '${i.toString().padLeft(2, '0')} 作业',
                  AssignmentSubmissionStatus.unsubmitted,
                  null,
                ),
      ], []);
      final last = find.text('41 作业');
      final list = find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .last;
      await tester.scrollUntilVisible(
        last,
        500,
        scrollable: list,
        maxScrolls: 40,
      );
      await Scrollable.ensureVisible(tester.element(last), alignment: .5);
      await tester.pumpAndSettle();
      expect(last.hitTestable(), findsOneWidget);
    });
  }
}
