import 'package:test/test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('题目集合复制且不可变，父作业保留状态和nullable字段', () {
    final problems = [
      const JudgeProblemPresentation(
        name: '同名题',
        status: AssignmentSubmissionStatus.unknown,
        statusText: '未识别',
      ),
    ];
    final p = JudgeAssignmentPresentation(
      courseId: 'B',
      courseName: '同名课程',
      assignmentId: 'A',
      totalProblems: 1,
      submittedCount: 0,
      status: AssignmentSubmissionStatus.partial,
      statusText: '部分',
      problems: problems,
    );
    problems.clear();
    expect(p.problems.single.name, '同名题');
    expect(() => p.problems.clear(), throwsUnsupportedError);
    expect(p.myScore, isNull);
    expect(p.status, AssignmentSubmissionStatus.partial);
  });
  test('集合overview独立于空details且copyWith显式清理', () {
    const overview = EvaluationProgressOverview(
      totalCourses: 4,
      evaluatedCourses: 4,
      pendingCourses: 0,
    );
    const result = FeatureResult.empty(overview: overview);
    const snapshot = FeatureSnapshot(
      feature: FeatureId.evaluation,
      overview: overview,
    );
    expect(result.overview, same(overview));
    expect(
      snapshot.copyWith(status: FeatureLoadStatus.stale).overview,
      same(overview),
    );
    expect(snapshot.copyWith(clearOverview: true).overview, isNull);
    expect(const FeatureResult.failure(null).overview, isNull);
  });
}
