part of '../bridge_backend.dart';

Future<FeatureResult> _loadEvaluationOnRoute(
  BridgeBackend backend, {
  required ConnectionMode route,
}) async {
  try {
    final result = await backend.client.evaluationAllOnRoute(
      route: _toBridgeConnectionMode(route),
    );
    return _mapEvaluationResult(
      result.data,
      _toConnectionMode(result.pinnedRoute),
    );
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
}

Future<FeatureResult> _loadEvaluationFeature(
  BridgeBackend backend,
  FeatureId feature,
  FeatureQuery query,
) async {
  if (feature != FeatureId.evaluation) {
    throw StateError('unexpected feature: $feature');
  }
  switch (query.view) {
    case FeatureQueryView.summary:
    case FeatureQueryView.evaluationPending:
      final result = await backend.client.evaluationAll();
      return _mapEvaluationResult(
        result.data,
        _toConnectionMode(result.route.resolvedRoute),
        pendingOnly: query.view == FeatureQueryView.evaluationPending,
      );
    default:
      throw const BackendException(UbaaErrorCode.invalidInput);
  }
}

FeatureResult _mapEvaluationResult(
  BridgeEvaluationCoursesResponse data,
  ConnectionMode resolvedRoute, {
  bool pendingOnly = false,
}) {
  final normalizedTargetCounts = <String, int>{};
  for (final course in data.courses) {
    final key = _normalizedEvaluationBridgeTargetKey(course.submitTarget);
    if (key != null) {
      normalizedTargetCounts.update(
        key,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
  }
  final courses = pendingOnly
      ? data.courses.where((course) => !course.isEvaluated)
      : data.courses;
  final details = courses
      .map(
        (course) => _mapEvaluationCourseDetail(course, normalizedTargetCounts),
      )
      .toList(growable: false);
  final progress = data.progress;
  final summary = pendingOnly
      ? '待评 ${progress.pendingCourses} 门'
      : '已评 ${progress.evaluatedCourses}/${progress.totalCourses} 门';
  return FeatureResult.success(
    summary: summary,
    details: details,
    resolvedRoute: resolvedRoute,
  );
}

FeatureDetail _mapEvaluationCourseDetail(
  BridgeEvaluationCourse course,
  Map<String, int> normalizedTargetCounts,
) {
  final target = _mapEvaluationSubmitTarget(course.submitTarget);
  final targetKey = target?.selectionKey;
  final originalEligibility = _toEvaluationActionEligibility(
    course.submitEligibility,
  );
  final allowedIsConsistent =
      originalEligibility == ActionEligibility.allowed &&
      target != null &&
      !course.isEvaluated &&
      course.kcmc.trim().isNotEmpty &&
      course.bpmc.trim().isNotEmpty &&
      course.id == _evaluationCourseId(target) &&
      normalizedTargetCounts[targetKey] == 1;
  final eligibility = allowedIsConsistent
      ? ActionEligibility.allowed
      : originalEligibility == ActionEligibility.allowed ||
            course.submitTarget != null
      ? ActionEligibility.unknown
      : originalEligibility;
  final safeTarget = allowedIsConsistent ? target : null;
  final courseName = course.kcmc.trim().isEmpty ? '未知课程' : course.kcmc;
  final teacherName = course.bpmc.trim().isEmpty ? '未知教师' : course.bpmc;
  return FeatureDetail(
    title: courseName,
    subtitle: teacherName,
    fields: _compactFields(<FeatureField?>[
      _field('状态', course.isEvaluated ? '已评' : '待评'),
      course.id.trim().isEmpty ? null : _field('课程 ID', course.id),
    ]),
    actions: <FeatureAction>[
      EvaluationSubmitAction(eligibility: eligibility, target: safeTarget),
    ],
  );
}

EvaluationSubmitTarget? _mapEvaluationSubmitTarget(
  BridgeEvaluationSubmitTarget? target,
) {
  if (target == null ||
      target.rwid.isEmpty ||
      target.rwid.trim() != target.rwid ||
      target.wjid.isEmpty ||
      target.wjid.trim() != target.wjid ||
      target.kcdm.isEmpty ||
      target.kcdm.trim() != target.kcdm ||
      target.bpdm == '' ||
      (target.bpdm != null && target.bpdm!.trim() != target.bpdm)) {
    return null;
  }
  return EvaluationSubmitTarget(
    rwid: target.rwid,
    wjid: target.wjid,
    kcdm: target.kcdm,
    bpdm: target.bpdm,
  );
}

String? _normalizedEvaluationBridgeTargetKey(
  BridgeEvaluationSubmitTarget? target,
) {
  if (target == null) return null;
  final rwid = target.rwid.trim();
  final wjid = target.wjid.trim();
  final kcdm = target.kcdm.trim();
  if (rwid.isEmpty || wjid.isEmpty || kcdm.isEmpty) return null;
  final bpdm = target.bpdm?.trim();
  return EvaluationSubmitTarget(
    rwid: rwid,
    wjid: wjid,
    kcdm: kcdm,
    bpdm: bpdm == null || bpdm.isEmpty ? null : bpdm,
  ).selectionKey;
}

String _evaluationCourseId(EvaluationSubmitTarget target) =>
    '${target.rwid}_${target.wjid}_${target.kcdm}_${target.bpdm ?? ''}';

ActionEligibility _toEvaluationActionEligibility(
  BridgeActionEligibility eligibility,
) => switch (eligibility) {
  BridgeActionEligibility.allowed => ActionEligibility.allowed,
  BridgeActionEligibility.denied => ActionEligibility.denied,
  BridgeActionEligibility.unknown => ActionEligibility.unknown,
};
