part of '../bridge_backend.dart';

Future<FeatureResult> _loadAssignmentFeature(
  BridgeBackend backend,
  FeatureId feature,
  FeatureQuery query,
) async {
  final client = backend.client;
  switch (feature) {
    case FeatureId.spoc:
      return _loadSpocHome(backend, query);
    case FeatureId.judge:
      switch (query.view) {
        case FeatureQueryView.summary:
          return _loadJudgeWithCache(
            backend,
            includeExpired: query.includeExpired,
          );
        case FeatureQueryView.judgeDetail:
          final courseId = _requiredQueryValue(query.courseId, '课程编号');
          final assignmentId = _requiredQueryValue(query.assignmentId, '作业编号');
          final result = await client.judgeAssignment(
            courseId: courseId,
            assignmentId: assignmentId,
          );
          return FeatureResult.success(
            summary: '希冀作业详情',
            details: [_judgeDetailPresentation(result.data)],
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.judgeBatchDetails:
          if (query.judgeKeys.isEmpty) {
            throw const BackendException(UbaaErrorCode.invalidInput);
          }
          final result = await client.judgeAssignmentDetails(
            keys: query.judgeKeys
                .map(
                  (key) => BridgeJudgeAssignmentKey(
                    courseId: key.courseId,
                    assignmentId: key.assignmentId,
                  ),
                )
                .toList(growable: false),
          );
          final details = result.data
              .map((item) => _judgeDetailPresentation(item, batch: true))
              .toList(growable: false);
          return FeatureResult.success(
            summary: '${result.data.length}项希冀作业详情',
            details: details,
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        default:
          throw const BackendException(UbaaErrorCode.invalidInput);
      }
    case FeatureId.signin:
      return _loadSigninHome(backend, query);
    default:
      throw StateError('unexpected feature: $feature');
  }
}

ActionEligibility _toSigninActionEligibility(
  BridgeActionEligibility eligibility,
) => switch (eligibility) {
  BridgeActionEligibility.allowed => ActionEligibility.allowed,
  BridgeActionEligibility.denied => ActionEligibility.denied,
  BridgeActionEligibility.unknown => ActionEligibility.unknown,
};

AssignmentSubmissionStatus _spocStatus(BridgeSpocSubmissionStatus status) =>
    switch (status) {
      BridgeSpocSubmissionStatus.submitted =>
        AssignmentSubmissionStatus.submitted,
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
FeatureDetail _judgeDetailPresentation(
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
  fields: _compactFields([
    _field('课程编号', item.courseId),
    _field('作业编号', item.assignmentId),
    _field('开始', item.startTime),
    _field('截止', item.dueTime),
    _field('状态', item.submissionStatusText),
    _field(
      batch ? '题目数' : '进度',
      '${item.submittedCount}/${item.totalProblems}',
    ),
    _field('我的得分', item.myScore),
    _field('满分', item.maxScore),
    _field('作业内容', item.contentPlainText),
    for (final p in item.problems) ...[
      _field('题目', p.name),
      _field('状态', p.statusText),
      _field('得分', p.score),
      _field('满分', p.maxScore),
    ],
  ]),
);

List<FeatureDetail> _judgeSummaryDetails(
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
        fields: _compactFields(<FeatureField?>[
          _field('课程编号', item.courseId),
          _field('作业编号', item.assignmentId),
          _field('开始', item.startTime),
          _field('截止', item.dueTime),
          _field('状态', item.submissionStatusText),
          _field('进度', '${item.submittedCount}/${item.totalProblems}'),
          _field('我的得分', item.myScore),
          _field('满分', item.maxScore),
        ]),
      ),
    )
    .toList(growable: false);
