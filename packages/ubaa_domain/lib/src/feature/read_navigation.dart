import 'catalog.dart';
import 'query.dart';

/// 用户明确点击后才执行的公开只读查询；不包含写入意图或权限。
final class FeatureReadNavigation {
  const FeatureReadNavigation({required this.feature, required this.query});

  final FeatureId feature;
  final FeatureQuery query;
}
