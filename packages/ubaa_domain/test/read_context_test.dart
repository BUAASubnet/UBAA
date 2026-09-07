import 'package:test/test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('读取参数比较覆盖全部字段且保留批量键顺序', () {
    const base = FeatureQuery();
    final variants = <FeatureQuery>[
      base.copyWith(term: 'term'),
      base.copyWith(date: DateTime(2026, 9, 8)),
      base.copyWith(campus: 2),
      base.copyWith(floorId: 'floor'),
      base.copyWith(section: '3'),
      base.copyWith(week: 2),
      base.copyWith(page: 1),
      base.copyWith(size: 10),
      base.copyWith(view: FeatureQueryView.scheduleTerms),
      base.copyWith(premisesId: 'p'),
      base.copyWith(storeyId: 's'),
      base.copyWith(areaId: 'a'),
      base.copyWith(startTime: 'start'),
      base.copyWith(endTime: 'end'),
      base.copyWith(segment: 'segment'),
      base.copyWith(siteId: 1),
      base.copyWith(orderId: 2),
      base.copyWith(assignmentId: 'assignment'),
      base.copyWith(courseId: 'course'),
      base.copyWith(includeExpired: true),
      base.copyWith(
        judgeKeys: [
          const JudgeAssignmentQueryKey(courseId: 'a', assignmentId: 'b'),
        ],
      ),
    ];
    expect(base.hasSameParameters(const FeatureQuery()), isTrue);
    for (final variant in variants) {
      expect(base.hasSameParameters(variant), isFalse);
      expect(variant.hasSameParameters(base), isFalse);
    }
    const first = JudgeAssignmentQueryKey(courseId: 'c1', assignmentId: 'a1');
    const second = JudgeAssignmentQueryKey(courseId: 'c2', assignmentId: 'a2');
    expect(
      base
          .copyWith(judgeKeys: [first, second])
          .hasSameParameters(base.copyWith(judgeKeys: [second, first])),
      isFalse,
    );
  });

  test('上下文冻结外部keys且区分默认读取与显式summary', () {
    final keys = <JudgeAssignmentQueryKey>[
      const JudgeAssignmentQueryKey(
        courseId: 'course',
        assignmentId: 'assignment',
      ),
    ];
    final context = FeatureReadContext(
      query: FeatureQuery(judgeKeys: keys),
      requestRevision: 7,
    );
    keys.clear();
    expect(context.query!.judgeKeys, hasLength(1));
    expect(() => context.query!.judgeKeys.clear(), throwsUnsupportedError);
    expect(context.requestRevision, 7);
    expect(
      FeatureReadContext(requestRevision: 1).hasSameQuery(const FeatureQuery()),
      isFalse,
    );
    expect(
      FeatureReadContext(
        query: const FeatureQuery(),
        requestRevision: 2,
      ).hasSameQuery(null),
      isFalse,
    );
  });
}
