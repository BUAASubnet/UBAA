import 'package:ubaa_domain/ubaa_domain.dart';

/// 缓存不可读时，部分在线批次仍保留本次查询已展示的范围。
FeatureResult controllerRetainJudgePartial(
  FeatureId feature,
  FeatureSnapshot previous,
  FeatureResult result, {
  bool pending = false,
}) {
  if (feature != FeatureId.judge ||
      previous.details.isEmpty ||
      (!pending && result.evidence?.complete != false) ||
      previous.resolvedRoute == null ||
      previous.resolvedRoute != result.resolvedRoute ||
      previous.evidence?.accountId != result.evidence?.accountId)
    return result;
  final rows = <(String, String), FeatureDetail>{};
  for (final detail in previous.details) {
    final key = controllerJudgeDetailKey(detail);
    if (key == null) return result;
    rows[key] = detail;
  }
  for (final detail in result.details) {
    final key = controllerJudgeDetailKey(detail);
    if (key == null) return result;
    // 索引占位不能抹掉已取得的进度、分数和截止时间。
    if (detail.presentation is JudgeAssignmentPresentation ||
        !rows.containsKey(key))
      rows[key] = detail;
  }
  final prior = previous.evidence;
  final current = result.evidence;
  final evidence = prior == null || current == null
      ? current
      : DataEvidence(
          accountId: current.accountId,
          origin:
              prior.origin == DataOrigin.online &&
                  current.origin == DataOrigin.online
              ? DataOrigin.online
              : DataOrigin.mixed,
          fetchedAt: prior.fetchedAt.isBefore(current.fetchedAt)
              ? prior.fetchedAt
              : current.fetchedAt,
          complete: false,
          savedForOffline: false,
          cacheFailure: current.cacheFailure ?? prior.cacheFailure,
        );
  final details = [
    for (final detail in rows.values)
      FeatureDetail(
        title: detail.title,
        subtitle: detail.subtitle,
        fields: detail.fields,
        presentation: detail.presentation,
        readNavigation: detail.readNavigation,
      ),
  ];
  final summary = '${details.length}项希冀作业，部分范围待更新';
  final error = result.error;
  return error != null
      ? FeatureResult.partial(
          error: error,
          summary: summary,
          details: details,
          evidence: evidence,
          resolvedRoute: result.resolvedRoute,
        )
      : FeatureResult.success(
          summary: summary,
          details: details,
          evidence: evidence,
          resolvedRoute: result.resolvedRoute,
        );
}

(String, String)? controllerJudgeDetailKey(FeatureDetail detail) {
  if (detail.presentation case final JudgeAssignmentPresentation item)
    return controllerJudgeNonEmptyKey(item.courseId, item.assignmentId);
  final navigation = detail.readNavigation;
  if (navigation?.feature != FeatureId.judge ||
      navigation?.query.view != FeatureQueryView.judgeDetail)
    return null;
  final query = navigation!.query;
  return controllerJudgeNonEmptyKey(query.courseId, query.assignmentId);
}

(String, String)? controllerJudgeNonEmptyKey(
  String? course,
  String? assignment,
) =>
    course == null ||
        course.trim().isEmpty ||
        assignment == null ||
        assignment.trim().isEmpty
    ? null
    : (course, assignment);
