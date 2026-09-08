/// 只读结果的集合级统计，不从局部搜索或分页重新计算。
sealed class FeatureOverview {
  const FeatureOverview();
}

final class SpocTermOverview extends FeatureOverview {
  const SpocTermOverview({required this.termCode, this.termName});
  final String termCode;
  final String? termName;
}

final class EvaluationProgressOverview extends FeatureOverview {
  const EvaluationProgressOverview({
    required this.totalCourses,
    required this.evaluatedCourses,
    required this.pendingCourses,
  });
  final int totalCourses;
  final int evaluatedCourses;
  final int pendingCourses;
}
