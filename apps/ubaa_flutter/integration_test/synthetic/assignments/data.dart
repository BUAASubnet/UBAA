part of 'backend.dart';

FeatureResult _courseworkData(
  CourseworkBackend backend,
  FeatureId feature,
  FeatureQuery query,
) {
  final state = backend.state;
  final empty = state == 'empty';
  final count = state == 'many' ? 42 : 2;
  String title(String base) =>
      state == 'long' ? '$base——合成跨学院课程长标题与状态布局检查' : base;
  String body(String marker) => state == 'long'
      ? '${List.generate(24, (i) => '$marker 第${i + 1}段：这是明确合成的课程正文，用于检验长段落的换行、连续阅读与尾部可达。不得由时间字符串推断作业资格。').join('\n\n')}\n$marker 正文尾部'
      : '$marker 合成正文\n$marker 正文尾部';
  FeatureResult result(
    List<FeatureDetail> details, {
    FeatureOverview? overview,
  }) =>
      details.isEmpty &&
          (feature == FeatureId.spoc || feature == FeatureId.judge) &&
          query.view == FeatureQueryView.summary
      ? FeatureResult.empty(
          overview: overview,
          resolvedRoute: ConnectionMode.direct,
        )
      : FeatureResult.success(
          summary: '合成课程数据',
          details: details,
          overview: overview,
          resolvedRoute: ConnectionMode.direct,
        );
  FeatureDetail spoc(int i, {bool detail = false}) {
    final suffix = i == 0
        ? 'a'
        : i == 1
        ? 'b'
        : '$i';
    final id = 'spoc-$suffix';
    return FeatureDetail(
      title: title('同名合成作业'),
      subtitle: 'SPOC课程$suffix',
      fields: const [FeatureField(label: '作业编号', value: '误导展示编号')],
      presentation: SpocAssignmentPresentation(
        courseId: 'spoc-course-$suffix',
        courseName: 'SPOC课程$suffix',
        assignmentId: id,
        teacherName: '合成教师$suffix',
        startTime: '时间待确认',
        dueTime: '2026-09-20 23:59',
        score: i == 0 ? null : '优秀',
        status: i == 0
            ? AssignmentSubmissionStatus.unsubmitted
            : AssignmentSubmissionStatus.submitted,
        statusText: i == 0 ? '未提交' : '已提交',
        contentPlainText: detail ? body('SPOC$suffix') : null,
        submittedAt: i == 0 ? null : '2026-09-08',
        isDetail: detail,
      ),
      readNavigation: detail
          ? null
          : FeatureReadNavigation(
              feature: FeatureId.spoc,
              query: FeatureQuery(
                view: FeatureQueryView.spocDetail,
                assignmentId: id,
              ),
            ),
    );
  }

  FeatureDetail judge(String course, String id, {bool detail = false}) {
    final b = course == 'judge-b';
    return FeatureDetail(
      title: title('同名合成实验'),
      subtitle: '希冀课程$course',
      fields: const [
        FeatureField(label: '课程编号', value: '误导课程'),
        FeatureField(label: '作业编号', value: '误导作业'),
      ],
      presentation: JudgeAssignmentPresentation(
        courseId: course,
        courseName: '希冀课程$course',
        assignmentId: id,
        startTime: '时间待确认',
        dueTime: '原始截止字符串',
        maxScore: '100',
        myScore: b ? '22' : null,
        totalProblems: 2,
        submittedCount: 1,
        status: AssignmentSubmissionStatus.partial,
        statusText: '部分提交',
        contentPlainText: detail ? body(course) : null,
        isDetail: detail,
        problems: detail
            ? [
                JudgeProblemPresentation(
                  name: '同名题目',
                  status: AssignmentSubmissionStatus.submitted,
                  statusText: '$course 题目已通过',
                  score: b ? '22' : '11',
                  maxScore: '50',
                ),
                JudgeProblemPresentation(
                  name: '$course 嵌套检索标记',
                  status: AssignmentSubmissionStatus.unknown,
                  statusText: '状态待确认',
                  score: null,
                  maxScore: '50',
                ),
              ]
            : [],
      ),
      readNavigation: detail
          ? null
          : FeatureReadNavigation(
              feature: FeatureId.judge,
              query: FeatureQuery(
                view: FeatureQueryView.judgeDetail,
                includeExpired: query.includeExpired,
                courseId: course,
                assignmentId: id,
              ),
            ),
    );
  }

  switch (feature) {
    case FeatureId.spoc:
      if (query.view == FeatureQueryView.spocDetail) {
        final id = query.assignmentId;
        if (id == null) {
          throw const BackendException(UbaaErrorCode.invalidInput);
        }
        final index = id == 'spoc-a'
            ? 0
            : id == 'spoc-b'
            ? 1
            : int.tryParse(id.replaceFirst('spoc-', ''));
        if (index == null) {
          throw const BackendException(UbaaErrorCode.invalidInput);
        }
        return result(empty ? [] : [spoc(index, detail: true)]);
      }
      return result(
        empty ? [] : List.generate(count, spoc),
        overview: const SpocTermOverview(
          termCode: '2026-2027-1',
          termName: '合成秋季学期',
        ),
      );
    case FeatureId.judge:
      if (query.view == FeatureQueryView.judgeBatchDetails) {
        if (query.judgeKeys.isEmpty) {
          throw const BackendException(UbaaErrorCode.invalidInput);
        }
        return result(
          empty
              ? []
              : [
                  for (final key in query.judgeKeys)
                    judge(key.courseId, key.assignmentId, detail: true),
                ],
        );
      }
      if (query.view == FeatureQueryView.judgeDetail) {
        if (query.courseId == null || query.assignmentId == null) {
          throw const BackendException(UbaaErrorCode.invalidInput);
        }
        return result(
          empty
              ? []
              : [judge(query.courseId!, query.assignmentId!, detail: true)],
        );
      }
      return result(
        empty
            ? []
            : [
                for (var i = 0; i < count; i++)
                  judge(
                    i == 0
                        ? 'judge-a'
                        : i == 1
                        ? 'judge-b'
                        : 'judge-$i',
                    'shared',
                  ),
                if (query.includeExpired) judge('judge-expired', 'expired'),
              ],
      );
    case FeatureId.signin:
      final rows = <FeatureDetail>[];
      for (var i = 0; i < (state == 'many' ? 42 : 6); i++) {
        final status = <int?>[0, 1, 0, 1, null, 2][i % 6];
        final eligibility = i % 6 == 0
            ? ActionEligibility.allowed
            : i % 6 == 1
            ? ActionEligibility.denied
            : ActionEligibility.unknown;
        if (query.view == FeatureQueryView.signinPending &&
            eligibility != ActionEligibility.allowed) {
          continue;
        }
        if (query.view == FeatureQueryView.signinCompleted &&
            eligibility != ActionEligibility.denied) {
          continue;
        }
        rows.add(
          FeatureDetail(
            title: title('合成签到课程$i'),
            presentation: SigninPresentation(
              courseId: 'schedule-$i',
              classBeginTime: '08:00',
              classEndTime: '09:35',
              signStatus: status,
            ),
            actions: i % 6 < 2 || i % 6 >= 4
                ? [
                    SigninPerformAction(
                      scheduleId: 'schedule-$i',
                      eligibility: eligibility,
                    ),
                  ]
                : [],
          ),
        );
      }
      if (empty || rows.isEmpty) {
        return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
      }
      return FeatureResult.success(
        summary: query.view == FeatureQueryView.signinPending
            ? '${empty ? 0 : rows.length} 门可签到课程'
            : '合成签到记录',
        details: empty ? [] : rows,
        resolvedRoute: ConnectionMode.direct,
      );
    case FeatureId.evaluation:
      final total = empty
          ? 0
          : state == 'many'
          ? 42
          : state == 'all-evaluated'
          ? 4
          : 6;
      final allDone = state == 'all-evaluated';
      final evaluated = allDone ? total : total ~/ 2;
      final rows = <FeatureDetail>[];
      for (var i = 0; i < total; i++) {
        final done = allDone || i.isOdd;
        if (query.view == FeatureQueryView.evaluationPending && done) continue;
        final target = EvaluationSubmitTarget(
          rwid: 'task-$i',
          wjid: 'form-$i',
          kcdm: 'course-$i',
          bpdm: 'teacher-$i',
        );
        rows.add(
          FeatureDetail(
            title: title('同名合成评教课程'),
            subtitle: i == 4 ? '' : '合成教师$i',
            fields: [
              FeatureField(
                label: '课程 ID',
                value: 'task-${i}_form-${i}_course-${i}_teacher-$i',
              ),
            ],
            presentation: EvaluationCoursePresentation(
              courseId: 'task-${i}_form-${i}_course-${i}_teacher-$i',
              isEvaluated: done,
            ),
            actions: [
              EvaluationSubmitAction(
                eligibility: done
                    ? ActionEligibility.denied
                    : i == 4
                    ? ActionEligibility.unknown
                    : ActionEligibility.allowed,
                target: done || i == 4 ? null : target,
              ),
            ],
          ),
        );
      }
      return result(
        rows,
        overview: EvaluationProgressOverview(
          totalCourses: total,
          evaluatedCourses: evaluated,
          pendingCourses: total - evaluated,
        ),
      );
    default:
      return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
  }
}
