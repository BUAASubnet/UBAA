import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/src/bridge/features/bykc/cache.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/src/features/bykc/chosen_card.dart';

void main() {
  for (final points in [true, false, null]) {
    testWidgets('已选缓存保留自主签到标签且不恢复动作：$points', (tester) async {
      final cached = await bridgeCachedBykcProjection(
        _Cache(points),
        const LocalAccount(id: 'synthetic', username: 'synthetic'),
        const FeatureQuery(view: FeatureQueryView.bykcChosenCourses),
        BridgeConnectionMode.direct,
      );
      final detail = cached!.details.single;
      expect(detail.actions, isEmpty);
      final course = detail.presentation! as BykcChosenPresentation;
      expect(course.signPointCount, isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BykcChosenCard(course: course, onTap: null)),
        ),
      );
      expect(find.text('自主签到'), points == true ? findsOneWidget : findsNothing);
    });
  }
}

class _Cache implements BridgeOfflineCache {
  _Cache(this.points);
  final bool? points;
  @override
  Future<BridgeCachedBykcChosenRecord?> readBykcChosen({
    required BridgeConnectionMode route,
  }) async => BridgeCachedBykcChosenRecord(
    data: BridgeCachedBykcChosen(
      semesterStart: '2026-09-01',
      semesterEnd: '2027-01-31',
      courses: [
        BridgeCachedBykcChosenCourse(
          id: 1,
          courseId: 2,
          courseName: '合成课程',
          signWindow: points == null
              ? null
              : BridgeCachedBykcSignWindow(hasPoints: points!),
        ),
      ],
    ),
    sourceRoute: route,
    fetchedAt: 100,
    complete: true,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
