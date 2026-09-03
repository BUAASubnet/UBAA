part of '../bridge_backend.dart';

Future<FeatureResult> _loadAssignmentFeature(
  BridgeBackend backend,
  FeatureId feature,
  FeatureQuery query,
) async {
  final client = backend.client;
  switch (feature) {
    case FeatureId.spoc:
      switch (query.view) {
        case FeatureQueryView.summary:
          final result = await client.spocAssignments();
          final details = result.data.assignments
              .map(
                (item) => FeatureDetail(
                  title: item.title,
                  subtitle: item.courseName,
                  fields: _compactFields(<FeatureField?>[
                    _field('课程编号', item.courseId),
                    _field('作业编号', item.assignmentId),
                    _field('教师', item.teacherName),
                    _field('开始', item.startTime),
                    _field('截止', item.dueTime),
                    _field('状态', item.submissionStatusText),
                    _field('得分', item.score),
                  ]),
                ),
              )
              .toList(growable: false);
          return _countResult(
            result.data.assignments.length,
            '项 SPOC 作业',
            details: details,
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.spocDetail:
          final assignmentId = _requiredQueryValue(query.assignmentId, '作业编号');
          final result = await client.spocAssignment(
            assignmentId: assignmentId,
          );
          final item = result.data;
          return FeatureResult.success(
            summary: 'SPOC 作业详情',
            details: <FeatureDetail>[
              FeatureDetail(
                title: item.title,
                subtitle: item.courseName,
                fields: _compactFields(<FeatureField?>[
                  _field('作业编号', item.assignmentId),
                  _field('课程编号', item.courseId),
                  _field('教师', item.teacherName),
                  _field('开始', item.startTime),
                  _field('截止', item.dueTime),
                  _field('状态', item.submissionStatusText),
                  _field('得分', item.score),
                  _field('提交时间', item.submittedAt),
                  _field('作业内容', item.contentPlainText),
                ]),
              ),
            ],
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        default:
          throw const BackendException(UbaaErrorCode.invalidInput);
      }
    case FeatureId.judge:
      switch (query.view) {
        case FeatureQueryView.summary:
          final result = await client.judgeAssignments(
            includeExpired: query.includeExpired,
          );
          final details = result.data
              .map(
                (item) => FeatureDetail(
                  title: item.title,
                  subtitle: item.courseName,
                  fields: _compactFields(<FeatureField?>[
                    _field('课程编号', item.courseId),
                    _field('作业编号', item.assignmentId),
                    _field('开始', item.startTime),
                    _field('截止', item.dueTime),
                    _field('状态', item.submissionStatusText),
                    _field(
                      '进度',
                      '${item.submittedCount}/${item.totalProblems}',
                    ),
                    _field('我的得分', item.myScore),
                  ]),
                ),
              )
              .toList(growable: false);
          return _countResult(
            result.data.length,
            '项希冀作业',
            details: details,
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.judgeDetail:
          final courseId = _requiredQueryValue(query.courseId, '课程编号');
          final assignmentId = _requiredQueryValue(query.assignmentId, '作业编号');
          final result = await client.judgeAssignment(
            courseId: courseId,
            assignmentId: assignmentId,
          );
          final item = result.data;
          final problems = item.problems
              .map(
                (problem) => FeatureDetail(
                  title: problem.name,
                  fields: _compactFields(<FeatureField?>[
                    _field('状态', problem.statusText),
                    _field('得分', problem.score),
                    _field('满分', problem.maxScore),
                  ]),
                ),
              )
              .toList(growable: false);
          final details = <FeatureDetail>[
            FeatureDetail(
              title: item.title,
              subtitle: item.courseName,
              fields: _compactFields(<FeatureField?>[
                _field('课程编号', item.courseId),
                _field('作业编号', item.assignmentId),
                _field('开始', item.startTime),
                _field('截止', item.dueTime),
                _field('状态', item.submissionStatusText),
                _field('进度', '${item.submittedCount}/${item.totalProblems}'),
                _field('我的得分', item.myScore),
                _field('作业内容', item.contentPlainText),
              ]),
            ),
            ...problems,
          ];
          return FeatureResult.success(
            summary: '希冀作业详情',
            details: details,
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
          final details = <FeatureDetail>[];
          for (final item in result.data) {
            details.add(
              FeatureDetail(
                title: item.title,
                subtitle: item.courseName,
                fields: _compactFields(<FeatureField?>[
                  _field('课程编号', item.courseId),
                  _field('作业编号', item.assignmentId),
                  _field('开始', item.startTime),
                  _field('截止', item.dueTime),
                  _field('状态', item.submissionStatusText),
                  _field('题目数', '${item.submittedCount}/${item.totalProblems}'),
                  _field('我的得分', item.myScore),
                  _field('作业内容', item.contentPlainText),
                ]),
              ),
            );
            details.addAll(
              item.problems.map(
                (problem) => FeatureDetail(
                  title: problem.name,
                  fields: _compactFields(<FeatureField?>[
                    _field('状态', problem.statusText),
                    _field('得分', problem.score),
                    _field('满分', problem.maxScore),
                  ]),
                ),
              ),
            );
          }
          return FeatureResult.success(
            summary: '${result.data.length}项希冀作业详情',
            details: details,
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        default:
          throw const BackendException(UbaaErrorCode.invalidInput);
      }
    case FeatureId.signin:
      final result = await client.signinToday();
      final classes = switch (query.view) {
        FeatureQueryView.summary => result.data,
        FeatureQueryView.signinPending =>
          result.data
              .where((item) => item.signStatus == 0)
              .toList(growable: false),
        FeatureQueryView.signinCompleted =>
          result.data
              .where((item) => item.signStatus == 1)
              .toList(growable: false),
        _ => throw const BackendException(UbaaErrorCode.invalidInput),
      };
      final details = classes
          .map(
            (item) => FeatureDetail(
              title: item.courseName,
              subtitle: '${item.classBeginTime}–${item.classEndTime}',
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
            ),
          )
          .toList(growable: false);
      return _countResult(
        classes.length,
        switch (query.view) {
          FeatureQueryView.signinPending => '门未签到课程',
          FeatureQueryView.signinCompleted => '门已签到课程',
          _ => '门今日签到课程',
        },
        details: details,
        resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
      );
    default:
      throw StateError('unexpected feature: $feature');
  }
}
