part of '../bridge_backend.dart';

FeatureResult _mapSpocHome(BridgeSpocAssignments data, ConnectionMode route) {
  final details = data.assignments
      .map(
        (item) => FeatureDetail(
          title: item.title,
          subtitle: item.courseName,
          presentation: SpocAssignmentPresentation(
            courseId: item.courseId,
            courseName: item.courseName,
            assignmentId: item.assignmentId,
            teacherName: item.teacherName,
            startTime: item.startTime,
            dueTime: item.dueTime,
            score: item.score,
            status: _spocStatus(item.submissionStatus),
            statusText: item.submissionStatusText,
          ),
          readNavigation: item.assignmentId.trim().isEmpty
              ? null
              : FeatureReadNavigation(
                  feature: FeatureId.spoc,
                  query: FeatureQuery(
                    view: FeatureQueryView.spocDetail,
                    assignmentId: item.assignmentId,
                  ),
                ),
          fields: _compactFields(<FeatureField?>[
            _field('课程编号', item.courseId),
            _field('作业编号', item.assignmentId),
            _field('教师', item.teacherName),
            _field('开始', item.startTime),
            _field('截止', item.dueTime),
            _field('状态', item.submissionStatusText),
            _field('分值', item.score),
          ]),
        ),
      )
      .toList(growable: false);
  return _countResult(
    data.assignments.length,
    '项 SPOC 作业',
    overview: SpocTermOverview(
      termCode: data.termCode,
      termName: data.termName,
    ),
    details: details,
    resolvedRoute: route,
  );
}

FeatureResult _mapSpocHomeDetail(
  BridgeSpocAssignmentDetail item,
  ConnectionMode route,
) {
  return FeatureResult.success(
    summary: 'SPOC 作业详情',
    details: <FeatureDetail>[
      FeatureDetail(
        title: item.title,
        subtitle: item.courseName,
        presentation: SpocAssignmentPresentation(
          courseId: item.courseId,
          courseName: item.courseName,
          assignmentId: item.assignmentId,
          teacherName: item.teacherName,
          startTime: item.startTime,
          dueTime: item.dueTime,
          score: item.score,
          status: _spocStatus(item.submissionStatus),
          statusText: item.submissionStatusText,
          contentPlainText: item.contentPlainText,
          submittedAt: item.submittedAt,
          isDetail: true,
        ),
        fields: _compactFields(<FeatureField?>[
          _field('作业编号', item.assignmentId),
          _field('课程编号', item.courseId),
          _field('教师', item.teacherName),
          _field('开始', item.startTime),
          _field('截止', item.dueTime),
          _field('状态', item.submissionStatusText),
          _field('分值', item.score),
          _field('提交时间', item.submittedAt),
          _field('作业内容', item.contentPlainText),
        ]),
      ),
    ],
    resolvedRoute: route,
  );
}

FeatureResult _mapSigninHome(
  List<BridgeSigninClass> items,
  FeatureQuery query,
  ConnectionMode route, {
  bool persisted = false,
}) {
  final classes = switch (query.view) {
    FeatureQueryView.summary => items,
    FeatureQueryView.signinPending =>
      items
          .where(
            (item) => (persisted
                ? item.signStatus == 0
                : item.signinEligibility == BridgeActionEligibility.allowed),
          )
          .toList(growable: false),
    FeatureQueryView.signinCompleted =>
      items
          .where(
            (item) => (persisted
                ? item.signStatus == 1
                : item.signinEligibility == BridgeActionEligibility.denied),
          )
          .toList(growable: false),
    _ => throw const BackendException(UbaaErrorCode.invalidInput),
  };
  final details = classes
      .map((item) {
        final eligibility = _toSigninActionEligibility(item.signinEligibility);
        final target = item.signinTarget?.trim();
        return FeatureDetail(
          title: item.courseName,
          subtitle: '${item.classBeginTime}–${item.classEndTime}',
          presentation: SigninPresentation(
            courseId: item.courseId,
            classBeginTime: item.classBeginTime,
            classEndTime: item.classEndTime,
            signStatus: item.signStatus,
          ),
          fields: <FeatureField>[
            FeatureField(label: '课程 ID', value: item.courseId),
            FeatureField(
              label: '签到状态',
              value: switch (item.signStatus) {
                0 => '未签到',
                1 => '已签到',
                _ => '状态未知',
              },
            ),
          ],
          actions: target == null || target.isEmpty
              ? const <FeatureAction>[]
              : <FeatureAction>[
                  SigninPerformAction(
                    scheduleId: target,
                    eligibility: eligibility,
                  ),
                ],
        );
      })
      .toList(growable: false);
  return _countResult(
    classes.length,
    switch (query.view) {
      FeatureQueryView.signinPending => persisted ? '门上次未签到课程' : '门可签到课程',
      FeatureQueryView.signinCompleted => '门已签到课程',
      _ => '门今日签到课程',
    },
    details: details,
    resolvedRoute: route,
  );
}
