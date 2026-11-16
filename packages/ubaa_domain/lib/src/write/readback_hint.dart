import 'package:meta/meta.dart';
import '../common/route.dart';
import '../feature/catalog.dart';
import 'intent.dart';

/// 重启后仅供核对的最小提示，不包含目标、意图或可提交材料。
@immutable
class WriteReadbackHint {
  const WriteReadbackHint({
    required this.id,
    required this.operation,
    required this.route,
    required this.startedAt,
  });
  final String id;
  final WriteOperation operation;
  final ConnectionMode route;
  final DateTime startedAt;

  FeatureId? get feature => operation.feature;
}
