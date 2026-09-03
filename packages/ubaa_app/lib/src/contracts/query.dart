import 'package:ubaa_domain/ubaa_domain.dart';

/// 支持领域筛选/服务端分页的可选 backend 能力。
///
/// 保留与 [UbaaBackend] 分离的接口，确保旧版 fake backend 不必伪造查询能力；
/// 生产 bridge backend 实现该接口并将参数 typed 传入 Core。
abstract interface class FeatureQueryBackend {
  Future<FeatureResult> loadFeatureQuery(FeatureId feature, FeatureQuery query);
}
