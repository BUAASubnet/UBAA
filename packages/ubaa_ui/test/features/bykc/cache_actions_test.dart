import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/common/details/detail_list.dart';

void main() {
  for (final (selected, full, allowed) in [
    (false, false, true),
    (false, true, false),
    (true, false, true),
    (true, false, false),
  ]) {
    testWidgets('缓存按钮保持卡片高度且在线资格到达前不可写：$selected/$full/$allowed', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(402, 874);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final calls = <(WriteOperation, int)>[];
      final detail = FeatureDetail(
        title: '合成课程',
        presentation: BykcCoursePresentation(
          id: 42,
          courseName: '合成课程',
          selected: selected,
          status: selected
              ? BykcCourseStatus.selected
              : full
              ? BykcCourseStatus.full
              : BykcCourseStatus.available,
          courseCurrentCount: full ? 10 : 3,
          courseMaxCount: 10,
        ),
        actions: [
          if (selected)
            BykcDeselectAction(
              courseId: 42,
              eligibility: allowed
                  ? ActionEligibility.allowed
                  : ActionEligibility.denied,
            )
          else
            BykcSelectAction(
              courseId: 42,
              eligibility: allowed
                  ? ActionEligibility.allowed
                  : ActionEligibility.denied,
            ),
        ],
      );
      final cached = readonlyFeatureDetails([detail]);
      Future<void> mount(bool online) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeatureDetailList(
              feature: FeatureId.bykc,
              details: online ? [detail] : cached,
              bykcStatuses: const {},
              onBykcWrite: (op, id) async => calls.add((op, id)),
            ),
          ),
        ),
      );
      final label = selected
          ? '退选'
          : full
          ? '已满'
          : '选课';
      Finder button() => find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      await mount(false);
      expect(cached.single.actions, isEmpty);
      expect(tester.widget<ButtonStyleButton>(button()).onPressed, isNull);
      final height = tester.getSize(find.widgetWithText(Card, '合成课程')).height;
      await tester.tap(button());
      expect(calls, isEmpty);
      await mount(true);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.widgetWithText(Card, '合成课程')).height,
        closeTo(height, .01),
      );
      expect(
        tester.widget<ButtonStyleButton>(button()).onPressed,
        allowed ? isNotNull : isNull,
      );
      await tester.tap(button());
      expect(
        calls,
        allowed
            ? [
                (
                  selected
                      ? WriteOperation.bykcDeselectCourse
                      : WriteOperation.bykcSelectCourse,
                  42,
                ),
              ]
            : isEmpty,
      );
    });
  }
}
