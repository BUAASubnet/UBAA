import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'backend.dart';

void registerCourseworkFixtureContract() {
  test('合成加载只在截图调用方明确释放后结束', () async {
    final backend = CourseworkBackend(state: 'loading')..signedIn = true;
    backend.holdNextRead();
    final request = backend.loadFeatureQuery(
      FeatureId.judge,
      const FeatureQuery(),
    );
    expect(backend.hasPendingRead, isTrue);
    backend.releaseRead();
    expect((await request).details, isNotEmpty);
    expect(backend.hasPendingRead, isFalse);
  });
  test('合成空列表保持生产empty语义，评教空详情仍success带进度', () async {
    final backend = CourseworkBackend(state: 'empty')..signedIn = true;
    for (final feature in [FeatureId.spoc, FeatureId.judge, FeatureId.signin]) {
      expect((await backend.loadFeature(feature)).isEmpty, isTrue);
    }
    final evaluation = await backend.loadFeature(FeatureId.evaluation);
    expect(evaluation.isEmpty, isFalse);
    expect(evaluation.overview, isA<EvaluationProgressOverview>());
  });
  test('合成作业typed导航、批量题目归属和空待评全局进度', () async {
    final backend = CourseworkBackend()..signedIn = true;
    final spoc = await backend.loadFeature(FeatureId.spoc);
    expect(spoc.details.length, 2);
    expect(spoc.overview, isA<SpocTermOverview>());
    expect(
      spoc.details.first.readNavigation!.query.hasSameParameters(
        const FeatureQuery(
          view: FeatureQueryView.spocDetail,
          assignmentId: 'spoc-a',
        ),
      ),
      isTrue,
    );
    final judge = await backend.loadFeatureQuery(
      FeatureId.judge,
      const FeatureQuery(
        view: FeatureQueryView.judgeBatchDetails,
        judgeKeys: [
          JudgeAssignmentQueryKey(courseId: 'judge-b', assignmentId: 'shared'),
          JudgeAssignmentQueryKey(courseId: 'judge-a', assignmentId: 'shared'),
        ],
      ),
    );
    final parents = judge.details
        .map((d) => d.presentation as JudgeAssignmentPresentation)
        .toList();
    expect(parents.map((p) => p.courseId), ['judge-b', 'judge-a']);
    expect(parents[0].problems.first.score, '22');
    expect(parents[1].problems.first.score, '11');
    final completed = CourseworkBackend(state: 'all-evaluated')
      ..signedIn = true;
    final empty = await completed.loadFeatureQuery(
      FeatureId.evaluation,
      const FeatureQuery(view: FeatureQueryView.evaluationPending),
    );
    expect(empty.details, isEmpty);
    final progress = empty.overview! as EvaluationProgressOverview;
    expect(
      [
        progress.totalCourses,
        progress.evaluatedCourses,
        progress.pendingCourses,
      ],
      [4, 4, 0],
    );
  });
  test('合成签到事实与资格独立，准备取消不提交', () async {
    final backend = CourseworkBackend()..signedIn = true;
    final all = await backend.loadFeature(FeatureId.signin);
    expect(all.details.length, 6);
    final pending = await backend.loadFeatureQuery(
      FeatureId.signin,
      const FeatureQuery(view: FeatureQueryView.signinPending),
    );
    expect(pending.details.length, 1);
    final action = pending.details.single.actions.single as SigninPerformAction;
    expect(action.scheduleId, 'schedule-0');
    final intent = await backend.prepareSigninPerform(
      courseId: action.scheduleId,
    );
    await backend.discardWriteIntent(intent.intentId);
    expect(backend.preparedSignin, ['schedule-0']);
    expect(backend.discarded, [intent.intentId]);
    expect(backend.commitCalls, 0);
  });
}
