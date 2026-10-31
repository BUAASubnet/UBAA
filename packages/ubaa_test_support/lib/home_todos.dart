import 'package:ubaa_domain/ubaa_domain.dart';

/// 界面测试的已投影结果替身：只搬运合成标题和导航，不实现学校筛选或时间算法。
Future<HomeTodoProjection> homeTodoFixture(
  HomeTodoRequest request, {
  bool visible = true,
  Map<String, String> statuses = const {},
}) async => HomeTodoProjection([
  if (visible)
    for (final source in request.snapshots.values)
      for (final detail in source.details)
        if (_navigation(source.feature, detail.presentation)
            case final navigation?)
          HomeTodo(
            id: '${source.feature.name}:${detail.title}',
            feature: source.feature,
            title: detail.title,
            subtitle: switch (detail.presentation) {
              SpocAssignmentPresentation p => [
                p.courseName,
                p.teacherName,
              ].whereType<String>().join(' · '),
              _ => detail.subtitle ?? '合成来源',
            },
            statusLabel: statuses[detail.title] ?? '',
            timeLabel: '明天 12:00 截止',
            sortTime: request.now,
            navigation: navigation,
            signinAction:
                source.status == FeatureLoadStatus.success &&
                    source.evidence?.origin != DataOrigin.persisted
                ? detail.action<SigninPerformAction>()
                : null,
          ),
]);
FeatureReadNavigation? _navigation(FeatureId feature, FeaturePresentation? p) {
  final query = switch (p) {
    BykcChosenPresentation p => FeatureQuery(
      view: FeatureQueryView.bykcDetail,
      courseId: '${p.courseId}',
    ),
    SpocAssignmentPresentation p => FeatureQuery(
      view: FeatureQueryView.spocDetail,
      assignmentId: p.assignmentId,
    ),
    JudgeAssignmentPresentation p => FeatureQuery(
      view: FeatureQueryView.judgeDetail,
      courseId: p.courseId,
      assignmentId: p.assignmentId,
    ),
    CgyyOrderPresentation() => const FeatureQuery(
      view: FeatureQueryView.cgyyOrders,
    ),
    SigninPresentation() => const FeatureQuery(
      view: FeatureQueryView.signinPending,
    ),
    ExamPresentation() => const FeatureQuery(
      view: FeatureQueryView.examArranged,
    ),
    _ => null,
  };
  return query == null
      ? null
      : FeatureReadNavigation(feature: feature, query: query);
}
