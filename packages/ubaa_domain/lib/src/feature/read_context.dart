import 'query.dart';

/// 读取结果的参数归属和生命周期，不包含上游响应或写入资格。
final class FeatureReadContext {
  FeatureReadContext({FeatureQuery? query, required this.requestRevision})
    : query = query?.copyWith(
        judgeKeys: List<JudgeAssignmentQueryKey>.unmodifiable(query.judgeKeys),
      );

  /// null 表示 backend.loadFeature，不等同显式 summary 查询。
  final FeatureQuery? query;
  final int requestRevision;

  bool hasSameQuery(FeatureQuery? other) => query == null
      ? other == null
      : other != null && query!.hasSameParameters(other);
}
