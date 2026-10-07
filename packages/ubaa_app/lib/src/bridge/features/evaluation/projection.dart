import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../support/mapping.dart' show bridgeCompactFields, bridgeField;
part 'cached_models.dart';

FeatureResult bridgeMapEvaluationResult(
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
    overview: EvaluationProgressOverview(
      totalCourses: progress.totalCourses,
      evaluatedCourses: progress.evaluatedCourses,
      pendingCourses: progress.pendingCourses,
    ),
    summary: summary,
    details: details,
    resolvedRoute: resolvedRoute,
  );
}

FeatureDetail _mapEvaluationCourseDetail(
  BridgeEvaluationCourse course,
  Map<String, int> normalizedTargetCounts,
) {
  final target = bridgeMapEvaluationSubmitTarget(course.submitTarget);
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
    presentation: EvaluationCoursePresentation(
      courseId: course.id,
      isEvaluated: course.isEvaluated,
    ),
    title: courseName,
    subtitle: teacherName,
    fields: bridgeCompactFields(<FeatureField?>[
      bridgeField('状态', course.isEvaluated ? '已评' : '待评'),
      course.id.trim().isEmpty ? null : bridgeField('课程 ID', course.id),
    ]),
    actions: <FeatureAction>[
      EvaluationSubmitAction(eligibility: eligibility, target: safeTarget),
    ],
  );
}

EvaluationSubmitTarget? bridgeMapEvaluationSubmitTarget(
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
