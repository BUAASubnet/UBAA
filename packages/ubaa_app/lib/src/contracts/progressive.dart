import 'package:ubaa_domain/ubaa_domain.dart';

/// 可分段读取的 backend；未支持的领域返回 null，继续使用原 typed 读取。
abstract interface class ProgressiveReadBackend {
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  );
}

abstract interface class FeatureReadTask {
  Future<FeatureReadBatch> next();
  void cancel();
}

final class FeatureReadBatch {
  const FeatureReadBatch(
    this.result, {
    required this.finished,
    this.publish = true,
  });
  final FeatureResult result;
  final bool finished;

  /// 中间准备步骤不替换当前页面已显示的目标内容。
  final bool publish;
}
