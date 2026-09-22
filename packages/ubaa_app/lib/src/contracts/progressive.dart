import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

/// 可分段读取的 backend；未支持的领域返回 null，继续使用原 typed 读取。
abstract interface class ProgressiveReadBackend {
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  );
}

/// 密钥不可用时也传递本机身份范围，认证与持久化能力分别判断。
abstract interface class AccountScopedProgressiveReadBackend
    implements ProgressiveReadBackend {
  Future<FeatureReadTask?> beginAccountFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
    LocalAccount account,
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
