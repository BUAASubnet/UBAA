import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/schedule/content.dart';

FeatureDetail course(int n) => FeatureDetail(
  title: '合成课程$n',
  presentation: ScheduleCoursePresentation(
    courseCode: 'course-$n',
    dayOfWeek: n % 7 + 1,
    beginSection: n < 7 ? 1 : 4,
    endSection: n < 7 ? 2 : 5,
    color: '#FFCC99',
  ),
);

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('$brightness同色源课程可区分，切周后颜色保持且文字清晰', (tester) async {
      Future<void> show(List<FeatureDetail> details) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(body: ScheduleContent(details: details)),
          ),
        );
        await tester.pumpAndSettle();
      }

      Color background(int n) => tester
          .widget<Material>(
            find
                .ancestor(
                  of: find.text('合成课程$n'),
                  matching: find.byType(Material),
                )
                .first,
          )
          .color!;
      await show([for (var n = 0; n < 12; n++) course(n)]);
      final colors = [for (var n = 0; n < 12; n++) background(n)];
      expect(colors.toSet().length, 12, reason: '不同课程不复用同一背景色');
      for (var n = 0; n < 12; n++) {
        final foreground = tester
            .widget<Text>(find.text('合成课程$n'))
            .style!
            .color!;
        final a = colors[n].computeLuminance(),
            b = foreground.computeLuminance();
        expect(
          (a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05)),
          greaterThanOrEqualTo(4.5),
          reason: '课程名称保持可读对比度',
        );
      }
      await show([course(8), course(1), course(12)]);
      expect(background(8), colors[8]);
      expect(background(1), colors[1]);
      expect(background(12), isNot(anyOf(colors)));
    });
  }
}
