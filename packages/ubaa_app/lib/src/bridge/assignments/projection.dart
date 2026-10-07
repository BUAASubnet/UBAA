import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../support/mapping.dart' show bridgeCompactFields, bridgeField;

ActionEligibility bridgeToSigninActionEligibility(
  BridgeActionEligibility eligibility,
) => switch (eligibility) {
  BridgeActionEligibility.allowed => ActionEligibility.allowed,
  BridgeActionEligibility.denied => ActionEligibility.denied,
  BridgeActionEligibility.unknown => ActionEligibility.unknown,
};

AssignmentSubmissionStatus bridgeSpocStatus(
  BridgeSpocSubmissionStatus status,
) => switch (status) {
  BridgeSpocSubmissionStatus.submitted => AssignmentSubmissionStatus.submitted,
  BridgeSpocSubmissionStatus.unsubmitted =>
    AssignmentSubmissionStatus.unsubmitted,
  BridgeSpocSubmissionStatus.unknown => AssignmentSubmissionStatus.unknown,
};

AssignmentSubmissionStatus _judgeStatus(BridgeJudgeSubmissionStatus status) =>
    switch (status) {
      BridgeJudgeSubmissionStatus.submitted =>
        AssignmentSubmissionStatus.submitted,
      BridgeJudgeSubmissionStatus.partial => AssignmentSubmissionStatus.partial,
      BridgeJudgeSubmissionStatus.unsubmitted =>
        AssignmentSubmissionStatus.unsubmitted,
      BridgeJudgeSubmissionStatus.unknown => AssignmentSubmissionStatus.unknown,
    };

FeatureDetail bridgeJudgeDetailPresentation(
  BridgeJudgeAssignmentDetail item, {
  bool batch = false,
}) => FeatureDetail(
  title: item.title,
  subtitle: item.courseName,
  presentation: JudgeAssignmentPresentation(
    courseId: item.courseId,
    courseName: item.courseName,
    assignmentId: item.assignmentId,
    startTime: item.startTime,
    dueTime: item.dueTime,
    maxScore: item.maxScore,
    myScore: item.myScore,
    totalProblems: item.totalProblems,
    submittedCount: item.submittedCount,
    status: _judgeStatus(item.submissionStatus),
    statusText: item.submissionStatusText,
    contentPlainText: item.contentPlainText,
    isDetail: true,
    problems: [
      for (final problem in item.problems)
        JudgeProblemPresentation(
          name: problem.name,
          score: problem.score,
          maxScore: problem.maxScore,
          status: _judgeStatus(problem.status),
          statusText: problem.statusText,
        ),
    ],
  ),
  // 父作业保留所有原搜索文本；题目不再摊平为失去归属的独立条目。
  fields: bridgeCompactFields([
    bridgeField('课程编号', item.courseId),
    bridgeField('作业编号', item.assignmentId),
    bridgeField('开始', item.startTime),
    bridgeField('截止', item.dueTime),
    bridgeField('状态', item.submissionStatusText),
    bridgeField(
      batch ? '题目数' : '进度',
      '${item.submittedCount}/${item.totalProblems}',
    ),
    bridgeField('我的得分', item.myScore),
    bridgeField('满分', item.maxScore),
    bridgeField('作业内容', item.contentPlainText),
    for (final p in item.problems) ...[
      bridgeField('题目', p.name),
      bridgeField('状态', p.statusText),
      bridgeField('得分', p.score),
      bridgeField('满分', p.maxScore),
    ],
  ]),
);

List<FeatureDetail> bridgeJudgeSummaryDetails(
  List<BridgeJudgeAssignmentSummary> data, {
  required bool includeExpired,
}) => data
    .map(
      (item) => FeatureDetail(
        title: item.title,
        subtitle: item.courseName,
        presentation: JudgeAssignmentPresentation(
          courseId: item.courseId,
          courseName: item.courseName,
          assignmentId: item.assignmentId,
          startTime: item.startTime,
          dueTime: item.dueTime,
          maxScore: item.maxScore,
          myScore: item.myScore,
          totalProblems: item.totalProblems,
          submittedCount: item.submittedCount,
          status: _judgeStatus(item.submissionStatus),
          statusText: item.submissionStatusText,
        ),
        readNavigation:
            item.courseId.trim().isEmpty || item.assignmentId.trim().isEmpty
            ? null
            : FeatureReadNavigation(
                feature: FeatureId.judge,
                query: FeatureQuery(
                  view: FeatureQueryView.judgeDetail,
                  includeExpired: includeExpired,
                  courseId: item.courseId,
                  assignmentId: item.assignmentId,
                ),
              ),
        fields: bridgeCompactFields(<FeatureField?>[
          bridgeField('课程编号', item.courseId),
          bridgeField('作业编号', item.assignmentId),
          bridgeField('开始', item.startTime),
          bridgeField('截止', item.dueTime),
          bridgeField('状态', item.submissionStatusText),
          bridgeField('进度', '${item.submittedCount}/${item.totalProblems}'),
          bridgeField('我的得分', item.myScore),
          bridgeField('满分', item.maxScore),
        ]),
      ),
    )
    .toList(growable: false);
