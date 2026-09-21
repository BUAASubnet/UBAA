import 'package:test/test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('缓存展示投影保持时间来源且不携带学校写动作', () {
    final fetched = DateTime.utc(2026, 9, 21, 1);
    final cached = CachedFeatureProjection(
      feature: FeatureId.schedule,
      accountId: 'opaque-fixture',
      route: ConnectionMode.direct,
      fetchedAt: fetched,
      scopeDate: '2026-09-21',
      complete: true,
      details: const [
        FeatureDetail(
          title: '合成课程',
          actions: [
            BykcSelectAction(
              courseId: 1,
              eligibility: ActionEligibility.allowed,
            ),
          ],
          presentation: TodayCoursePresentation(
            time: '08:00-09:35',
            place: '合成教室',
          ),
        ),
      ],
    );
    final snapshot = cached.toSnapshot();
    expect(snapshot.status, FeatureLoadStatus.stale);
    expect(snapshot.updatedAt, fetched);
    expect(snapshot.evidence?.origin, DataOrigin.persisted);
    expect(snapshot.evidence?.scopeDate, '2026-09-21');
    expect(snapshot.details.single.actions, isEmpty);
    expect(
      snapshot.copyWith(status: FeatureLoadStatus.loading).evidence?.fetchedAt,
      fetched,
    );
  });
}
